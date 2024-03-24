/*
When `map_topology.contact` table is updated, changes should propagate
to `map_topology.map_face`
*/

/* Util functions */

CREATE OR REPLACE FUNCTION {topo_schema}.line_topology(type_id text)
RETURNS text AS $$
SELECT topology
FROM {data_schema}.linework_type
WHERE id = type_id;
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION {topo_schema}.hash_geometry(line {data_schema}.linework)
RETURNS uuid AS $$
SELECT md5(ST_AsBinary(line.geometry))::uuid;
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION {topo_schema}.__linework_layer_id()
RETURNS integer AS $$
SELECT layer_id
FROM topology.layer
WHERE schema_name= ${data_schema}
  AND table_name='linework'
  AND feature_column='topo';
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION {topo_schema}.__topo_precision()
RETURNS numeric AS $$
SELECT precision::numeric
  FROM topology.topology
  WHERE name=  :topo_name ;
$$ LANGUAGE SQL IMMUTABLE;

/*
When `map_topology.contact` table is updated, changes should propagate
to `map_topology.map_face`
*/

CREATE OR REPLACE FUNCTION {topo_schema}.mark_surrounding_faces(
  line {data_schema}.linework)
RETURNS void AS $$
DECLARE
  __faces integer[];
  __topology text;
BEGIN
  __topology := {topo_schema}.line_topology(line.type);

  IF (line.topo IS null OR __topology IS null) THEN
    RETURN;
  END IF;

  -- GET ADJACENT FACES
  WITH edges AS (
  SELECT (topology.GetTopoGeomElements(line.topo))[1] edge_id
  ),
  faces AS (
  SELECT
    left_face, right_face
  FROM edges e
  JOIN {topo_schema}.edge_data e1
    ON e.edge_id = e1.edge_id
  ),
  faces1 AS (
  SELECT left_face f FROM faces
  UNION
  SELECT right_face f FROM faces
  )
  SELECT array_agg(f)
  INTO __faces
  FROM faces1;

  INSERT INTO {topo_schema}.__dirty_face (id, topology)
  SELECT
    unnest(__faces),
    __topology
  ON CONFLICT DO NOTHING;

  RAISE NOTICE 'Marking faces %', __faces;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION {topo_schema}.linework_changed()
RETURNS trigger AS $$
DECLARE
  __edges integer[];
  __dest_topology text;
BEGIN

IF (TG_OP = 'DELETE') THEN
  PERFORM {topo_schema}.mark_surrounding_faces(OLD);
  --PERFORM {topo_schema}.join_surrounding_faces(NEW)
  RETURN OLD;

  -- ON DELETE CASCADE should handle the `__edge_relation` table in this case
END IF;

__dest_topology := {topo_schema}.line_topology(NEW.type);

IF (NEW.topo IS null OR __dest_topology IS null ) THEN
  -- Delete stale relations, in case we are changing the topology
  DELETE FROM {topo_schema}.__edge_relation
  WHERE line_id = NEW.id;

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
  {topo_schema}.line_topology(OLD.type) = __dest_topology
) THEN
  /* Discards cases where we aren't changing anything relevant */
  RETURN NEW;
END IF;
/* We are new working with only changed topogeometries */

SELECT array_agg(elem)
INTO __edges
FROM (SELECT (topology.GetTopoGeomElements(NEW.topo))[1] elem) AS a;

/* Delete unreferenced elements from topo tracker */
DELETE FROM {topo_schema}.__edge_relation
WHERE line_id IN (OLD.id)
  AND NOT(edge_id = ANY(__edges));

/* Add new objects into linework tracker */
INSERT INTO {topo_schema}.__edge_relation
  (edge_id, topology, line_id, type)
VALUES (
  unnest(__edges),
  __dest_topology,
  NEW.id,
  NEW.type
)
ON CONFLICT (edge_id, topology) DO UPDATE SET
  line_id = NEW.id,
  type = NEW.type;

/* This is probably where we should update map faces for referential
   integrity

Envisioned series of steps:
1. Find overlapping map faces
2. Join all of the overlapping faces
3. Split faces on this new

*/

/* We can fall back to this if we don't have a handled case for now */
PERFORM {topo_schema}.mark_surrounding_faces(OLD);
PERFORM {topo_schema}.mark_surrounding_faces(NEW);
RETURN NEW;

END;
$$ LANGUAGE plpgsql;

/*
Function to update topogeometry of linework
*/
CREATE OR REPLACE FUNCTION {topo_schema}.update_linework_topo(
  line {data_schema}.linework)
RETURNS text AS
$$
BEGIN
  IF ({topo_schema}.hash_geometry(line) = line.geometry_hash) THEN
    -- We already have a valid topogeometry representation
    RETURN null;
  END IF;
  -- Actually set topogeometry
  BEGIN
    -- Set topogeometry
    UPDATE {data_schema}.linework l
    SET
      topo = topology.toTopoGeom(
        line.geometry,   :topo_name ,
        {topo_schema}.__linework_layer_id(),
        {topo_schema}.__topo_precision()),
      geometry_hash = {topo_schema}.hash_geometry(l),
      topology_error = null
    WHERE l.id = line.id;
    RETURN null;
  EXCEPTION WHEN others THEN
    UPDATE {data_schema}.linework l
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
DROP TRIGGER IF EXISTS map_topology_linework_trigger ON {data_schema}.linework;
CREATE TRIGGER map_topology_linework_trigger
BEFORE INSERT OR UPDATE OR DELETE ON {data_schema}.linework
FOR EACH ROW EXECUTE PROCEDURE {topo_schema}.linework_changed();
