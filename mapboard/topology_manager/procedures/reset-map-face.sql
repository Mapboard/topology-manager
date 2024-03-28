/*
Procedure to create map faces in bulk after deleting all of them.
*/
-- Every topology face is dirty
INSERT INTO {topo_schema}.__dirty_face (id, layer)
SELECT face_id, ml.id
FROM {topo_schema}.face
CROSS JOIN {data_schema}.map_layer ml
WHERE ml.topological
ON CONFLICT DO NOTHING;

TRUNCATE TABLE {topo_schema}.map_face CASCADE;

