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
    AND f.unit_id IS NOT NULL
    AND f.unit_id != 'none'
),
delete_dereferenced_elements AS (
 DELETE FROM {topo_schema}.map_face f
   WHERE map_layer = :composite_layer
     AND source_id IS NULL
),
composite_faces AS (
  /*
  Primitives that are already in the composite layer.
  These are not considered for insertion, but we may want to update them
  if they are in the targeted map layer and have no overlay.
  */
  SELECT f.id
  FROM {topo_schema}.map_face f
  WHERE f.map_layer = :map_layer
    AND f.unit_id IS NOT NULL
    AND f.unit_id != 'none'
  EXCEPT
  SELECT -- Omit faces that are already in the composite layer.
    f.id
  FROM {topo_schema}.map_face f
  WHERE f.map_layer = :composite_layer
  --  AND f.source_layer = ANY(:overlay_layers || ARRAY[:map_layer])
  -- Only consider features that aren't already in the composite layer.
  -- Only consider identified features.
),
layer_features AS (
  /*
  Faces that are are in the targeted map layer and may be overlapped by an overlay layer.

  This doesn't account for features that might already be captured in the composite layer.
  We may want to filter those out.
  */
  SELECT
    f.id,
    r.element_id,
    op.element_id IS NOT NULL AS has_overlay
  FROM composite_faces f
  JOIN {topo_schema}.map_face mf
    ON f.id = mf.id
  JOIN {topo_schema}.relation r
    ON (mf.topo).id = r.topogeo_id
   AND r.layer_id = (mf.topo).layer_id
  LEFT JOIN overlay_primitives op
    ON r.element_id = op.element_id
  WHERE r.element_type = 3
),
feature_summary0 AS (
 SELECT
   f.id,
   sum(has_overlay::integer) > 0 AS any_overlay,
   CASE WHEN sum(has_overlay::integer) > 0 THEN
     topology.createTopoGeom(:topo_name, 3,
                             {topo_schema}.__map_face_layer_id(),
                             array_agg(ARRAY [element_id, 3]) FILTER (WHERE NOT has_overlay)
     )
   END AS topo
 FROM layer_features f
 GROUP BY f.id
 HAVING sum(f.has_overlay::integer) < count(f.element_id) -- face is not entirely covered
),
feature_summary AS (
  SELECT
    f.id,
    mf.unit_id,
    coalesce(f.topo, mf.topo) AS topo,
    coalesce(f.topo::geometry, mf.geometry) AS geometry
  FROM feature_summary0 f
  JOIN {topo_schema}.map_face mf
    ON f.id = mf.id
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
)
INSERT INTO {topo_schema}.map_face (
  source_id,
  unit_id,
  source_layer,
  map_layer,
  topo,
  geometry
)
SELECT
  p1.id,
  p1.unit_id,
  :map_layer,
  :composite_layer,
  p1.topo,
  p1.geometry
FROM feature_summary p1
RETURNING id;
