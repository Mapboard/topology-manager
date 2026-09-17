/*
Element-level CRUD for map faces.

A map face is a face-based topogeometry: a set of topology primitives (faces)
recorded as rows in the `relation` table, plus a cached `geometry` and an
identity. Historically the update pipeline only ever *created* and *deleted*
whole map faces; this file adds the operations needed to move primitives
between existing faces instead, so that the cost of a change is proportional to
the change rather than to the size of the neighbouring faces:

- `map_face_absorb(faces, layer)`  — settle a dissolved component onto one
  surviving map face: pick the survivor, add the component's missing primitives
  to it, take the component's primitives away from every other face that held
  them (deleting faces that become empty), and refresh the survivor's geometry
  and identity. Creates a new face only when no existing face overlaps.
- `map_face_release(faces, layer)` — take primitives away from any map face
  holding them (used for components that contain the universal face, which
  never get a map face of their own).
- `map_face_replace(faces, layer)` — the legacy behaviour: delete every
  overlapping face and create one new face. Kept as a configurable fallback.
- `map_face_create` / `map_face_delete` — the primitives underneath.

Every operation that takes primitives away from a face re-marks the face's
*remaining* primitives as dirty. The caller's loop picks them up, so a face whose
remainder is disconnected is split into one row per connected component, and a
face that would otherwise be left without a map face ("the hole") is rebuilt.
Every delete path clears the topogeometry first, so no `relation` rows are
orphaned.

Geometry is recomputed incrementally. The stored geometry of a map face is
trusted except within the run's *reshaped region* — the union of the primitives
that were dirty when the run started (registered per layer by
`set_reshaped_faces`). Those primitives are the only ones whose shape can have
changed since the face was persisted, so anything outside that region can be
reused, and only the primitives that moved or were reshaped are resolved from
the topology. Without registered information the functions fall back to a full
resolution, which is always correct.

Note: relation rows are inserted/deleted directly (set-based) rather than
through `TopoGeom_addElement` / `TopoGeom_remElement`, which do exactly the
same thing one element at a time.
*/

/* ------------------------------------------------------------------------- */
/* Geometry helpers                                                          */
/* ------------------------------------------------------------------------- */

/** Resolve a set of topology primitives to a single MultiPolygon (NULL for an
empty set). This is the authoritative — and expensive — path. */
CREATE OR REPLACE FUNCTION {topo_schema}.__faces_geometry(_faces integer[])
RETURNS geometry AS $$
  SELECT ST_Multi(ST_CollectionExtract(ST_UnaryUnion(ST_Collect(
           ST_SetSRID(topology.ST_GetFaceGeometry({topo_name_literal}, f.face_id), {srid_literal})
         )), 3))
  FROM unnest(_faces) AS f(face_id)
  JOIN {topo_schema}.face fc ON fc.face_id = f.face_id
  WHERE f.face_id IS NOT NULL AND f.face_id <> 0;
$$ LANGUAGE SQL STABLE;

/** `_geom` minus `_minus`, tolerating NULL/empty operands. */
CREATE OR REPLACE FUNCTION {topo_schema}.__geometry_minus(_geom geometry, _minus geometry)
RETURNS geometry AS $$
  SELECT CASE
    WHEN _geom IS NULL THEN NULL
    WHEN _minus IS NULL OR ST_IsEmpty(_minus) OR NOT ST_Intersects(_geom, _minus) THEN _geom
    ELSE ST_Multi(ST_CollectionExtract(ST_Difference(_geom, _minus), 3))
  END;
$$ LANGUAGE SQL IMMUTABLE;

/** `_a` union `_b`, tolerating NULL/empty operands. */
CREATE OR REPLACE FUNCTION {topo_schema}.__geometry_plus(_a geometry, _b geometry)
RETURNS geometry AS $$
  SELECT CASE
    WHEN _a IS NULL OR ST_IsEmpty(_a) THEN _b
    WHEN _b IS NULL OR ST_IsEmpty(_b) THEN _a
    ELSE ST_Multi(ST_CollectionExtract(ST_Union(_a, _b), 3))
  END;
$$ LANGUAGE SQL IMMUTABLE;

/* ------------------------------------------------------------------------- */
/* Reshaped primitives (per update run)                                      */
/* ------------------------------------------------------------------------- */

/** Register, for the current session, the primitives of a layer whose shape may
have changed since the layer's map faces were last persisted — i.e. the faces
that were dirty when the update run started. Primitives that are re-marked dirty
*during* the run (because they were shed from a face) are deliberately not
reshaped: their geometry is still trustworthy. */
CREATE OR REPLACE FUNCTION {topo_schema}.set_reshaped_faces(_map_layer integer, _faces integer[])
RETURNS integer AS $$
DECLARE
  _n integer;
BEGIN
  -- Session-scoped scratch tables (the caller commits per batch, so no ON COMMIT DROP).
  CREATE TEMP TABLE IF NOT EXISTS _reshaped_layers (map_layer integer PRIMARY KEY);
  CREATE TEMP TABLE IF NOT EXISTS _reshaped_faces (
    map_layer integer NOT NULL,
    face_id integer NOT NULL,
    PRIMARY KEY (map_layer, face_id)
  );
  CREATE TEMP TABLE IF NOT EXISTS _reshaped_region (map_layer integer PRIMARY KEY, geometry geometry);

  DELETE FROM _reshaped_faces WHERE map_layer = _map_layer;
  DELETE FROM _reshaped_region WHERE map_layer = _map_layer;
  INSERT INTO _reshaped_layers VALUES (_map_layer) ON CONFLICT DO NOTHING;

  INSERT INTO _reshaped_faces (map_layer, face_id)
  SELECT DISTINCT _map_layer, f.face_id
  FROM unnest(_faces) AS f(face_id)
  WHERE f.face_id IS NOT NULL AND f.face_id <> 0;
  GET DIAGNOSTICS _n = ROW_COUNT;
  RETURN _n;
END;
$$ LANGUAGE plpgsql;

/** Forget all registered reshaped primitives (end of an update run). */
CREATE OR REPLACE FUNCTION {topo_schema}.clear_reshaped_faces()
RETURNS void AS $$
BEGIN
  DROP TABLE IF EXISTS _reshaped_region;
  DROP TABLE IF EXISTS _reshaped_faces;
  DROP TABLE IF EXISTS _reshaped_layers;
END;
$$ LANGUAGE plpgsql;

/** Whether reshaped-primitive information was registered for a layer. */
CREATE OR REPLACE FUNCTION {topo_schema}.__has_reshaped_info(_map_layer integer)
RETURNS boolean AS $$
BEGIN
  IF to_regclass('pg_temp._reshaped_layers') IS NULL THEN
    RETURN false;
  END IF;
  RETURN EXISTS (SELECT 1 FROM _reshaped_layers WHERE map_layer = _map_layer);
END;
$$ LANGUAGE plpgsql;

/** The union of a layer's reshaped primitives (computed once per layer and
cached for the session). NULL when there are none. */
CREATE OR REPLACE FUNCTION {topo_schema}.__reshaped_region(_map_layer integer)
RETURNS geometry AS $$
DECLARE
  _geom geometry;
BEGIN
  SELECT geometry INTO _geom FROM _reshaped_region WHERE map_layer = _map_layer;
  IF FOUND THEN
    RETURN _geom;
  END IF;
  _geom := {topo_schema}.__faces_geometry(
    array(SELECT face_id FROM _reshaped_faces WHERE map_layer = _map_layer)
  );
  INSERT INTO _reshaped_region (map_layer, geometry) VALUES (_map_layer, _geom);
  RETURN _geom;
END;
$$ LANGUAGE plpgsql;

/* ------------------------------------------------------------------------- */
/* Queries                                                                   */
/* ------------------------------------------------------------------------- */

/** The map faces of a layer that hold any of the given primitives, with the
breakdown of each face's primitives into those inside the set (`shared`) and
those outside it (`outside`).

The set is staged in an indexed, analyzed temp table: joined straight from
`unnest()` the planner underestimates it and nested-loops thousands of
primitives against thousands of relation rows. */
CREATE OR REPLACE FUNCTION {topo_schema}.map_face_overlaps(_faces integer[], _map_layer integer)
RETURNS TABLE (
  map_face integer,
  shared integer[],
  outside integer[],
  n_shared integer,
  n_outside integer
) AS $$
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _mfo_component (face_id integer PRIMARY KEY);
  TRUNCATE _mfo_component;
  INSERT INTO _mfo_component (face_id)
  SELECT DISTINCT f.face_id FROM unnest(_faces) AS f(face_id) WHERE f.face_id IS NOT NULL;
  ANALYZE _mfo_component;

  RETURN QUERY
  WITH candidates AS (
    SELECT DISTINCT mf.id, (mf.topo).id AS topogeo_id, (mf.topo).layer_id AS layer_id
    FROM {topo_schema}.map_face mf
    JOIN {topo_schema}.relation r
      ON r.topogeo_id = (mf.topo).id
     AND r.layer_id = (mf.topo).layer_id
     AND r.element_type = 3
    JOIN _mfo_component c ON c.face_id = r.element_id
    WHERE mf.map_layer = _map_layer
  ),
  members AS (
    SELECT
      mf.id AS map_face,
      r.element_id AS face_id,
      c.face_id IS NOT NULL AS inside
    FROM candidates mf
    JOIN {topo_schema}.relation r
      ON r.topogeo_id = mf.topogeo_id
     AND r.layer_id = mf.layer_id
     AND r.element_type = 3
    LEFT JOIN _mfo_component c ON c.face_id = r.element_id
  )
  SELECT
    m.map_face,
    coalesce(array_agg(m.face_id ORDER BY m.face_id) FILTER (WHERE m.inside), ARRAY[]::integer[]),
    coalesce(array_agg(m.face_id ORDER BY m.face_id) FILTER (WHERE NOT m.inside), ARRAY[]::integer[]),
    (count(*) FILTER (WHERE m.inside))::integer,
    (count(*) FILTER (WHERE NOT m.inside))::integer
  FROM members m
  GROUP BY m.map_face
  ORDER BY m.map_face;
END;
$$ LANGUAGE plpgsql;

/** Primitives of the map_face layer's relation rows that no map face refers to
(should always be zero: every delete path clears the topogeometry first). */
CREATE OR REPLACE FUNCTION {topo_schema}.orphaned_map_face_relations()
RETURNS integer AS $$
  SELECT count(*)::integer
  FROM {topo_schema}.relation r
  WHERE r.layer_id = {topo_schema}.__map_face_layer_id()
    AND NOT EXISTS (
      SELECT 1 FROM {topo_schema}.map_face mf
      WHERE (mf.topo).id = r.topogeo_id
        AND (mf.topo).layer_id = r.layer_id
    );
$$ LANGUAGE SQL STABLE;

/* ------------------------------------------------------------------------- */
/* Create / delete                                                           */
/* ------------------------------------------------------------------------- */

/** Create a map face over a set of primitives. The geometry is resolved from the
topology unless the caller already assembled it (`_geometry`); identity is
resolved from the geometry. Returns the new face id. */
-- An earlier revision had no geometry argument; drop it so the call is unambiguous.
DROP FUNCTION IF EXISTS {topo_schema}.map_face_create(integer[], integer);
CREATE OR REPLACE FUNCTION {topo_schema}.map_face_create(
  _faces integer[],
  _map_layer integer,
  _geometry geometry DEFAULT NULL
)
RETURNS integer AS $$
DECLARE
  _id integer;
  _elements integer[][];
BEGIN
  SELECT array_agg(ARRAY[f.face_id, 3])
  INTO _elements
  FROM (SELECT DISTINCT face_id FROM unnest(_faces) AS f(face_id) WHERE face_id <> 0) f;

  IF _elements IS NULL THEN
    RETURN NULL;
  END IF;

  INSERT INTO {topo_schema}.map_face ({face_identity_column}, topo, map_layer, geometry)
  SELECT
    {topo_schema}.identity_for_area(g.geom, _map_layer),
    t.topo,
    _map_layer,
    g.geom
  FROM (
    SELECT topology.createTopoGeom(
      {topo_name_literal}, 3, {topo_schema}.__map_face_layer_id(), _elements
    ) AS topo
  ) t,
  LATERAL (
    SELECT coalesce(_geometry, ST_Multi(ST_SetSRID(t.topo::geometry, {srid_literal})))
  ) g(geom)
  RETURNING id INTO _id;

  PERFORM {topo_schema}.register_face_identity(_id);
  RETURN _id;
END;
$$ LANGUAGE plpgsql;

/** Delete map faces, clearing their topogeometries first so that no relation
rows are left behind. Returns the number of faces deleted. */
CREATE OR REPLACE FUNCTION {topo_schema}.map_face_delete(_map_faces integer[])
RETURNS integer AS $$
DECLARE
  _n integer;
BEGIN
  PERFORM topology.clearTopoGeom(mf.topo)
  FROM {topo_schema}.map_face mf
  WHERE mf.id = ANY(_map_faces) AND mf.topo IS NOT NULL;

  DELETE FROM {topo_schema}.map_face WHERE id = ANY(_map_faces);
  GET DIAGNOSTICS _n = ROW_COUNT;
  RETURN _n;
END;
$$ LANGUAGE plpgsql;

/* ------------------------------------------------------------------------- */
/* Moving primitives                                                         */
/* ------------------------------------------------------------------------- */

DROP TYPE IF EXISTS {topo_schema}.map_face_change CASCADE;
/** What an element-level operation did to the map faces of a layer. */
CREATE TYPE {topo_schema}.map_face_change AS (
  map_face integer,     -- the face now holding the component (NULL when released)
  created boolean,      -- whether map_face was newly created
  added integer[],      -- primitives added to map_face
  removed integer[],    -- primitives taken away from map_face (its former remainder)
  deleted integer[],    -- map faces that became empty and were deleted
  shed integer[],       -- map faces that lost primitives but survive (to be revisited)
  reseeded integer[]    -- primitives re-marked dirty for the caller to process
);

/** Whether a face's remainder is still one connected piece after `_removed`
was taken away from it, decided *locally*.

Every piece of the remainder must contain a primitive adjacent to the removed
set (the face was one connected component before). So it is enough to walk the
joinable graph, restricted to the remainder, from one of those neighbours until
all of them have been reached: for a small change against a
large face this touches only the surroundings of the change and stops, instead
of walking the whole face. Returns false as soon as the walk exhausts without
reaching every neighbour (the remainder is split) — and, conservatively, when it
cannot tell. */
CREATE OR REPLACE FUNCTION {topo_schema}.__remainder_connected(
  _remaining integer[],
  _removed integer[],
  _map_layer integer
)
RETURNS boolean AS $$
DECLARE
  _boundary_layers integer[];
  _n_targets integer;
  _n_reached integer;
  _added integer;
  _niter integer := 0;
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _rc_remaining (face_id integer PRIMARY KEY);
  CREATE TEMP TABLE IF NOT EXISTS _rc_removed   (face_id integer PRIMARY KEY);
  CREATE TEMP TABLE IF NOT EXISTS _rc_target    (face_id integer PRIMARY KEY);
  CREATE TEMP TABLE IF NOT EXISTS _rc_seen      (face_id integer PRIMARY KEY);
  CREATE TEMP TABLE IF NOT EXISTS _rc_frontier  (face_id integer PRIMARY KEY);
  CREATE TEMP TABLE IF NOT EXISTS _rc_next      (face_id integer PRIMARY KEY);
  TRUNCATE _rc_remaining, _rc_removed, _rc_target, _rc_seen, _rc_frontier, _rc_next;

  INSERT INTO _rc_remaining SELECT DISTINCT f.face_id FROM unnest(_remaining) AS f(face_id);
  INSERT INTO _rc_removed   SELECT DISTINCT f.face_id FROM unnest(_removed)   AS f(face_id);
  ANALYZE _rc_remaining;

  _boundary_layers := array(
    SELECT DISTINCT p.id FROM {topo_schema}.constraining_layers(_map_layer) AS p(id)
  );

  -- The remaining primitives adjacent to the removed set. Plain edge adjacency,
  -- not joinability: the removed set usually stopped being joinable to the
  -- remainder (that is why it left), but every piece of the remainder still
  -- touches it across some edge, since the face was connected before.
  INSERT INTO _rc_target (face_id)
  SELECT DISTINCT r.face_id
  FROM {topo_schema}.edge_data e
  JOIN _rc_removed d ON d.face_id IN (e.left_face, e.right_face)
  JOIN _rc_remaining r ON r.face_id IN (e.left_face, e.right_face)
  WHERE e.left_face <> e.right_face;

  SELECT count(*) INTO _n_targets FROM _rc_target;
  IF _n_targets = 0 THEN
    RETURN false;  -- cannot tell; let the caller do the full walk
  END IF;
  IF _n_targets = 1 THEN
    RETURN true;
  END IF;

  INSERT INTO _rc_seen     SELECT face_id FROM _rc_target ORDER BY face_id LIMIT 1;
  INSERT INTO _rc_frontier SELECT face_id FROM _rc_seen;

  LOOP
    SELECT count(*) INTO _n_reached FROM _rc_target t JOIN _rc_seen s ON s.face_id = t.face_id;
    IF _n_reached = _n_targets THEN
      RETURN true;
    END IF;

    TRUNCATE _rc_next;
    INSERT INTO _rc_next (face_id)
    SELECT DISTINCT j.opp_face
    FROM (
      SELECT
        fe.opp_face, fe.left_face, fe.right_face,
        array_remove(array_agg(er.map_layer), null) AS edge_layers
      FROM (
        SELECT e.edge_id, e.left_face, e.right_face, e.right_face AS opp_face
        FROM {topo_schema}.edge_data e
        JOIN _rc_frontier f ON e.left_face = f.face_id
        WHERE e.left_face <> e.right_face
        UNION ALL
        SELECT e.edge_id, e.left_face, e.right_face, e.left_face AS opp_face
        FROM {topo_schema}.edge_data e
        JOIN _rc_frontier f ON e.right_face = f.face_id
        WHERE e.left_face <> e.right_face
      ) fe
      JOIN _rc_remaining r ON r.face_id = fe.opp_face
      LEFT JOIN _rc_seen s ON s.face_id = fe.opp_face
      LEFT JOIN {topo_schema}.__edge_relation er ON er.edge_id = fe.edge_id
      WHERE s.face_id IS NULL
      GROUP BY fe.edge_id, fe.left_face, fe.right_face, fe.opp_face
    ) j
    WHERE (
            NOT (j.edge_layers && _boundary_layers)
         OR array_length(j.edge_layers, 1) = 0
         OR array_length(_boundary_layers, 1) = 0
          )
       OR {topo_schema}.faces_are_joinable(j.left_face, j.right_face, _map_layer);

    GET DIAGNOSTICS _added = ROW_COUNT;
    IF _added = 0 THEN
      RETURN false;  -- exhausted a piece without reaching every neighbour: split
    END IF;

    INSERT INTO _rc_seen SELECT face_id FROM _rc_next;
    TRUNCATE _rc_frontier;
    INSERT INTO _rc_frontier SELECT face_id FROM _rc_next;
    _niter := _niter + 1;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

/** Take `_faces` away from one map face.

If nothing remains, the face is deleted (returns NULL). If the remainder is
trustworthy (no reshaped primitives) and `__remainder_connected` shows it is
still one piece, the face is settled in place — geometry subtracted, identity
re-resolved — and nothing is re-marked dirty (returns an empty array).
Otherwise the remaining primitives are re-marked dirty so the caller revisits
them, rebuilding geometry and identity and splitting the face if needed
(returns them). With `_update_geometry` false the cached geometry is left for
the caller to set and the remainder is always re-marked. */
CREATE OR REPLACE FUNCTION {topo_schema}.__map_face_shed(
  _map_face integer,
  _faces integer[],
  _map_layer integer,
  _update_geometry boolean DEFAULT true
)
RETURNS integer[] AS $$
DECLARE
  _topo_id integer;
  _layer_id integer;
  _geom geometry;
  _removed integer[];
  _remaining integer[];
  _has_info boolean;
  _trusted boolean := false;
  _old_identity {topo_schema}.map_face.{face_identity_column}%TYPE;
  _new_identity {topo_schema}.map_face.{face_identity_column}%TYPE;
BEGIN
  SELECT (topo).id, (topo).layer_id, geometry, {face_identity_column}
  INTO _topo_id, _layer_id, _geom, _old_identity
  FROM {topo_schema}.map_face WHERE id = _map_face;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  WITH gone AS (
    DELETE FROM {topo_schema}.relation r
    USING (SELECT DISTINCT face_id FROM unnest(_faces) AS f(face_id)) f
    WHERE r.topogeo_id = _topo_id
      AND r.layer_id = _layer_id
      AND r.element_type = 3
      AND r.element_id = f.face_id
    RETURNING r.element_id
  )
  SELECT coalesce(array_agg(element_id), ARRAY[]::integer[]) INTO _removed FROM gone;

  IF cardinality(_removed) = 0 THEN
    RETURN array(
      SELECT element_id FROM {topo_schema}.relation r
      WHERE r.topogeo_id = _topo_id AND r.layer_id = _layer_id AND r.element_type = 3
    );
  END IF;

  DELETE FROM {topo_schema}.face_identity
  WHERE map_face = _map_face AND map_layer = _map_layer AND face_id = ANY(_removed);

  _remaining := array(
    SELECT element_id FROM {topo_schema}.relation r
    WHERE r.topogeo_id = _topo_id AND r.layer_id = _layer_id AND r.element_type = 3
    ORDER BY element_id
  );

  IF cardinality(_remaining) = 0 THEN
    PERFORM {topo_schema}.map_face_delete(ARRAY[_map_face]);
    RETURN NULL;
  END IF;

  _has_info := {topo_schema}.__has_reshaped_info(_map_layer);
  IF _has_info AND _geom IS NOT NULL THEN
    -- The remainder's stored geometry can be trusted when none of it was reshaped
    _trusted := NOT EXISTS (
      SELECT 1 FROM _reshaped_faces rf
      WHERE rf.map_layer = _map_layer AND rf.face_id = ANY(_remaining)
    );
  END IF;

  IF _update_geometry THEN
    IF NOT _has_info
       OR _geom IS NULL
       OR cardinality(_remaining) < cardinality(_removed) THEN
      -- Resolving the remainder is authoritative, and cheaper when it is small.
      _geom := {topo_schema}.__faces_geometry(_remaining);
    ELSE
      -- Subtract what left; reshaped areas are subtracted too and re-resolved
      -- when the remainder is revisited.
      _geom := {topo_schema}.__geometry_minus(
        _geom,
        {topo_schema}.__geometry_plus(
          {topo_schema}.__faces_geometry(_removed),
          {topo_schema}.__reshaped_region(_map_layer)
        )
      );
    END IF;
    UPDATE {topo_schema}.map_face SET geometry = _geom WHERE id = _map_face;
  END IF;

  -- Derived (composite-layer) copies of this face are stale; they are rebuilt
  -- by the composite update, exactly as if the face had been recreated.
  DELETE FROM {topo_schema}.map_face WHERE source_id = _map_face;

  -- Short-circuit: a trustworthy remainder that is still one piece is settled
  -- here, without re-marking it dirty (which would walk the whole remainder).
  IF _update_geometry AND _trusted
     AND {topo_schema}.__remainder_connected(_remaining, _removed, _map_layer) THEN
    _new_identity := {topo_schema}.identity_for_area(_geom, _map_layer);
    IF _new_identity IS DISTINCT FROM _old_identity THEN
      UPDATE {topo_schema}.map_face SET {face_identity_column} = _new_identity WHERE id = _map_face;
      PERFORM {topo_schema}.register_face_identity(_map_face);
    END IF;
    RETURN ARRAY[]::integer[];
  END IF;

  INSERT INTO {topo_schema}.dirty_face (id, map_layer)
  SELECT f.face_id, _map_layer FROM unnest(_remaining) AS f(face_id)
  ON CONFLICT DO NOTHING;

  RETURN _remaining;
END;
$$ LANGUAGE plpgsql;

/** Take a set of primitives away from every map face of a layer that holds
them. Used for components that include the universal face (which never get a
map face). */
CREATE OR REPLACE FUNCTION {topo_schema}.map_face_release(_faces integer[], _map_layer integer)
RETURNS {topo_schema}.map_face_change AS $$
DECLARE
  _o record;
  _remaining integer[];
  _res {topo_schema}.map_face_change;
BEGIN
  _res.map_face := NULL;
  _res.created := false;
  _res.added := ARRAY[]::integer[];
  _res.removed := ARRAY[]::integer[];
  _res.deleted := ARRAY[]::integer[];
  _res.shed := ARRAY[]::integer[];
  _res.reseeded := ARRAY[]::integer[];

  FOR _o IN SELECT * FROM {topo_schema}.map_face_overlaps(_faces, _map_layer) LOOP
    _remaining := {topo_schema}.__map_face_shed(_o.map_face, _o.shared, _map_layer, true);
    IF _remaining IS NULL THEN
      _res.deleted := _res.deleted || _o.map_face;
    ELSE
      _res.shed := _res.shed || _o.map_face;
      _res.reseeded := _res.reseeded || _remaining;
    END IF;
  END LOOP;
  RETURN _res;
END;
$$ LANGUAGE plpgsql;

/** Settle a dissolved component (a maximal set of joinable primitives) onto a
single map face by moving primitives rather than recreating faces.

1. Find the existing faces holding any of the component's primitives.
   None → create a new face.
2. Assemble the component's geometry: stored geometries of faces that lie
   (mostly) inside the component are reused outside the reshaped region; the
   remaining primitives are resolved from the topology. Resolve the identity.
3. Choose the survivor: an overlapping face with the same identity if there is
   one (most shared primitives first), else a face lying entirely inside the
   component. A face that extends beyond the component with a different
   identity is never taken over — it keeps its row for its remainder.
4. Every other overlapping face sheds the component's primitives (deleted when
   emptied, re-marked dirty otherwise). With no survivor a new face is created
   from the assembled geometry; otherwise the survivor sheds its primitives
   outside the component (re-marked dirty) and gains the component's missing
   ones. Its geometry and identity are refreshed and `face_identity` updated.
*/
CREATE OR REPLACE FUNCTION {topo_schema}.map_face_absorb(_faces integer[], _map_layer integer)
RETURNS {topo_schema}.map_face_change AS $$
DECLARE
  _has_info boolean;
  _region geometry;
  _geom geometry;
  _identity {topo_schema}.map_face.{face_identity_column}%TYPE;
  _survivor integer;
  _topo_id integer;
  _layer_id integer;
  _o record;
  _remaining integer[];
  _resolve integer[];
  _s_outside integer[];
  _res {topo_schema}.map_face_change;
BEGIN
  IF 0 = ANY(_faces) THEN
    RAISE EXCEPTION 'A component containing the universal face cannot be absorbed into a map face';
  END IF;

  _res.created := false;
  _res.added := ARRAY[]::integer[];
  _res.removed := ARRAY[]::integer[];
  _res.deleted := ARRAY[]::integer[];
  _res.shed := ARRAY[]::integer[];
  _res.reseeded := ARRAY[]::integer[];

  -- Session-scoped scratch tables, reused across calls.
  CREATE TEMP TABLE IF NOT EXISTS _mfc_component (
    face_id integer PRIMARY KEY,
    reshaped boolean NOT NULL DEFAULT true
  );
  CREATE TEMP TABLE IF NOT EXISTS _mfc_overlap (
    map_face integer PRIMARY KEY,
    shared integer[],
    outside integer[],
    n_shared integer,
    n_outside integer,
    reuse boolean
  );
  TRUNCATE _mfc_component, _mfc_overlap;

  INSERT INTO _mfc_component (face_id)
  SELECT DISTINCT f.face_id FROM unnest(_faces) AS f(face_id) WHERE f.face_id IS NOT NULL;

  ANALYZE _mfc_component;

  _has_info := {topo_schema}.__has_reshaped_info(_map_layer);
  IF _has_info THEN
    UPDATE _mfc_component c
    SET reshaped = EXISTS (
      SELECT 1 FROM _reshaped_faces rf
      WHERE rf.map_layer = _map_layer AND rf.face_id = c.face_id
    );
  END IF;

  -- A face's stored geometry is reusable when we know which primitives were
  -- reshaped, and it is cheaper to subtract its part outside the component
  -- than to resolve its part inside.
  INSERT INTO _mfc_overlap (map_face, shared, outside, n_shared, n_outside, reuse)
  SELECT
    o.map_face, o.shared, o.outside, o.n_shared, o.n_outside,
    _has_info AND mf.geometry IS NOT NULL AND o.n_outside < o.n_shared
  FROM {topo_schema}.map_face_overlaps(
    array(SELECT face_id FROM _mfc_component), _map_layer
  ) o
  JOIN {topo_schema}.map_face mf ON mf.id = o.map_face;

  IF NOT EXISTS (SELECT 1 FROM _mfc_overlap) THEN
    _res.map_face := {topo_schema}.map_face_create(
      array(SELECT face_id FROM _mfc_component), _map_layer
    );
    _res.created := true;
    _res.added := array(SELECT face_id FROM _mfc_component ORDER BY face_id);
    RETURN _res;
  END IF;

  -- 2. Geometry: trusted pieces of reusable faces ...
  IF EXISTS (SELECT 1 FROM _mfc_overlap WHERE reuse) THEN
    _region := {topo_schema}.__reshaped_region(_map_layer);

    SELECT ST_Union(piece) INTO _geom
    FROM (
      SELECT {topo_schema}.__geometry_minus(
        mf.geometry,
        {topo_schema}.__geometry_plus(_region, {topo_schema}.__faces_geometry(o.outside))
      ) AS piece
      FROM _mfc_overlap o
      JOIN {topo_schema}.map_face mf ON mf.id = o.map_face
      WHERE o.reuse
    ) p
    WHERE piece IS NOT NULL;
  END IF;

  -- ... plus everything reshaped or not covered by a reusable face, resolved.
  WITH covered AS (
    SELECT DISTINCT unnest(o.shared) AS face_id FROM _mfc_overlap o WHERE o.reuse
  )
  SELECT coalesce(array_agg(c.face_id), ARRAY[]::integer[])
  INTO _resolve
  FROM _mfc_component c
  LEFT JOIN covered cv ON cv.face_id = c.face_id
  WHERE c.reshaped OR cv.face_id IS NULL;

  _geom := {topo_schema}.__geometry_plus(_geom, {topo_schema}.__faces_geometry(_resolve));
  _geom := ST_Multi(_geom);
  _identity := {topo_schema}.identity_for_area(_geom, _map_layer);

  -- 3. Survivor: an overlapping face with the component's identity (most shared
  -- primitives first), else a face lying entirely inside the component (its row
  -- would otherwise be deleted). A face that extends *beyond* the component and
  -- has a different identity must not be taken over — it keeps its row for its
  -- remainder, and the component gets a new face.
  SELECT o.map_face INTO _survivor
  FROM _mfc_overlap o
  JOIN {topo_schema}.map_face mf ON mf.id = o.map_face
  WHERE mf.{face_identity_column} IS NOT DISTINCT FROM _identity
     OR o.n_outside = 0
  ORDER BY
    (mf.{face_identity_column} IS NOT DISTINCT FROM _identity) DESC,
    o.n_shared DESC,
    o.map_face ASC
  LIMIT 1;

  -- 4a. Other faces shed the component's primitives
  FOR _o IN
    SELECT * FROM _mfc_overlap
    WHERE _survivor IS NULL OR map_face <> _survivor
    ORDER BY map_face
  LOOP
    _remaining := {topo_schema}.__map_face_shed(_o.map_face, _o.shared, _map_layer, true);
    IF _remaining IS NULL THEN
      _res.deleted := _res.deleted || _o.map_face;
    ELSE
      _res.shed := _res.shed || _o.map_face;
      _res.reseeded := _res.reseeded || _remaining;
    END IF;
  END LOOP;

  IF _survivor IS NULL THEN
    _res.map_face := {topo_schema}.map_face_create(
      array(SELECT face_id FROM _mfc_component), _map_layer, _geom
    );
    _res.created := true;
    _res.added := array(SELECT face_id FROM _mfc_component ORDER BY face_id);
    RETURN _res;
  END IF;
  _res.map_face := _survivor;

  -- 4b. The survivor sheds its part outside the component ...
  SELECT outside INTO _s_outside FROM _mfc_overlap WHERE map_face = _survivor;
  IF cardinality(_s_outside) > 0 THEN
    PERFORM {topo_schema}.__map_face_shed(_survivor, _s_outside, _map_layer, false);
    _res.removed := _s_outside;
    _res.reseeded := _res.reseeded || _s_outside;
  END IF;

  -- ... and takes on the component's primitives it does not yet hold.
  SELECT (topo).id, (topo).layer_id INTO _topo_id, _layer_id
  FROM {topo_schema}.map_face WHERE id = _survivor;
  WITH ins AS (
    INSERT INTO {topo_schema}.relation (topogeo_id, layer_id, element_id, element_type)
    SELECT _topo_id, _layer_id, c.face_id, 3
    FROM _mfc_component c
    WHERE NOT EXISTS (
      SELECT 1 FROM {topo_schema}.relation r
      WHERE r.topogeo_id = _topo_id
        AND r.layer_id = _layer_id
        AND r.element_type = 3
        AND r.element_id = c.face_id
    )
    RETURNING element_id
  )
  SELECT coalesce(array_agg(element_id ORDER BY element_id), ARRAY[]::integer[])
  INTO _res.added
  FROM ins;

  UPDATE {topo_schema}.map_face
  SET geometry = _geom, {face_identity_column} = _identity
  WHERE id = _survivor;

  IF cardinality(_res.added) > 0 OR cardinality(_res.removed) > 0 THEN
    -- Derived (composite-layer) copies are stale; the composite update rebuilds them.
    DELETE FROM {topo_schema}.map_face WHERE source_id = _survivor;
  END IF;

  PERFORM {topo_schema}.register_face_identity(_survivor);
  RETURN _res;
END;
$$ LANGUAGE plpgsql;

/** Legacy behaviour: delete every map face holding any of the component's
primitives and (optionally) create a fresh face for the component. Unlike the
original implementation, the deleted faces' primitives outside the component are
re-marked dirty so they are rebuilt rather than left without a face, and the
deleted topogeometries are cleared. */
CREATE OR REPLACE FUNCTION {topo_schema}.map_face_replace(
  _faces integer[],
  _map_layer integer,
  _create boolean DEFAULT true
)
RETURNS {topo_schema}.map_face_change AS $$
DECLARE
  _o record;
  _res {topo_schema}.map_face_change;
BEGIN
  _res.map_face := NULL;
  _res.created := false;
  _res.added := ARRAY[]::integer[];
  _res.removed := ARRAY[]::integer[];
  _res.deleted := ARRAY[]::integer[];
  _res.shed := ARRAY[]::integer[];
  _res.reseeded := ARRAY[]::integer[];

  FOR _o IN SELECT * FROM {topo_schema}.map_face_overlaps(_faces, _map_layer) LOOP
    INSERT INTO {topo_schema}.dirty_face (id, map_layer)
    SELECT f.face_id, _map_layer FROM unnest(_o.outside) AS f(face_id)
    ON CONFLICT DO NOTHING;
    _res.reseeded := _res.reseeded || _o.outside;
    _res.deleted := _res.deleted || _o.map_face;
  END LOOP;

  IF cardinality(_res.deleted) > 0 THEN
    PERFORM {topo_schema}.map_face_delete(_res.deleted);
  END IF;

  IF _create AND NOT (0 = ANY(_faces)) THEN
    _res.map_face := {topo_schema}.map_face_create(_faces, _map_layer);
    _res.created := true;
    _res.added := array(SELECT DISTINCT f.face_id FROM unnest(_faces) AS f(face_id) ORDER BY 1);
  END IF;
  RETURN _res;
END;
$$ LANGUAGE plpgsql;
