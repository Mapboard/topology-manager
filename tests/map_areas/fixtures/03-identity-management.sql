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
  -- A point guaranteed to lie on the area must be within each candidate map
  -- (a centroid can fall outside a non-convex face, e.g. one with a notch)
  WHERE ST_Intersects(ST_PointOnSurface(geom), ma.geometry)
  ORDER BY priority, map_id DESC
  LIMIT 1;
$$ LANGUAGE sql;


/** The identity of a primitive: the highest-priority map area covering it.

Topogeometry ids are only unique *within a topology layer*, so the relation row
must be matched on both `topogeo_id` and `layer_id` — otherwise a `map_face`
topogeometry with the same id as a map area is mistaken for it. */
CREATE OR REPLACE FUNCTION map_bounds_topology.identity_for_face(face_id integer, map_layer integer)
  RETURNS integer AS $$
SELECT
  map_id
FROM map_bounds_topology.relation r
JOIN map_bounds.map_area f
  -- A topogeometry id is only unique within a layer.
  ON (f.topo).id = r.topogeo_id
 AND (f.topo).layer_id = r.layer_id
 AND f.map_layer = $2
JOIN map_bounds.map_priority mc
  ON mc.map_id = f.id
 AND mc.map_layer = $2
WHERE element_id = $1
  AND element_type = 3
ORDER BY priority, map_id DESC
LIMIT 1;
$$ LANGUAGE SQL STABLE;

/** The set-oriented form of `identity_for_face`, for a whole layer at once.

Must agree with `identity_for_face` exactly -- same candidate set, same ordering --
because the dissolve uses whichever is available and the two must not disagree
about which map owns a face. `DISTINCT ON` is the bulk equivalent of that
function's `LIMIT 1`. Declaring it (with `bulk_identity=True` on the strategy) is
what makes the suites exercise the cached dissolve path that hosts with a bulk
strategy -- Macrostrat among them -- actually run. */
CREATE OR REPLACE FUNCTION map_bounds_topology.resolve_layer_identity(_map_layer integer)
  RETURNS TABLE (face_id integer, identity text) AS $$
SELECT DISTINCT ON (r.element_id)
  r.element_id,
  mc.map_id::text
FROM map_bounds_topology.relation r
JOIN map_bounds.map_area f
  ON (f.topo).id = r.topogeo_id
 AND (f.topo).layer_id = r.layer_id
 AND f.map_layer = _map_layer
JOIN map_bounds.map_priority mc
  ON mc.map_id = f.id
 AND mc.map_layer = _map_layer
WHERE r.element_type = 3
ORDER BY r.element_id, mc.priority, mc.map_id DESC;
$$ LANGUAGE SQL STABLE;

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
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION {topo_schema}.map_face_is_identified(map_face {topo_schema}.map_face)
  RETURNS boolean AS $$
BEGIN
  RETURN map_face.map_id IS NOT NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
