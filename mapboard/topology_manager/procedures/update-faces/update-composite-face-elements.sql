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
delete_elements AS (
  DELETE FROM {topo_schema}.map_face f
  WHERE map_layer = :composite_layer
    AND source_id IS NULL
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
    AND f.unit_id IS NOT NULL
    AND f.unit_id != 'none'
),
composite_primitives AS (
  /*
  Primitives that are already in the composite layer.
  These are not considered for insertion, but we may want to update them
  if they are in the targeted map layer and have no overlay.
  */
  SELECT
    r.element_id,
    f.id
  FROM {topo_schema}.map_face f
  JOIN {topo_schema}.relation r
    ON r.topogeo_id = (f.topo).id
   AND r.layer_id = (f.topo).layer_id
  WHERE r.element_type = 3
    AND f.map_layer = :composite_layer
    AND f.source_layer = ANY(:overlay_layers || ARRAY[:map_layer])
    AND f.unit_id IS NOT NULL
    AND f.unit_id != 'none'
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
  WHERE r.element_type = 3
    AND f.map_layer = :map_layer
    -- Only consider features that aren't already in the composite layer.
    AND f.id NOT IN (SELECT id FROM composite_primitives)
    -- Only consider identified features.
    AND f.unit_id IS NOT NULL
    AND f.unit_id != 'none'
),
feature_summary AS (
  SELECT f.id,
    f.unit_id,
    count(element_id) all_count,
    sum(has_overlay::integer) overlay_count,
    (SELECT array_agg(ARRAY[element_id, 3])  FROM layer_features lf WHERE lf.id = f.id AND NOT has_overlay) AS topo_elements
  FROM layer_features f
  GROUP BY f.id, f.unit_id
),
delete_overlapping_features AS (
  -- Delete existing features in the composite layer that overlap the features
  DELETE FROM {topo_schema}.map_face f
  USING {topo_schema}.relation r,
    layer_features lf
  WHERE f.map_layer = :composite_layer
    AND r.topogeo_id = (f.topo).id
    AND r.layer_id = (f.topo).layer_id
    AND r.element_type = 3
    AND r.element_id = lf.element_id
    AND NOT lf.has_overlay
),
p1 AS (
  SELECT
    f.id,
    f.unit_id,
    CASE WHEN f.overlay_count = 0 THEN
      mf.topo
    ELSE
      topology.createTopoGeom(:topo_name, 3, (SELECT layer_id FROM layer_info), topo_elements)
    END AS topo
  FROM feature_summary f
  JOIN {topo_schema}.map_face mf
    ON f.id = mf.id
  WHERE f.overlay_count < all_count
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
-- SELECT
--   f.id,
--   f.unit_id,
--   :map_layer,
--   :composite_layer,
--   f.topo,
--   f.geometry
-- FROM {topo_schema}.map_face f
-- WHERE f.id IN (SELECT id FROM feature_summary WHERE overlay_count = 0)
-- UNION ALL
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
