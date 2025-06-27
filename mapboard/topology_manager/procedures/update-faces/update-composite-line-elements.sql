WITH lines AS (
  SELECT l.*,
        f.geometry face_geom
  FROM {data_schema}.linework l
  LEFT JOIN {topo_schema}.map_face f
    ON l.geometry && f.geometry
  AND ST_Intersects(l.geometry, f.geometry)
  WHERE l.map_layer = :map_layer
    AND l.geometry IS NOT NULL
    AND l.topo IS NOT NULL
    AND f.map_layer = :composite_layer
    AND f.source_layer = ANY(:overlay_layers)
),
all_lines AS (
  SELECT l.id     source_id,
         l.type,
         l.geometry_hash,
  CASE
   WHEN l.face_geom IS NOT NULL THEN
     ST_Difference(l.geometry, l.face_geom)
   ELSE l.geometry
   END AS geometry,
  false AS covered
  FROM lines l
  UNION ALL
  SELECT l.id,
  l.type,
  l.geometry_hash,
  ST_Intersection(l.geometry, l.face_geom) geometry,
  true AS                                  covered
  FROM lines l
  WHERE l.face_geom IS NOT NULL
)
SELECT
  :map_layer AS map_layer,
  source_id,
  :map_layer source_layer,
  type,
  geometry,
  geometry_hash,
  covered
FROM all_lines
WHERE geometry IS NOT NULL
  AND NOT ST_IsEmpty(geometry)
