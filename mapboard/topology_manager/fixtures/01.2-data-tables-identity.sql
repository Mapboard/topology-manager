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

/** We can compute the face's identity by looking at the unit id of the relation */
CREATE OR REPLACE FUNCTION {topo_schema}.identity_for_face(face_id integer, map_layer integer)
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


/** Helper function that allows us to check whether edges are joinable within a layer */
CREATE OR REPLACE FUNCTION {topo_schema}.faces_are_joinable(
  f1 integer, f2 integer, _map_layer integer
) RETURNS boolean
AS $$
BEGIN
  RETURN true;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION {topo_schema}.map_face_is_identified(map_face {topo_schema}.map_face)
  RETURNS boolean AS $$
BEGIN
  RETURN map_face.unit_id IS NOT NULL AND map_face.unit_id != 'none';
END;
$$ LANGUAGE plpgsql IMMUTABLE;
