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
composite_primitives AS (
  /*
  Primitives that are already in the composite layer.
  These are not considered for insertion, but we may want to update them
  if they are in the targeted map layer and have no overlay.
  */
  SELECT
    r.element_id
  FROM {topo_schema}.map_face f
  JOIN {topo_schema}.relation r
    ON r.topogeo_id = (f.topo).id
   AND r.layer_id = (f.topo).layer_id
  WHERE r.element_type = 3
    AND f.map_layer = :composite_layer
    AND f.source_layer = :map_layer
     OR f.source_layer = ANY(:overlay_layers)
),
layer_features AS (
  /*
  Faces that are are in the targeted map layer and may be overlapped by an overlay layer.

  This doesn't account for features that might already be captured in the composite layer.
  We may want to filter those out.
  */
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
  LEFT JOIN composite_primitives cp
    ON r.element_id = cp.element_id
  WHERE r.element_type = 3
    AND f.map_layer = :map_layer
    -- Only consider features that aren't already in the composite layer.
    AND cp.element_id IS NULL
),
feature_summary AS (
  SELECT f.id,
    f.unit_id,
    count(element_id)         all_count,
    sum(has_overlay::integer) overlay_count,
    array_remove(array_agg(case when not has_overlay then element_id end),
                  null) AS no_overlay_elements
  FROM layer_features f
  GROUP BY f.id, f.unit_id
),
overlapping_features AS (
  -- Find all existing features in the composite layer that overlap the features
  SELECT
    f.id
  FROM {topo_schema}.map_face f
  JOIN {topo_schema}.relation r
    ON (f.topo).id = r.topogeo_id
   AND r.layer_id = (f.topo).layer_id
  WHERE r.element_type = 3
    AND r.element_id IN (SELECT r.element_id FROM layer_features r WHERE NOT has_overlay)
    -- Looking at all overlay layers, rather than the accumulating composite layer,
    -- prevents us from having to consider ordering issues in composite feature insertion.
    -- However, it might be a bit slower for multiple overlapping layers.
    AND f.map_layer = :composite_layer
),
delete_overlapping_features AS (
  -- Delete existing features in the composite layer that overlap the features
  DELETE FROM {topo_schema}.map_face f
    WHERE f.id IN (SELECT id FROM overlapping_features)
      AND f.map_layer = :composite_layer
),
p1 AS (
  SELECT
    f.id,
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
  source_id,
  unit_id,
  source_layer,
  map_layer,
  topo,
  geometry
)
-- Features to be inserted as is
SELECT
  f.id,
  f.unit_id,
  :map_layer,
  :composite_layer,
  f.topo,
  f.geometry
FROM {topo_schema}.map_face f
WHERE f.id IN (SELECT id FROM feature_summary WHERE overlay_count = 0)
UNION ALL
-- Features that need to be updated with a new topogeometry
SELECT
  p1.id,
  p1.unit_id,
  :map_layer,
  :composite_layer,
  p1.topo,
  st_setsrid(p1.topo::geometry, :srid)
FROM p1
RETURNING id;
