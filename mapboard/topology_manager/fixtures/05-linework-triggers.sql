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

/** The faces on either side of the given edges, and of every edge bounding the
given faces: what a change to those primitives can affect. Lineal boundaries
pass their edges (the faces they separate); areal boundaries pass their faces
(themselves, and their neighbours across their bounding edges). */
CREATE OR REPLACE FUNCTION {topo_schema}.__adjacent_faces(
  _edges integer[],
  _faces integer[]
) RETURNS integer[] AS $$
WITH edge_faces AS (
  SELECT e.left_face, e.right_face
  FROM {topo_schema}.edge_data e
  WHERE e.edge_id = ANY(_edges)
     OR e.left_face = ANY(_faces)
     OR e.right_face = ANY(_faces)
),
faces AS (
  SELECT left_face f FROM edge_faces
  UNION
  SELECT right_face f FROM edge_faces
)
SELECT array_agg(f) FROM faces;
$$ LANGUAGE SQL STABLE;

/** Adjacent faces (lines) or overlapping faces (polygons) for a given topogeometry */
CREATE OR REPLACE FUNCTION {topo_schema}.relevant_faces(topo topogeometry) RETURNS integer[] AS $$
WITH topo_primitives AS (
  SELECT topology.GetTopoGeomElements(topo) primitives
)
SELECT {topo_schema}.__adjacent_faces(
  (SELECT array_agg(abs(primitives[1])) FROM topo_primitives WHERE primitives[2] = 2),
  (SELECT array_agg(primitives[1]) FROM topo_primitives WHERE primitives[2] = 3)
);
$$
LANGUAGE SQL STABLE;

/** Queue faces for the face update, in every layer a change in `_map_layer`
invalidates. */
CREATE OR REPLACE FUNCTION {topo_schema}.mark_faces(
  _faces integer[],
  _map_layer integer
) RETURNS void AS $$
  WITH ml AS (
    SELECT {topo_schema}.dirty_layers_for(_map_layer) id
  )
  INSERT INTO {topo_schema}.dirty_face (id, map_layer)
  SELECT
    unnest(_faces),
    ml.id
  FROM ml
  WHERE ml.id IS NOT NULL
  ON CONFLICT DO NOTHING;
$$ LANGUAGE SQL;

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

  PERFORM {topo_schema}.mark_faces(__faces, line.map_layer);

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

Two entry points, both returning the error text of a failed noding (NULL on
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
  geometry: the first piece creates the row's topogeometry, later pieces
  accumulate into it under the same id, so the row's `topo` references the union
  of what it did before and the piece's primitives. On failure the row is
  untouched and nothing is recorded -- a piece is not a row. The caller sets
  `geometry_hash` when it considers the row complete; the library does not know
  about pieces once the call returns.

The noding itself is what PostGIS's `toTopoGeom` does -- `TopoGeo_AddPolygon` /
`TopoGeo_AddLinestring` per component, one `relation` row per primitive returned
-- done here so that the primitives a call added are known to it: the faces they
touch (`__adjacent_faces`, as the boundary trigger uses for a whole
topogeometry) are marked dirty in the same call. A noding call is an UPDATE of
the row's `topo` and fires `boundary_changed` too, but an accumulating call
keeps the topogeometry id, which that trigger takes as "nothing changed".

Realized geometry (`map_face.geometry`) is kept to the topology's precision, not
bitwise: noding may insert a vertex into an existing edge a float-noise distance
off its line where a new line ends on it, and the face across such a T-junction
is not re-marked for that.
*/

-- Earlier revisions had a one-argument form; with a defaulted tolerance the
-- two would be ambiguous.
DROP FUNCTION IF EXISTS {topo_schema}.update_boundary_topo({boundary_table});

/** Node `_geom` into the topogeometry of the row `line`, marking the faces it
touches dirty. `replace_existing` empties an existing topogeometry first;
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
  _tol float8 := coalesce(tolerance, {topo_schema}.__topo_precision());
  _layer integer := {topo_schema}.boundary_layer_id();
  _layer_type integer;
  _dims integer := ST_Dimension(_geom);
  _tg topology.topogeometry;
  _component geometry;
  _primitive integer;
  _edges integer[] := ARRAY[]::integer[];
  _faces integer[] := ARRAY[]::integer[];
BEGIN
  SELECT feature_type INTO _layer_type
  FROM topology.layer
  WHERE layer_id = _layer
    AND topology_id = (SELECT id FROM topology.topology WHERE name = {topo_name_literal});

  -- 1: puntal, 2: lineal, 3: areal, 4: collection
  IF _layer_type <> 4 AND _dims + 1 <> _layer_type THEN
    RAISE EXCEPTION 'The boundary layer is % and cannot hold a % piece',
      CASE _layer_type WHEN 1 THEN 'puntal' WHEN 2 THEN 'lineal' ELSE 'areal' END,
      CASE _dims WHEN 0 THEN 'puntal' WHEN 1 THEN 'lineal' ELSE 'areal' END;
  END IF;

  -- Not `SELECT topo INTO _tg`: with a composite target PL/pgSQL assigns the
  -- selected columns to the composite's fields, one by one.
  _tg := (SELECT topo FROM {boundary_table} WHERE id = line.id);
  IF _tg IS NOT NULL AND replace_existing THEN
    _tg := topology.clearTopoGeom(_tg);
  END IF;
  IF _tg IS NULL THEN
    _tg := topology.CreateTopoGeom({topo_name_literal}, _layer_type, _layer);
  END IF;

  FOR _component IN
    SELECT geom FROM ST_Dump(_geom) WHERE NOT ST_IsEmpty(geom)
  LOOP
    FOR _primitive IN
      SELECT p FROM (
        SELECT topology.TopoGeo_AddPoint({topo_name_literal}, _component, _tol)
          WHERE _dims = 0
        UNION ALL
        SELECT topology.TopoGeo_AddLinestring({topo_name_literal}, _component, _tol)
          WHERE _dims = 1
        UNION ALL
        SELECT topology.TopoGeo_AddPolygon({topo_name_literal}, _component, _tol)
          WHERE _dims = 2
      ) AS f(p)
    LOOP
      INSERT INTO {topo_schema}.relation (topogeo_id, layer_id, element_type, element_id)
      VALUES ((_tg).id, _layer, _dims + 1, _primitive)
      ON CONFLICT DO NOTHING;
      IF _dims = 1 THEN
        _edges := _edges || abs(_primitive);
      ELSIF _dims = 2 THEN
        _faces := _faces || _primitive;
      END IF;
    END LOOP;
  END LOOP;

  UPDATE {boundary_table} l
  SET
    topo = _tg,
    geometry_hash = CASE
      WHEN complete THEN {topo_schema}.hash_geometry(l.geometry)
      ELSE l.geometry_hash
    END,
    topology_error = CASE
      WHEN complete THEN NULL
      ELSE l.topology_error
    END
  WHERE l.id = line.id;

  PERFORM {topo_schema}.mark_faces(
    {topo_schema}.__adjacent_faces(_edges, _faces),
    line.map_layer
  );
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

/* The edge-relation triggers look a boundary row up by its topogeometry id on
   every relation row they see; a composite field access needs an expression
   index. */
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
