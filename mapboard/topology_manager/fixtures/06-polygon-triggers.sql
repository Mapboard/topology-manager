CREATE OR REPLACE FUNCTION {topo_schema}.polygon_topology(type_id text)
RETURNS text AS $$
SELECT topology
FROM {data_schema}.polygon_type
WHERE id = type_id
$$ LANGUAGE SQL;

/*
Trigger to update polygon faces when added
*/
CREATE OR REPLACE FUNCTION {topo_schema}.polygon_update_trigger()
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
  __topology := {topo_schema}.polygon_topology(OLD.type);
ELSIF (TG_OP = 'INSERT') THEN
  affected_area := NEW.geometry;
  __topology := {topo_schema}.polygon_topology(NEW.type);
ELSIF (NOT ST_Equals(OLD.geometry, NEW.geometry)) THEN
  affected_area := ST_Union(OLD.geometry, NEW.geometry);
  __topology := {topo_schema}.polygon_topology(NEW.type);
END IF;

-- TODO: there might be an issue with topology here...
UPDATE {topo_schema}.map_face mf
SET unit_id = {topo_schema}.unitForArea(geometry, mf.topology)
WHERE ST_Intersects(affected_area, geometry);
RETURN null;
END;
$$ LANGUAGE plpgsql;

/* Create the actual trigger */
DROP TRIGGER IF EXISTS topo_polygon_update_trigger
  ON {data_schema}.polygon;
CREATE TRIGGER topo_polygon_update_trigger
AFTER INSERT OR UPDATE OR DELETE ON {data_schema}.polygon
FOR EACH ROW
EXECUTE PROCEDURE {topo_schema}.polygon_update_trigger();

CREATE OR REPLACE FUNCTION
{topo_schema}.register_face_unit(__map_face_id integer)
RETURNS void AS $$
WITH t AS (
SELECT
  id map_face,
  unit_id,
  topology,
  (topo).*
FROM {topo_schema}.map_face
WHERE id = __map_face_id
)
INSERT INTO {topo_schema}.face_type AS ft (face_id, map_face, unit_id, topology)
SELECT
  face_id,
  map_face,
  unit_id,
  topology
FROM t
JOIN {topo_schema}.relation r
  ON r.layer_id = t.layer_id
  AND r.element_type = t.type
  AND r.topogeo_id = t.id
JOIN {topo_schema}.face f
  ON r.element_id = f.face_id
ON CONFLICT (face_id, topology) DO
UPDATE SET
  map_face = EXCLUDED.map_face,
  unit_id = EXCLUDED.unit_id
WHERE ft.face_id = EXCLUDED.face_id
  AND ft.topology = EXCLUDED.topology;
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION {topo_schema}.map_face_topo_update_trigger()
/* Procedure to keep contact table in sync with linework table */
RETURNS trigger AS $$
BEGIN
IF (NEW.topo IS NULL) THEN
  RETURN null;
END IF;
PERFORM {topo_schema}.register_face_unit(NEW.id);
RETURN null;
END;
$$ LANGUAGE plpgsql;

/* Create the actual trigger */
DROP TRIGGER IF EXISTS map_face_topo_update_trigger
  ON {topo_schema}.map_face;
CREATE TRIGGER map_face_topo_update_trigger
AFTER INSERT OR UPDATE OF topo, unit_id
ON {topo_schema}.map_face
FOR EACH ROW
EXECUTE PROCEDURE {topo_schema}.map_face_topo_update_trigger();

