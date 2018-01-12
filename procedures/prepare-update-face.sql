SELECT map_topology.register_face_unit(id) FROM map_topology.map_face
WHERE topo IS NOT null
  AND id NOT IN (SELECT DISTINCT map_face FROM map_topology.face_type);

WITH e AS (
SELECT
  element_id,
  f.id,
  f.topology
FROM map_topology.relation r
JOIN map_topology.map_face f
  ON (f.topo).id = r.topogeo_id
 AND (f.topo).layer_id = r.layer_id
WHERE element_type = 3
),
v1 AS (
SELECT
  element_id,
  array_agg(id) ids,
  topology,
  count(*)
FROM e
GROUP BY element_id, topology
),
/* Prepare deletion of areas with multiple faces
(this is kind of a hack that obscures a problem
with referential integrity). Perhaps should add a
CHECK constraint to bring this forward. */
v2 AS (
INSERT INTO map_topology.__dirty_face (id, topology)
SELECT element_id, topology
FROM v1
WHERE count > 1
ON CONFLICT DO NOTHING
),
v3 AS (
SELECT unnest(ids) id FROM v1 WHERE count > 1
)
DELETE FROM map_topology.map_face f
USING v3
WHERE f.id = v3.id;

