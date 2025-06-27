WITH delete_changed_lines AS (
  DELETE FROM {data_schema}.linework l
  USING {data_schema}.linework l2
  WHERE l.map_layer = :composite_layer
    AND l2.map_layer = l.source_layer
    AND l2.id = l.source_id
    AND (
      -- Compare topological properties
      l.geometry_hash != l2.geometry_hash
      OR
      -- Compare geometries
      NOT ST_Equals(l.geometry, l2.geometry)
    )
),
overlay_faces AS (
  SELECT ST_Union(f.geometry) AS geometry
  FROM {topo_schema}.map_face f
  WHERE f.map_layer = ANY(:overlay_layers)
    AND f.unit_id IS NOT NULL
    AND f.unit_id != 'none'
),
lines AS (
  SELECT l.*,
      ST_Intersects(l.geometry, f.geometry) AS intersects
  FROM {data_schema}.linework l,
       overlay_faces f
  WHERE l.map_layer IN (SELECT * FROM {topo_schema}.parent_map_layers(:map_layer))
    AND l.id NOT IN (
      SELECT source_id
      FROM {data_schema}.linework
      WHERE map_layer = :composite_layer
  )
),
all_lines AS (
  SELECT l.id     source_id,
         l.type type,
         l.geometry_hash geometry_hash,
  CASE
   WHEN l.intersects THEN
     ST_Difference(l.geometry, f.geometry)
   ELSE l.geometry
   END AS geometry,
  false AS covered
  FROM lines l, overlay_faces f
  UNION ALL
  SELECT l.id,
  l.type,
  l.geometry_hash,
  ST_Intersection(l.geometry, f.geometry) geometry,
  true AS                                  covered
  FROM lines l,
       overlay_faces f
  WHERE l.intersects
)
INSERT INTO {data_schema}.linework (
  map_layer,
  source_id,
  source_layer,
  type,
  geometry,
  geometry_hash,
  covered
)
SELECT
  :composite_layer AS map_layer,
  source_id,
  :map_layer source_layer,
  type,
  ST_Multi(geometry),
  geometry_hash,
  covered
FROM all_lines
WHERE geometry IS NOT NULL
  AND NOT ST_IsEmpty(geometry)
  -- Exclude non-lines
  AND ST_GeometryType(geometry) IN ('ST_MultiLineString', 'ST_LineString')
RETURNING id
