/*
When `map_topology.contact` table is updated, changes should propagate
to `map_topology.map_face`
*/

/* Util functions */

CREATE OR REPLACE FUNCTION map_topology.line_topology(type_id text)
RETURNS text AS $$
SELECT topology
FROM map_digitizer.linework_type
WHERE id = type_id;
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION map_topology.hash_geometry(line map_digitizer.linework)
RETURNS uuid AS $$
SELECT md5(ST_AsBinary(line.geometry))::uuid;
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION map_topology.__linework_layer_id()
RETURNS integer AS $$
SELECT layer_id
FROM topology.layer
WHERE schema_name='map_digitizer'
  AND table_name='linework'
  AND feature_column='topo';
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION map_topology.__topo_precision()
RETURNS numeric AS $$
SELECT precision::numeric
  FROM topology.topology
  WHERE name='map_topology';
$$ LANGUAGE SQL IMMUTABLE;

/*
When `map_topology.contact` table is updated, changes should propagate
to `map_topology.map_face`
*/

CREATE OR REPLACE FUNCTION map_topology.mark_surrounding_faces(
  line map_digitizer.linework)
RETURNS void AS $$
BEGIN
  IF (line.topo IS null) THEN
    RETURN;
  END IF;

  INSERT INTO map_topology.__dirty_face (id, topology)
  SELECT
    face_id,
    map_topology.line_topology(line.type)
  FROM map_topology.edge_face ef
  WHERE ef.edge_id IN (SELECT
    (topology.GetTopoGeomElements(line.topo))[1])
  ON CONFLICT DO NOTHING;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION map_topology.linework_changed()
RETURNS trigger AS $$
DECLARE
  __edges integer[];
BEGIN

IF (TG_OP = 'DELETE') THEN
  PERFORM map_topology.mark_surrounding_faces(OLD);
  --PERFORM map_topology.join_surrounding_faces(NEW)
  RETURN OLD;

  -- ON DELETE CASCADE should handle the `__edge_relation` table in this case
END IF;

__edges := array_agg((topology.GetTopoGeomElements(NEW.topo))[1]);

DELETE FROM map_topology.__edge_relation
WHERE line_id IN (OLD.id)
  AND NOT(edge_id = ANY(__edges));

-- Maybe we could make this faster IDK
INSERT INTO map_topology.__edge_relation
  (edge_id, topology, line_id, type)
VALUES (
  unnest(edges),
  NEW.topology,
  NEW.id,
  NEW.type
)
ON CONFLICT DO UPDATE SET
  line_id = NEW.id,
  type = NEW.type;

IF (TG_OP = 'INSERT') THEN
  /*
  We will probably not have topo set on inserts most of the time, but we might
  on programmatic or eagerly-managed insertions, so it's worth a try.

  NEW method: get map faces that cover this
  PERFORM map_topology.join_surrounding_faces(NEW)
  */
  PERFORM map_topology.mark_surrounding_faces(NEW);
  RETURN NEW;
END IF;

/* More complex logic for updates */

/* Wipe hash if we know we have geometry changes.
   We may put in a dirty marker here instead of hashing if it seems better */
IF (NOT OLD.geometry = NEW.geometry) THEN
  NEW.geometry_hash := null;
  PERFORM map_topology.mark_surrounding_faces(OLD);
  RETURN NEW;
END IF;

IF ((OLD.topo).id = (NEW.topo).id AND
    map_topology.line_topology(OLD.type) = map_topology.line_topology(NEW.type)) THEN
  /* Discards cases where we aren't changing anything relevant */
  RETURN NEW;
END IF;

/* This is probably where we should update map faces for referential
   integrity

Envisioned series of steps:
1. Find overlapping map faces
2. Join all of the overlapping faces
3. Split faces on this new

*/

/* We can fall back to this if we don't have a handled case for now */
PERFORM map_topology.mark_surrounding_faces(OLD);
PERFORM map_topology.mark_surrounding_faces(NEW);
RETURN NEW;

END;
$$ LANGUAGE plpgsql;

/*
Function to update topogeometry of linework
*/
CREATE OR REPLACE FUNCTION map_topology.update_linework_topo(
  line map_digitizer.linework)
RETURNS text AS
$$
BEGIN
  IF (map_topology.hash_geometry(line) = line.geometry_hash) THEN
    -- We already have a valid topogeometry representation
    RETURN null;
  END IF;
  -- Actually set topogeometry
  BEGIN
    -- Set topogeometry
    UPDATE map_digitizer.linework l
    SET
      topo = topology.toTopoGeom(
        line.geometry, 'map_topology',
        map_topology.__linework_layer_id(),
        map_topology.__topo_precision()),
      geometry_hash = map_topology.hash_geometry(l),
      topology_error = null
    WHERE l.id = line.id;
    RETURN null;
  EXCEPTION WHEN others THEN
    UPDATE map_digitizer.linework l
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
DROP TRIGGER IF EXISTS map_topology_linework_trigger ON map_digitizer.linework;
CREATE TRIGGER map_topology_linework_trigger
BEFORE INSERT OR UPDATE OR DELETE ON map_digitizer.linework
FOR EACH ROW EXECUTE PROCEDURE map_topology.linework_changed();

