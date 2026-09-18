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
  PERFORM {topo_schema}.mark_surrounding_faces(OLD);
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

/*
Function to update topogeometry of linework
*/
CREATE OR REPLACE FUNCTION {topo_schema}.update_boundary_topo(line {boundary_table})
RETURNS text AS
$$
BEGIN
  IF ({topo_schema}.hash_geometry(line.geometry) = line.geometry_hash) THEN
    -- We already have a valid topogeometry representation
    RETURN null;
  END IF;
  -- Actually set topogeometry
  BEGIN
    -- Set topogeometry
    UPDATE {boundary_table} l
    SET
      topo = topology.toTopoGeom(
        line.geometry,
        {topo_name_literal},
        {topo_schema}.boundary_layer_id(),
        {topo_schema}.__topo_precision()
      ),
      geometry_hash = {topo_schema}.hash_geometry(l.geometry),
      topology_error = null
    WHERE l.id = line.id;
    RETURN null;
  EXCEPTION WHEN others THEN
    UPDATE {boundary_table} l
    SET
      topology_error = SQLERRM
    WHERE l.id = line.id;
    RETURN SQLERRM::text;
  END;
  RETURN null;
END;
$$ LANGUAGE plpgsql;


-- Trigger to create a non-topogeometry representation for
-- storage on each row (for speed of lookup)
DROP TRIGGER IF EXISTS map_topology_boundary_trigger ON {boundary_table};
CREATE TRIGGER map_topology_boundary_trigger
BEFORE INSERT OR UPDATE OR DELETE ON {boundary_table}
FOR EACH ROW EXECUTE PROCEDURE {topo_schema}.boundary_changed();
