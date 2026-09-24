/*
When `map_topology.contact` table is updated, changes should propagate
to `map_topology.map_face`
*/

/* Util functions */

CREATE OR REPLACE FUNCTION {topo_schema}.hash_geometry(geom geometry)
RETURNS uuid AS $$
SELECT md5(ST_AsBinary(geom))::uuid;
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION {topo_schema}.boundary_layer_id()
RETURNS integer AS $$
SELECT layer_id
FROM topology.layer
WHERE schema_name={data_schema_name_literal}
  AND table_name={boundary_table_literal}
  AND feature_column='topo';
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION {topo_schema}.__topo_precision()
RETURNS numeric AS $$
SELECT precision::numeric
  FROM topology.topology
  WHERE name={topo_name_literal};
$$ LANGUAGE SQL IMMUTABLE;

/** Adjacent faces (lines) or overlapping faces (polygons) for a given topogeometry */
CREATE OR REPLACE FUNCTION {topo_schema}.relevant_faces(topo topogeometry) RETURNS integer[] AS $$
WITH topo_primitives AS (
  SELECT topology.GetTopoGeomElements(topo) primitives
),
edge_faces AS (
  SELECT
    left_face,
    right_face
  FROM topo_primitives tp
  JOIN {topo_schema}.edge_data e1
    ON (
      (e1.edge_id = tp.primitives[1] AND tp.primitives[2] = 2)
      OR
      (left_face = tp.primitives[1] AND tp.primitives[2] = 3)
      OR
      (right_face = tp.primitives[1] AND tp.primitives[2] = 3)
    )
),
faces AS (
  SELECT left_face f FROM edge_faces
  UNION
  SELECT right_face f FROM edge_faces
),
unique_faces AS (
  SELECT DISTINCT f FROM faces
)
SELECT array_agg(f)
FROM unique_faces;
$$
LANGUAGE SQL IMMUTABLE;


/*
When `map_topology.contact` table is updated, changes should propagate
to `map_topology.map_face`
*/
CREATE OR REPLACE FUNCTION {topo_schema}.mark_surrounding_faces(
  line {boundary_table})
RETURNS void AS $$
DECLARE
  __faces integer[];
BEGIN
  IF (line.topo IS null) THEN
    RETURN;
  END IF;

  SELECT {topo_schema}.relevant_faces(line.topo)
  INTO __faces;

  WITH ml AS (
    SELECT {topo_schema}.dirty_layers_for(line.map_layer) id
  )
  INSERT INTO {topo_schema}.dirty_face (id, map_layer)
  SELECT
    unnest(__faces),
    ml.id
  FROM ml
  WHERE ml.id IS NOT NULL
  ON CONFLICT DO NOTHING;

  RAISE NOTICE 'Marking faces %', __faces;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION {topo_schema}.boundary_changed()
RETURNS trigger AS $$
DECLARE
  __edges integer[];
  __dest_topology integer;
BEGIN

IF (TG_OP = 'DELETE') THEN
  PERFORM {topo_schema}.mark_surrounding_faces(OLD);
  --PERFORM {topo_schema}.join_surrounding_faces(NEW)
  RETURN OLD;

  -- ON DELETE CASCADE should handle the `__edge_relation` table in this case
END IF;

__dest_topology := {topo_schema}.get_topological_map_layer(NEW);

IF (NEW.topo IS null OR __dest_topology IS null ) THEN
  -- Delete stale relations, in case we are changing the topology
  PERFORM {topo_schema}.mark_surrounding_faces(OLD);

  IF (TG_OP = 'UPDATE' AND OLD.topo IS NOT NULL AND NEW.topo IS NULL) THEN
    -- The row is giving up its topogeometry: release its primitives rather than
    -- leave relation rows that no row refers to.
    PERFORM topology.clearTopoGeom(OLD.topo);
  END IF;

  RETURN NEW;
END IF;
/* We now are working with situations where we have a topogeometry of some
   sort
*/

/* SPECIAL CASE FOR PROGRAMMATIC INSERTS (with topo defined) ONLY) */
IF (TG_OP = 'INSERT') THEN
  /*
  We will probably not have topo set on inserts most of the time, but we might
  on programmatic or eagerly-managed insertions, so it's worth a try.

  NEW method: get map faces that cover this
  PERFORM {topo_schema}.join_surrounding_faces(NEW)
  */
  PERFORM {topo_schema}.mark_surrounding_faces(NEW);
  RETURN NEW;
END IF;


/* We have changed the geometry. We need to wipe the hash and then exit */
/*   We may put in a dirty marker here instead of hashing if it seems better */
IF (NOT OLD.geometry = NEW.geometry) THEN
  NEW.geometry_hash := null;
  -- A recorded failure belongs to the old geometry
  NEW.topology_error := null;
  PERFORM {topo_schema}.mark_surrounding_faces(OLD);
  /* The topogeometry is cleared *before* the geometry is re-noded, so it never
     holds primitives from two different geometries of the same row. It keeps
     its id: re-noding accumulates into the emptied topogeometry
     (`update_boundary_topo`). A host that assigns a different topogeometry in
     the same statement is left alone. */
  IF (
    OLD.topo IS NOT NULL
    AND (NEW.topo).id = (OLD.topo).id
    AND (NEW.topo).layer_id = (OLD.topo).layer_id
  ) THEN
    NEW.topo := topology.clearTopoGeom(OLD.topo);
  END IF;
  RETURN NEW;
END IF;
/* Now we are working with situations where we have a stable geometry
   and should update the topogeometry to match
*/

IF (
  /* Hopefully this catches all topogeometry changes,
     if it doesn't we'll have to reset
  */
  (OLD.topo).id = (NEW.topo).id AND
  {topo_schema}.get_topological_map_layer(OLD) = __dest_topology
) THEN
  /* Discards cases where we aren't changing anything relevant */
  RETURN NEW;
END IF;
/* We are now working with only cases where the topogeometry was changed */

PERFORM {topo_schema}.mark_surrounding_faces(OLD);
PERFORM {topo_schema}.mark_surrounding_faces(NEW);
RETURN NEW;

END;
$$ LANGUAGE plpgsql;

/** Noding a boundary row's geometry into its topogeometry.

Two entry points, both returning the error text of a failed `toTopoGeom` (NULL on
success) and both taking the snapping tolerance as an argument, defaulting to the
topology's precision. The library never chooses a tolerance, never retries and
never alters a geometry before noding; simplification, subdivision and retry
policy are the caller's.

- `update_boundary_topo(line, tolerance)` nodes the row's whole `geometry`. On
  success `geometry_hash` records that the topogeometry was built from this
  geometry and `topology_error` is cleared; on failure `topology_error` is set.
  An existing topogeometry is emptied first (keeping its id), so the result
  always holds exactly this geometry's primitives.
- `update_boundary_topo(line, piece, tolerance)` nodes one *piece* of the row's
  geometry: the create form of `toTopoGeom` when the row has no topogeometry
  yet, the accumulate form otherwise, so the row's `topo` references the union of
  what it did before and the piece's primitives under the same id. On failure
  the row is untouched and nothing is recorded -- a piece is not a row. The
  caller sets `geometry_hash` when it considers the row complete; the library
  does not know about pieces once the call returns.

Marking faces dirty. Each call is an UPDATE of the row's `topo`, so the
`boundary_changed` trigger fires, but for an accumulating call the topogeometry
id does not change and the trigger cannot tell which primitives are new (in a
BEFORE trigger OLD and NEW resolve to the same relation rows). So the noding
call marks faces itself, from two sources that together cover every face whose
identity or geometry a piece can change:

- the primitives the piece references, via the statement-level trigger on
  `relation` inserts (`mark_boundary_relation_faces`) -- this is what catches a
  piece that adds no edges at all, e.g. a map whose bounds coincide with one
  already noded;
- the faces on either side of every edge the noding created or *modified*, from
  a snapshot of the edges near the piece taken before the call
  (`mark_noded_faces`). Noding inserts a vertex into an existing edge when a
  new line ends on it at a point that is not exactly representable, which
  changes the shape of the faces on both sides of that edge without touching a
  relation row, and the face across a T-junction is not adjacent to any new
  edge.
*/

-- Earlier revisions had a one-argument form; with a defaulted tolerance the
-- two would be ambiguous.
DROP FUNCTION IF EXISTS {topo_schema}.update_boundary_topo({boundary_table});

/** Mark dirty the faces on either side of every edge within reach of `_geom`
that is not in `_before` (created by the noding) or whose geometry differs from
its snapshot (modified by it: split, or bent by a vertex the noding inserted).
Faces are marked for the dirty layers of `_map_layer`, as
`mark_surrounding_faces` does. The universal face is never marked: it has no
identity or geometry to refresh, and a face that merges into it is handled where
its barrier is removed. Returns the number of dirty_face rows added. */
CREATE OR REPLACE FUNCTION {topo_schema}.mark_noded_faces(
  _geom geometry,
  _tolerance numeric,
  _before {topo_schema}.edge_data[],
  _map_layer integer
)
RETURNS integer AS $$
DECLARE
  _n integer;
BEGIN
  WITH changed AS (
    SELECT e.edge_id, e.left_face, e.right_face
    FROM {topo_schema}.edge_data e
    LEFT JOIN unnest(_before) b
      ON b.edge_id = e.edge_id
    -- Snapping moves a vertex by at most the tolerance, so an edge the noding
    -- touched lies within twice of it from the input geometry.
    WHERE ST_DWithin(e.geom, _geom, 2 * _tolerance)
      AND (b.edge_id IS NULL OR NOT (b.geom = e.geom))
  ), faces AS (
    SELECT left_face AS face_id FROM changed
    UNION
    SELECT right_face FROM changed
  ), inserted AS (
    INSERT INTO {topo_schema}.dirty_face (id, map_layer)
    SELECT f.face_id, dl.id
    FROM faces f
    CROSS JOIN {topo_schema}.dirty_layers_for(_map_layer) dl(id)
    WHERE f.face_id <> 0
      AND dl.id IS NOT NULL
    ON CONFLICT DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO _n FROM inserted;
  RETURN _n;
END;
$$ LANGUAGE plpgsql;

/** Node `geom` into the topogeometry of the row `line`, marking the faces it
changes dirty. `replace_existing` empties an existing topogeometry first;
`complete` also records `geometry_hash` and clears `topology_error`. Raises on
a noding failure; the callers below turn that into a returned error text. */
CREATE OR REPLACE FUNCTION {topo_schema}.__node_boundary(
  line {boundary_table},
  _geom geometry,
  tolerance numeric,
  replace_existing boolean,
  complete boolean
)
RETURNS void AS $$
DECLARE
  _tol numeric := coalesce(tolerance, {topo_schema}.__topo_precision());
  _layer integer := {topo_schema}.boundary_layer_id();
  _before {topo_schema}.edge_data[];
BEGIN
  SELECT coalesce(array_agg(e), ARRAY[]::{topo_schema}.edge_data[])
  INTO _before
  FROM {topo_schema}.edge_data e
  WHERE ST_DWithin(e.geom, _geom, 2 * _tol);

  UPDATE {boundary_table} l
  SET
    topo = CASE
      WHEN l.topo IS NULL THEN
        topology.toTopoGeom(_geom, {topo_name_literal}, _layer, _tol)
      WHEN replace_existing THEN
        topology.toTopoGeom(_geom, topology.clearTopoGeom(l.topo), _tol)
      ELSE
        topology.toTopoGeom(_geom, l.topo, _tol)
    END,
    geometry_hash = CASE
      WHEN complete THEN {topo_schema}.hash_geometry(l.geometry)
      ELSE l.geometry_hash
    END,
    topology_error = CASE
      WHEN complete THEN NULL
      ELSE l.topology_error
    END
  WHERE l.id = line.id;

  PERFORM {topo_schema}.mark_noded_faces(_geom, _tol, _before, line.map_layer);
END;
$$ LANGUAGE plpgsql;

/** Whole-row form: node the row's geometry, recording the outcome on the row. */
CREATE OR REPLACE FUNCTION {topo_schema}.update_boundary_topo(
  line {boundary_table},
  tolerance numeric DEFAULT NULL
)
RETURNS text AS
$$
BEGIN
  IF ({topo_schema}.hash_geometry(line.geometry) = line.geometry_hash) THEN
    -- We already have a valid topogeometry representation
    RETURN null;
  END IF;
  BEGIN
    PERFORM {topo_schema}.__node_boundary(line, line.geometry, tolerance, true, true);
    RETURN null;
  EXCEPTION WHEN others THEN
    UPDATE {boundary_table} l
    SET
      topology_error = SQLERRM
    WHERE l.id = line.id;
    RETURN SQLERRM::text;
  END;
END;
$$ LANGUAGE plpgsql;

/** Piece form: node one piece of the row's geometry into its topogeometry. */
CREATE OR REPLACE FUNCTION {topo_schema}.update_boundary_topo(
  line {boundary_table},
  piece geometry,
  tolerance numeric DEFAULT NULL
)
RETURNS text AS
$$
BEGIN
  IF (piece IS NULL OR ST_IsEmpty(piece)) THEN
    RETURN null;
  END IF;
  BEGIN
    PERFORM {topo_schema}.__node_boundary(line, piece, tolerance, false, false);
    RETURN null;
  EXCEPTION WHEN others THEN
    RETURN SQLERRM::text;
  END;
END;
$$ LANGUAGE plpgsql;

/** Mark dirty the primitives a boundary topogeometry gains.

The boundary trigger marks faces when a row's topogeometry *id* changes; an
accumulating call keeps the id, so the new primitives are found here, on the
relation rows themselves. Only rows still being noded (`geometry_hash IS NULL`)
are considered: a relation row inserted into a *complete* row is a side effect
of noding some other row -- an edge or face of it split by the new geometry --
and the faces involved are adjacent to that geometry and marked by its own
call. Faces are marked for the row's dirty layers, as `mark_surrounding_faces`
does. `map_face` rows never match: they are in another layer. */
CREATE OR REPLACE FUNCTION {topo_schema}.mark_boundary_relation_faces()
RETURNS trigger AS $$
BEGIN
  WITH owners AS (
    SELECT DISTINCT n.element_type, n.element_id, l.map_layer
    FROM changed_new n
    JOIN {boundary_table} l
      ON (l.topo).id = n.topogeo_id
     AND (l.topo).layer_id = n.layer_id
    WHERE n.layer_id = {topo_schema}.boundary_layer_id()
      AND l.geometry_hash IS NULL
  ), faces AS (
    SELECT o.map_layer, o.element_id AS face_id
    FROM owners o
    WHERE o.element_type = 3
    UNION
    SELECT o.map_layer, e.left_face
    FROM owners o
    JOIN {topo_schema}.edge_data e ON e.edge_id = abs(o.element_id)
    WHERE o.element_type = 2
    UNION
    SELECT o.map_layer, e.right_face
    FROM owners o
    JOIN {topo_schema}.edge_data e ON e.edge_id = abs(o.element_id)
    WHERE o.element_type = 2
  )
  INSERT INTO {topo_schema}.dirty_face (id, map_layer)
  SELECT DISTINCT f.face_id, dl.id
  FROM faces f
  CROSS JOIN LATERAL {topo_schema}.dirty_layers_for(f.map_layer) dl(id)
  WHERE f.face_id <> 0
  ON CONFLICT DO NOTHING;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS mark_boundary_relation_faces ON {topo_schema}.relation;
CREATE TRIGGER mark_boundary_relation_faces
AFTER INSERT ON {topo_schema}.relation
REFERENCING NEW TABLE AS changed_new
FOR EACH STATEMENT
EXECUTE FUNCTION {topo_schema}.mark_boundary_relation_faces();

/* The joins above and in the edge-relation triggers look a boundary row up by
   its topogeometry id; a composite field access needs an expression index. */
CREATE INDEX IF NOT EXISTS {index_prefix}boundary_topogeom_id_idx
  ON {boundary_table} (((topo).id));

/** Boundary rows whose whole-row noding failed, as recorded by `update_contacts`
(`procedures/linework-failures.sql`). A log, not the current state: that is the
row's own `topology_error`. */
CREATE TABLE IF NOT EXISTS {topo_schema}.__boundary_failures (
  id integer PRIMARY KEY REFERENCES {boundary_table} (id) ON DELETE CASCADE,
  error text,
  recorded timestamp with time zone DEFAULT now()
);


-- Trigger to create a non-topogeometry representation for
-- storage on each row (for speed of lookup)
DROP TRIGGER IF EXISTS map_topology_boundary_trigger ON {boundary_table};
CREATE TRIGGER map_topology_boundary_trigger
BEFORE INSERT OR UPDATE OR DELETE ON {boundary_table}
FOR EACH ROW EXECUTE PROCEDURE {topo_schema}.boundary_changed();
