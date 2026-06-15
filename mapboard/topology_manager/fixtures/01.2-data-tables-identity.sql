/** Map face identifiers:
  links map_face to polygon_type identifier for geologic maps
  This could be changed if we wanted to use a different type of identification (e.g., for columns etc.)
*/
ALTER TABLE {topo_schema}.map_face ADD COLUMN unit_id text REFERENCES {data_schema}.polygon_type (id) ON DELETE CASCADE;
ALTER TABLE {topo_schema}.face_identity ADD COLUMN unit_id text REFERENCES {data_schema}.polygon_type (id) ON DELETE CASCADE;

/*
Get the map face that defines a polygon for a specific topology
*/
CREATE OR REPLACE FUNCTION {topo_schema}.identity_for_area(
  face geometry,
  _map_layer integer
  )
  RETURNS text AS $$
DECLARE result text;
BEGIN
-- Get polygons in requisite topology
WITH polygon AS (
SELECT
  p.id,
  p.type,
  p.geometry
FROM {data_schema}.polygon p
JOIN {data_schema}.map_layer ml
  ON p.map_layer = ml.id
JOIN {data_schema}.map_layer_polygon_type mlpt
  ON mlpt.type = p.type
 AND mlpt.map_layer = ml.id
JOIN {data_schema}.polygon_type pt
  ON pt.id = mlpt.type
WHERE ml.id = _map_layer
  AND coalesce(pt.topological, ml.topological)
  AND ST_Contains(face, p.geometry)
)
-- Assign face that has the greatest area of polygons
-- assigned to it within the feature
SELECT
  type
INTO result
FROM polygon
GROUP BY type
ORDER BY ST_Area(ST_Union(geometry)) DESC
LIMIT 1;

RETURN result;
END
$$ LANGUAGE plpgsql;


/** Unused function
CREATE OR REPLACE FUNCTION {topo_schema}.unitForFace(face_id integer, map_layer integer)
RETURNS text AS $$
SELECT
  unit_id
FROM {topo_schema}.relation r
JOIN {topo_schema}.map_face f
  ON (f.topo).id = r.topogeo_id
WHERE element_id = $1
  AND element_type = 3
  AND r.layer_id = {topo_schema}.__map_face_layer_id()
  AND f.map_layer = $2;
$$ LANGUAGE SQL IMMUTABLE;
 */

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
INSERT INTO {topo_schema}.face_identity AS ft
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

