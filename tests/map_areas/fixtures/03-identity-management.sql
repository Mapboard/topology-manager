/* Identity strategy: "direct" (host-registered)

Each face carries its own identity: the covering map_area, disambiguated by
map_priority. The `map_id` identity column is added by `create_tables` from the
strategy's declared column metadata; this file installs only the resolution
functions.
*/

/*
Get the map face that defines a polygon for a specific topology
*/
CREATE OR REPLACE FUNCTION map_bounds_topology.identity_for_area(
  geom geometry,
  _map_layer integer
)
  RETURNS integer AS $$
  -- Get maps that overlap the area
  SELECT mc.map_id
  FROM map_bounds.map_area ma
  JOIN map_bounds.map_priority mc
    ON mc.map_id = ma.id
   AND mc.map_layer = _map_layer
  -- The center of the area must be within each candidate map
  WHERE ST_Intersects(ST_Centroid(geom), ma.geometry)
  ORDER BY priority, map_id DESC
  LIMIT 1;
$$ LANGUAGE sql;


/** TODO: this has to be recreated here because the types are wrong **/
CREATE OR REPLACE FUNCTION map_bounds_topology.identity_for_face(face_id integer, map_layer integer)
  RETURNS integer AS $$
SELECT
  map_id
FROM map_bounds_topology.relation r
JOIN map_bounds.map_area f
  ON (f.topo).id = r.topogeo_id
 AND f.map_layer = $2
JOIN map_bounds.map_priority mc
  ON mc.map_id = f.id
 AND mc.map_layer = $2
WHERE element_id = $1
  AND element_type = 3
ORDER BY priority, map_id DESC
LIMIT 1;
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION map_bounds_topology.faces_are_joinable(f1 integer, f2 integer, map_layer integer)
  RETURNS boolean AS $$
DECLARE
  id1 integer;
  id2 integer;
BEGIN
  id1 := map_bounds_topology.identity_for_face(f1, map_layer);
  id2 := map_bounds_topology.identity_for_face(f2, map_layer);
  RETURN id1 IS NOT DISTINCT FROM id2;
END
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION {topo_schema}.map_face_is_identified(map_face {topo_schema}.map_face)
  RETURNS boolean AS $$
BEGIN
  RETURN map_face.map_id IS NOT NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
