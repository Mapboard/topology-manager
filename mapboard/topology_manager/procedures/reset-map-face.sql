/*
Procedure to create map faces in bulk after deleting all of them.
*/
-- Every topology face is dirty
INSERT INTO ${topo_schema~}.__dirty_face (id, topology)
SELECT face_id, st.id
FROM ${topo_schema~}.face
CROSS JOIN ${topo_schema~}.subtopology st
ON CONFLICT DO NOTHING;

TRUNCATE TABLE ${topo_schema~}.map_face CASCADE;

