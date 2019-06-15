/*
Post a notification each time the output topology changes
*/
CREATE OR REPLACE FUNCTION map_topology.linework_topology_notify()
RETURNS trigger AS $$
DECLARE
payload text;
BEGIN
  payload := NEW.edge_id::text;
  PERFORM pg_notify('topology', (payload));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS map_topology_topo_line_notify_trigger
ON map_topology.__edge_relation;

CREATE TRIGGER map_topology_topo_line_notify_trigger
AFTER INSERT
    OR UPDATE
    OR DELETE
    ON map_topology.__edge_relation
FOR EACH STATEMENT
EXECUTE PROCEDURE map_topology.linework_topology_notify();


CREATE OR REPLACE FUNCTION map_topology.polygon_topology_notify()
RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify('topology', NEW.id::text);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS map_topology_topo_map_face_trigger
ON map_topology.map_face;

CREATE TRIGGER map_topology_topo_map_face_trigger
AFTER INSERT
    OR UPDATE
    OR DELETE
    ON map_topology.map_face
FOR EACH STATEMENT
EXECUTE PROCEDURE map_topology.polygon_topology_notify();

