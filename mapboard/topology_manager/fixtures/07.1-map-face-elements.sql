/*
Element-level CRUD for map faces.

A map face is a face-based topogeometry: a set of topology primitives (faces)
recorded as rows in the `relation` table, plus a cached `geometry` and an
identity. Historically the update pipeline only ever *created* and *deleted*
whole map faces: every dissolved component deleted the faces it overlapped and
created a fresh topogeometry. The functions here let the pipeline reuse an
existing topogeometry instead:

- `map_face_absorb(faces, layer)`  — settle a dissolved component onto one
  existing map face when one overlaps it: update that face's `relation` rows to
  hold exactly the component, re-resolve its geometry and identity from the
  topology, and take the component's primitives away from every other face that
  held them. A new topogeometry is created only when no suitable face exists.
- `map_face_release(faces, layer)` — take primitives away from any map face
  holding them (used for components that contain the universal face, which
  never get a map face of their own).
- `map_face_replace(faces, layer)` — the legacy behaviour: delete every
  overlapping face and create one new face. Kept as a configurable fallback.
- `map_face_create` / `map_face_delete` — the primitives underneath.

Geometry is always resolved from the topology (`ST_GetFaceGeometry` over the
face's primitives — the same work `createTopoGeom` + `topo::geometry` did
before). What is saved is the churn on `map_face` and `relation`: a face that
keeps most of its primitives keeps its row and its unchanged relation rows.

In `move` mode, an operation that takes primitives away from a face re-marks
*one* of the face's remaining primitives as dirty. The loop dissolves that
primitive's component and settles it onto the face; if the remainder was split,
the face sheds the other piece then, re-marking one primitive of *it*, and so on
until every piece has its own row. One seed per shed is enough, and it keeps the
dirty set from growing by the size of every face that is touched. Faces emptied
this way are deleted with their topogeometry cleared.

`replace` mode is the historical behaviour exactly: overlapping faces are deleted
with a plain `DELETE` (their `relation` rows are reclaimed by the clean step, as
before), nothing is re-marked, and a new topogeometry is created. A face whose
primitives were only partly covered by the component loses its remainder, as it
always did.

Note: relation rows are inserted/deleted directly (set-based) rather than
through `TopoGeom_addElement` / `TopoGeom_remElement`, which do exactly the
same thing one element at a time.
*/

/** Resolve a set of topology primitives to a single MultiPolygon (NULL for an
empty set). */
CREATE OR REPLACE FUNCTION {topo_schema}.__faces_geometry(_faces integer[])
RETURNS geometry AS $$
  SELECT ST_Multi(ST_CollectionExtract(ST_UnaryUnion(ST_Collect(
           ST_SetSRID(topology.ST_GetFaceGeometry({topo_name_literal}, f.face_id), {srid_literal})
         )), 3))
  FROM unnest(_faces) AS f(face_id)
  JOIN {topo_schema}.face fc ON fc.face_id = f.face_id
  WHERE f.face_id IS NOT NULL AND f.face_id <> 0;
$$ LANGUAGE SQL STABLE;

/** The identity a dissolved component takes.

With a strategy whose identity is per primitive (`bulk_identity`: its
`resolve_layer_identity` is the set form of `identity_for_face`), the dissolve
has already decided it -- a component is primitives that share one identity -- so
it is read off one of them: from the layer's identity cache when the caller has
filled it (`_use_identity_cache`, as for `dissolve_component`), else from
`identity_for_face`. Re-deriving it from the geometry was the costlier call in
settling a small component, and could name a different owner than the dissolve
joined on, which a host checking faces against its resolver then found stale on
every run. Other strategies derive a component's identity from its area. */
DROP FUNCTION IF EXISTS {topo_schema}.__component_identity(integer[], integer, geometry);
CREATE OR REPLACE FUNCTION {topo_schema}.__component_identity(
  _faces integer[],
  _map_layer integer,
  _geom geometry,
  _use_identity_cache boolean DEFAULT false
)
RETURNS {topo_schema}.map_face.{face_identity_column}%TYPE AS $$
DECLARE
  _seed integer;
  _identity {topo_schema}.map_face.{face_identity_column}%TYPE;
BEGIN
  IF NOT {bulk_identity} THEN
    RETURN {topo_schema}.identity_for_area(_geom, _map_layer);
  END IF;
  SELECT min(f.face_id) INTO _seed FROM unnest(_faces) AS f(face_id) WHERE f.face_id <> 0;
  IF NOT _use_identity_cache THEN
    RETURN {topo_schema}.identity_for_face(_seed, _map_layer);
  END IF;
  -- Absent from the cache means no owner, as it does to the dissolve.
  SELECT il.identity INTO _identity FROM _layer_identity il WHERE il.face_id = _seed;
  RETURN _identity;
END;
$$ LANGUAGE plpgsql STABLE;

/* Earlier revisions kept per-run "reshaped region" state in the session and
   assembled geometry incrementally from it; that machinery is gone. */
DROP FUNCTION IF EXISTS {topo_schema}.set_reshaped_faces(integer, integer[]);
DROP FUNCTION IF EXISTS {topo_schema}.clear_reshaped_faces();
DROP FUNCTION IF EXISTS {topo_schema}.__has_reshaped_info(integer);
DROP FUNCTION IF EXISTS {topo_schema}.__reshaped_region(integer);
DROP FUNCTION IF EXISTS {topo_schema}.__geometry_minus(geometry, geometry);
DROP FUNCTION IF EXISTS {topo_schema}.__geometry_plus(geometry, geometry);
DROP FUNCTION IF EXISTS {topo_schema}.__remainder_connected(integer[], integer[], integer);

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

/** Relation rows of the map_face layer that no map face refers to (should
always be zero: every delete path clears the topogeometry first). */
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
topology unless the caller already resolved it (`_geometry`); identity is
`__component_identity`. Returns the new face id. */
DROP FUNCTION IF EXISTS {topo_schema}.map_face_create(integer[], integer);
DROP FUNCTION IF EXISTS {topo_schema}.map_face_create(integer[], integer, geometry);
DROP FUNCTION IF EXISTS {topo_schema}.map_face_create(integer[], integer, geometry, boolean);
CREATE OR REPLACE FUNCTION {topo_schema}.map_face_create(
  _faces integer[],
  _map_layer integer,
  _geometry geometry DEFAULT NULL,
  -- Register face identity now (move mode) or leave it to the trigger /
  -- post-update step as the original pipeline did (replace mode).
  _register boolean DEFAULT true,
  _use_identity_cache boolean DEFAULT false
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
    {topo_schema}.__component_identity(_faces, _map_layer, g.geom, _use_identity_cache),
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

  IF _register THEN
    PERFORM {topo_schema}.register_face_identity(_id);
  END IF;
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
/* Updating faces in place                                                   */
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

/** Take `_faces` away from one map face's topogeometry.

If nothing remains the face is deleted (returns NULL). Otherwise *one* remaining
primitive is re-marked dirty and returned: the loop dissolves its component and
settles it onto this face, re-resolving geometry and identity; if the remainder
was split, that step sheds the other piece and re-marks one primitive of it in
turn. Nothing is resolved here, and the dirty set grows by one row per shed, not
by the size of the face. */
-- Earlier revisions took an `_update_geometry` flag; drop that signature so the
-- call is unambiguous on a re-provisioned database.
DROP FUNCTION IF EXISTS {topo_schema}.__map_face_shed(integer, integer[], integer, boolean);
DROP FUNCTION IF EXISTS {topo_schema}.__map_face_shed(integer, integer[], integer);
CREATE OR REPLACE FUNCTION {topo_schema}.__map_face_shed(
  _map_face integer,
  _faces integer[],
  _map_layer integer,
  -- Re-mark one *remaining* primitive so the loop revisits this face. The
  -- survivor of a component passes false: its remainder is the component being
  -- settled right now, and it is the *removed* primitives that need a seed.
  _reseed_remainder boolean DEFAULT true
)
RETURNS integer[] AS $$
DECLARE
  _topo_id integer;
  _layer_id integer;
  _removed integer[];
  _remaining integer[];
BEGIN
  SELECT (topo).id, (topo).layer_id
  INTO _topo_id, _layer_id
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

  _remaining := array(
    SELECT element_id FROM {topo_schema}.relation r
    WHERE r.topogeo_id = _topo_id AND r.layer_id = _layer_id AND r.element_type = 3
    ORDER BY element_id
  );

  IF cardinality(_removed) = 0 THEN
    RETURN _remaining;
  END IF;

  DELETE FROM {topo_schema}.face_identity
  WHERE map_face = _map_face AND map_layer = _map_layer AND face_id = ANY(_removed);

  IF cardinality(_remaining) = 0 THEN
    PERFORM {topo_schema}.map_face_delete(ARRAY[_map_face]);
    RETURN NULL;
  END IF;

  -- Derived (composite-layer) copies of this face are stale; they are rebuilt
  -- by the composite update, exactly as if the face had been recreated.
  DELETE FROM {topo_schema}.map_face WHERE source_id = _map_face;

  IF NOT _reseed_remainder THEN
    RETURN ARRAY[]::integer[];
  END IF;

  INSERT INTO {topo_schema}.dirty_face (id, map_layer)
  VALUES (_remaining[1], _map_layer)
  ON CONFLICT DO NOTHING;

  RETURN ARRAY[_remaining[1]];
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
    _remaining := {topo_schema}.__map_face_shed(_o.map_face, _o.shared, _map_layer);
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
single map face, reusing an existing topogeometry when one is available.

1. Resolve the component's geometry from the topology, and its identity
   (`__component_identity`) — the same work creating a face does.
2. Find the existing faces holding any of the component's primitives. None →
   create a new face.
3. Choose the face to update: an overlapping face with the same identity
   (most shared primitives first), else a face lying entirely inside the
   component (its row would otherwise be deleted). A face that extends beyond
   the component with a different identity keeps its row for its remainder,
   and the component gets a new face.
4. Every other overlapping face sheds the component's primitives (deleted when
   emptied, its remainder re-marked dirty otherwise). The chosen face sheds
   its primitives outside the component (re-marked dirty), gains the missing
   ones, and takes the resolved geometry and identity.
*/
DROP FUNCTION IF EXISTS {topo_schema}.map_face_absorb(integer[], integer);
CREATE OR REPLACE FUNCTION {topo_schema}.map_face_absorb(
  _faces integer[],
  _map_layer integer,
  _use_identity_cache boolean DEFAULT false
)
RETURNS {topo_schema}.map_face_change AS $$
DECLARE
  _geom geometry;
  _identity {topo_schema}.map_face.{face_identity_column}%TYPE;
  _survivor integer;
  _topo_id integer;
  _layer_id integer;
  _o record;
  _remaining integer[];
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

  CREATE TEMP TABLE IF NOT EXISTS _mfc_overlap (
    map_face integer PRIMARY KEY,
    shared integer[],
    outside integer[],
    n_shared integer,
    n_outside integer
  );
  TRUNCATE _mfc_overlap;
  INSERT INTO _mfc_overlap
  SELECT o.map_face, o.shared, o.outside, o.n_shared, o.n_outside
  FROM {topo_schema}.map_face_overlaps(_faces, _map_layer) o;

  -- 1. Geometry and identity, resolved from the topology
  _geom := {topo_schema}.__faces_geometry(_faces);
  _identity := {topo_schema}.__component_identity(_faces, _map_layer, _geom, _use_identity_cache);

  -- 2. No existing face → create one
  IF NOT EXISTS (SELECT 1 FROM _mfc_overlap) THEN
    _res.map_face := {topo_schema}.map_face_create(_faces, _map_layer, _geom, true, _use_identity_cache);
    _res.created := true;
    _res.added := array(SELECT DISTINCT f.face_id FROM unnest(_faces) AS f(face_id) ORDER BY 1);
    RETURN _res;
  END IF;

  -- 3. The face to update
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
    _remaining := {topo_schema}.__map_face_shed(_o.map_face, _o.shared, _map_layer);
    IF _remaining IS NULL THEN
      _res.deleted := _res.deleted || _o.map_face;
    ELSE
      _res.shed := _res.shed || _o.map_face;
      _res.reseeded := _res.reseeded || _remaining;
    END IF;
  END LOOP;

  IF _survivor IS NULL THEN
    _res.map_face := {topo_schema}.map_face_create(_faces, _map_layer, _geom, true, _use_identity_cache);
    _res.created := true;
    _res.added := array(SELECT DISTINCT f.face_id FROM unnest(_faces) AS f(face_id) ORDER BY 1);
    RETURN _res;
  END IF;
  _res.map_face := _survivor;

  -- 4b. The chosen face sheds its part outside the component. Those primitives
  -- now have no face: re-mark one of them so the loop builds one (and, if they
  -- form several pieces, the same step repeats from there).
  SELECT outside INTO _s_outside FROM _mfc_overlap WHERE map_face = _survivor;
  IF cardinality(_s_outside) > 0 THEN
    PERFORM {topo_schema}.__map_face_shed(_survivor, _s_outside, _map_layer, false);
    INSERT INTO {topo_schema}.dirty_face (id, map_layer)
    VALUES (_s_outside[1], _map_layer)
    ON CONFLICT DO NOTHING;
    _res.removed := _s_outside;
    _res.reseeded := _res.reseeded || _s_outside[1];
  END IF;

  -- ... and takes on the component's primitives it does not yet hold.
  SELECT (topo).id, (topo).layer_id INTO _topo_id, _layer_id
  FROM {topo_schema}.map_face WHERE id = _survivor;
  WITH ins AS (
    INSERT INTO {topo_schema}.relation (topogeo_id, layer_id, element_id, element_type)
    SELECT _topo_id, _layer_id, f.face_id, 3
    FROM (SELECT DISTINCT face_id FROM unnest(_faces) AS f(face_id)) f
    WHERE NOT EXISTS (
      SELECT 1 FROM {topo_schema}.relation r
      WHERE r.topogeo_id = _topo_id
        AND r.layer_id = _layer_id
        AND r.element_type = 3
        AND r.element_id = f.face_id
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

/** The historical behaviour, unchanged: delete every map face holding any of
the component's primitives with a plain DELETE (relation rows are reclaimed by
`remove_empty_topogeometries` in the clean step, as before), then create a fresh
face for the component. Nothing is re-marked dirty, so a face only partly covered
by the component loses its remainder — exactly as the original pipeline did. */
DROP FUNCTION IF EXISTS {topo_schema}.map_face_replace(integer[], integer, boolean);
CREATE OR REPLACE FUNCTION {topo_schema}.map_face_replace(
  _faces integer[],
  _map_layer integer,
  _create boolean DEFAULT true,
  _use_identity_cache boolean DEFAULT false
)
RETURNS {topo_schema}.map_face_change AS $$
DECLARE
  _res {topo_schema}.map_face_change;
BEGIN
  _res.map_face := NULL;
  _res.created := false;
  _res.added := ARRAY[]::integer[];
  _res.removed := ARRAY[]::integer[];
  _res.shed := ARRAY[]::integer[];
  _res.reseeded := ARRAY[]::integer[];

  WITH gone AS (
    DELETE FROM {topo_schema}.map_face mf
    WHERE mf.id IN (
      SELECT o.map_face FROM {topo_schema}.map_face_overlaps(_faces, _map_layer) o
    )
    RETURNING mf.id
  )
  SELECT coalesce(array_agg(id ORDER BY id), ARRAY[]::integer[]) INTO _res.deleted FROM gone;

  IF _create AND NOT (0 = ANY(_faces)) THEN
    _res.map_face := {topo_schema}.map_face_create(_faces, _map_layer, NULL, false, _use_identity_cache);
    _res.created := true;
    _res.added := array(SELECT DISTINCT f.face_id FROM unnest(_faces) AS f(face_id) ORDER BY 1);
  END IF;
  RETURN _res;
END;
$$ LANGUAGE plpgsql;
