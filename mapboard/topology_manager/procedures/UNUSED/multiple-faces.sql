WITH e AS (
-- Get faces related to map_faces
SELECT
  element_id,
  f.id,
  f.map_layer
FROM {topo_schema}.relation r
JOIN {topo_schema}.map_face f
  ON (f.topo).id = r.topogeo_id
 AND (f.topo).layer_id = r.layer_id
WHERE element_type = 3
),
v1 AS (
SELECT
  element_id,
  array_agg(id) ids,
  map_layer,
  count(*)
FROM e
GROUP BY element_id, map_layer
),
/* Prepare deletion of areas with multiple faces
(this is kind of a hack that obscures a problem
with referential integrity). Perhaps should add a
CHECK constraint to bring this forward. */
v2 AS (
INSERT INTO {topo_schema}.__dirty_face (id, map_layer)
SELECT element_id, map_layer
FROM v1
WHERE count > 1
  AND element_id IN (SELECT face_id FROM {topo_schema}.face)
ON CONFLICT DO NOTHING
),
v3 AS (
SELECT unnest(ids) id FROM v1 WHERE count > 1
)
DELETE FROM {topo_schema}.map_face f
USING v3
WHERE f.id = v3.id;
