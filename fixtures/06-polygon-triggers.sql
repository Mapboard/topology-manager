CREATE OR REPLACE FUNCTION map_topology.polygon_topology(type_id text)
RETURNS text AS $$
SELECT topology
FROM map_digitizer.linework_type
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
