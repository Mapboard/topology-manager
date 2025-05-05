/*
Delete map faces that have no edges corresponding to map linework
These should have been caught earlier by trigger process, but weren't
*/
WITH edge_relation AS (
  SELECT
    l.id line_id,
    l.map_layer,
    r.element_id edge_id,
    ml.parent IS NOT null is_child
  FROM {topo_schema}.edge_data e
  JOIN {topo_schema}.relation r
    ON e.edge_id = r.element_id
   AND r.element_type = 2 -- edges
  JOIN {data_schema}.linework l
    ON (l.topo).id = r.topogeo_id
    AND r.layer_id = (l.topo).layer_id
    AND l.topo IS NOT null
  JOIN {data_schema}.map_layer ml
    ON ml.id = r.layer_id
   AND ml.topological
), v1 AS (
SELECT DISTINCT ON (ef.face_id) *
FROM {topo_schema}.edge_face ef
JOIN {topo_schema}.face_type ft ON ef.face_id = ft.face_id
WHERE ef.edge_id NOT IN (
    SELECT edge_id
    FROM edge_relation er
    WHERE NOT er.is_child
  )
  AND ef.face_id != 0
)
DELETE FROM {topo_schema}.map_face f
USING v1
WHERE v1.map_face = f.id;

/* expand dirty faces to cover parent layers.
This is needed because we currently have a bit of a disconnected process.
 */

INSERT INTO {topo_schema}.__dirty_face
SELECT id, {topo_schema}.parent_map_layers(map_layer) FROM {topo_schema}.__dirty_face
ON CONFLICT DO NOTHING;
