WITH overlay_primitives AS (
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
    r.element_id,
    op.element_id IS NOT NULL AS has_overlay
  FROM {topo_schema}.map_face f
  JOIN {topo_schema}.relation r
    ON (f.topo).id = r.topogeo_id
   AND r.layer_id = (f.topo).layer_id
  LEFT JOIN overlay_primitives op
    ON r.element_id = op.element_id
  WHERE r.element_type = 3
    AND f.map_layer = :current_layer
)
SELECT
  f.id,
  count(element_id) all_count,
  sum(has_overlay::integer) overlay_count,
  array_remove(array_agg(case when not has_overlay then element_id end), null) AS no_overlay_elements
FROM layer_features f
GROUP BY f.id;
