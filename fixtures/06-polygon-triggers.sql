CREATE OR REPLACE FUNCTION map_topology.polygon_topology(type_id text)
RETURNS text AS $$
SELECT topology
FROM map_digitizer.polygon_type
WHERE id = type_id
$$ LANGUAGE SQL;

/*
Trigger to update polygon faces when added
*/
CREATE OR REPLACE FUNCTION map_topology.polygon_update_trigger()
/*
Procedure to keep contact table in sync with linework table
*/
RETURNS trigger AS $$
DECLARE
  affected_area geometry;
  __topology text;
BEGIN

IF (TG_OP = 'DELETE') THEN
  affected_area := OLD.geometry;
  __topology := map_topology.polygon_topology(OLD.type);
ELSIF (TG_OP = 'INSERT') THEN
  affected_area := NEW.geometry;
  __topology := map_topology.polygon_topology(NEW.type);
ELSIF (NOT ST_Equals(OLD.geometry, NEW.geometry)) THEN
  affected_area := ST_Union(OLD.geometry, NEW.geometry);
  __topology := map_topology.polygon_topology(NEW.type);
END IF;

-- TODO: there might be an issue with topology here...
UPDATE map_topology.map_face mf
SET unit_id = map_topology.unitForArea(geometry, mf.topology)
WHERE ST_Intersects(affected_area, geometry);
RETURN null;
END;
$$ LANGUAGE plpgsql;

/* Create the actual trigger */
DROP TRIGGER IF EXISTS map_digitizer_polygon_update_trigger
  ON map_digitizer.polygon;
CREATE TRIGGER map_digitizer_polygon_update_trigger
AFTER INSERT OR UPDATE OR DELETE ON map_digitizer.polygon
FOR EACH ROW
EXECUTE PROCEDURE map_topology.polygon_update_trigger();

CREATE OR REPLACE FUNCTION
map_topology.register_face_units(__map_face map_topology.map_face)
RETURNS void AS $$
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION map_topology.map_face_topo_update_trigger()
/*
Procedure to keep contact table in sync with linework table
*/
RETURNS trigger AS $$
DECLARE
  __map_face map_topology.map_face;
  __topology text;
BEGIN

IF (TG_OP = 'DELETE') THEN
  __map_face := OLD;
ELSE
  __map_face := NEW;
END IF;

--IF (__map_face.topo IS NULL) THEN
RETURN null;
--END IF;

-- TODO: there might be an issue with topology here...
UPDATE map_topology.map_face mf
SET unit_id = map_topology.unitForArea(geometry, mf.topology)
WHERE ST_Intersects(affected_area, geometry);
RETURN null;
END;
$$ LANGUAGE plpgsql;

/* Create the actual trigger */
DROP TRIGGER IF EXISTS map_digitizer_map_face_topo_update_trigger
  ON map_topology.map_face;
CREATE TRIGGER map_topology_map_face_topo_update_trigger
AFTER INSERT
OR UPDATE OF topo, unit_id
OR DELETE
ON map_topology.map_face
FOR EACH ROW
EXECUTE PROCEDURE map_topology.map_face_topo_update_trigger();

