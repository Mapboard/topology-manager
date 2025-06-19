WITH layer_info AS (
  SELECT
    layer_id
  FROM
    topology.layer
  WHERE
    schema_name = :topo_name
    AND table_name = 'map_face'
    AND feature_column = 'topo'

),
overlay_primitives AS (
  SELECT
    r.element_id
  FROM {topo_schema}.map_face f
  JOIN {topo_schema}.relation r
    ON (f.topo).id = r.topogeo_id
  AND r.layer_id = (f.topo).layer_id
  WHERE r.element_type = 3
    -- Looking at all overlay layers, rather than the accumulating composite layer,
    -- prevents us from having to consider ordering issues in composite feature insertion.
    -- However, it might be a bit slower for multiple overlapping layers.
    AND f.map_layer = ANY(:overlay_layers)
),
 layer_features AS (
  SELECT
    f.id,
    f.unit_id,
    r.element_id,
    op.element_id IS NOT NULL AS has_overlay
  FROM {topo_schema}.map_face f
  JOIN {topo_schema}.relation r
    ON (f.topo).id = r.topogeo_id
   AND r.layer_id = (f.topo).layer_id
  LEFT JOIN overlay_primitives op
    ON r.element_id = op.element_id
  WHERE r.element_type = 3
    AND f.map_layer = :map_layer
),
feature_summary AS (SELECT f.id,
                           f.unit_id,
                           count(element_id)         all_count,
                           sum(has_overlay::integer) overlay_count,
                           array_remove(array_agg(case when not has_overlay then element_id end),
                                          null) AS no_overlay_elements
                    FROM layer_features f
                    GROUP BY f.id, f.unit_id
),
p1 AS (SELECT f.id,
              f.unit_id,
              topology.createTopoGeom(
                :topo_name, 3, (SELECT layer_id FROM layer_info), (
                  SELECT array_agg(ARRAY[e.element_id, 3]) FROM layer_features e
                  WHERE e.id = f.id AND NOT e.has_overlay
                )) AS topo
       FROM feature_summary f
       WHERE f.id IN (SELECT id FROM feature_summary WHERE overlay_count > 0 AND overlay_count < all_count)
)
INSERT INTO {topo_schema}.map_face (
  unit_id,
  topo,
  map_layer,
  geometry
)
SELECT
  f.unit_id,
  f.topo,
  :composite_layer,
  f.geometry
FROM {topo_schema}.map_face f
WHERE f.id IN (SELECT id FROM feature_summary WHERE overlay_count = 0)
UNION ALL
SELECT
  p1.unit_id,
  p1.topo,
  :composite_layer,
  st_setsrid(p1.topo::geometry, :srid)
FROM p1
RETURNING id
