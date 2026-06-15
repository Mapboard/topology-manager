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
