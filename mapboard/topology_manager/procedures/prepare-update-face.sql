/* Register units for faces that don't have units */
SELECT {topo_schema}.register_face_unit(id) FROM {topo_schema}.map_face
WHERE topo IS NOT null
  AND id NOT IN (SELECT DISTINCT map_face FROM {topo_schema}.face_type);

WITH e AS (
-- Get faces related to map_faces
SELECT
  element_id,
  f.id,
  f.layer
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
  layer,
  count(*)
FROM e
GROUP BY element_id, layer
),
/* Prepare deletion of areas with multiple faces
(this is kind of a hack that obscures a problem
with referential integrity). Perhaps should add a
CHECK constraint to bring this forward. */
v2 AS (
INSERT INTO {topo_schema}.__dirty_face (id, layer)
SELECT element_id, layer
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

/*
Delete map faces that have no edges corresponding to map linework
These should have been caught earlier by trigger process, but weren't
*/
WITH v1 AS (
SELECT DISTINCT ON (ef.face_id) *
FROM {topo_schema}.edge_face ef
JOIN {topo_schema}.face_type ft ON ef.face_id = ft.face_id
WHERE ef.edge_id NOT IN (SELECT edge_id FROM {topo_schema}.__edge_relation)
  AND ef.face_id != 0
)
DELETE FROM {topo_schema}.map_face f
USING v1
WHERE v1.map_face = f.id;
