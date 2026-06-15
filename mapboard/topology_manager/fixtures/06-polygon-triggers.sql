/** Get the topology for a polygon */
CREATE OR REPLACE FUNCTION {topo_schema}.get_topological_map_layer(_poly {data_schema}.polygon)
RETURNS integer AS $$
SELECT ml.id
FROM {data_schema}.map_layer ml,
     {data_schema}.polygon_type pt
  WHERE ml.id = $1.map_layer
    AND ml.composited_from IS NULL
    AND pt.id = $1.type
    AND coalesce(pt.topological, true)
    AND ml.topological;
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
  __topology integer;
BEGIN

affected_area := OLD.geometry;
IF (TG_OP = 'DELETE') THEN
  __topology := {topo_schema}.get_topological_map_layer(OLD);
ELSE
  __topology := {topo_schema}.get_topological_map_layer(NEW);
END IF;

-- Handle cases where we are removing the polygon from a topological map layer
IF __topology IS NULL AND (TG_OP = 'UPDATE') THEN
  __topology := {topo_schema}.get_topological_map_layer(OLD);
END IF;

-- This polygon is not part of a topological map layer
IF __topology IS NULL THEN
  RETURN null;
END IF;

IF (TG_OP = 'INSERT') THEN
  affected_area := NEW.geometry;
ELSIF (NOT ST_Equals(OLD.geometry, NEW.geometry)) THEN
  affected_area := ST_Union(OLD.geometry, NEW.geometry);
END IF;

/** Now we have the affected area, we can update map faces predictively based on it...  */

/** TODO: there might be an issue here because we
seem to be filtering faces to update only based
on the affected area, not also the map_layer being
updated.

Using source_layer also handles composite layers.
*/
UPDATE {topo_schema}.map_face mf
SET unit_id = {topo_schema}.identity_for_area(geometry, mf.map_layer)
WHERE ST_Intersects(affected_area, geometry)
  AND (mf.map_layer = __topology OR mf.source_layer = __topology);

RETURN null;
END;
$$ LANGUAGE plpgsql;

/* Create the actual trigger */
DROP TRIGGER IF EXISTS polygon_update_trigger
  ON {data_schema}.polygon;
CREATE TRIGGER polygon_update_trigger
AFTER INSERT OR UPDATE OR DELETE ON {data_schema}.polygon
FOR EACH ROW
EXECUTE PROCEDURE {topo_schema}.polygon_update_trigger();

CREATE OR REPLACE FUNCTION
{topo_schema}.register_face_identity(__map_face_id integer)
RETURNS void AS $$
WITH t AS (
SELECT
  id map_face,
  unit_id,
  map_layer,
  (topo).*
FROM {topo_schema}.map_face
WHERE id = __map_face_id
)
INSERT INTO {topo_schema}.face_type AS ft
  (face_id, map_face, unit_id, map_layer)
SELECT
  face_id,
  map_face,
  unit_id,
  map_layer
FROM t
JOIN {topo_schema}.relation r
  ON r.layer_id = t.layer_id
  AND r.element_type = t.type
  AND r.topogeo_id = t.id
JOIN {topo_schema}.face f
  ON r.element_id = f.face_id
ON CONFLICT (face_id, map_layer)
DO UPDATE SET
  map_face = EXCLUDED.map_face,
  unit_id = EXCLUDED.unit_id
WHERE ft.face_id = EXCLUDED.face_id
  AND ft.map_layer = EXCLUDED.map_layer;
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION {topo_schema}.map_face_topo_update_trigger()
/* Procedure to keep contact table in sync with linework table */
RETURNS trigger AS $$
BEGIN
IF (NEW.topo IS NULL) THEN
  RETURN null;
END IF;
PERFORM {topo_schema}.register_face_identity(NEW.id);
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

