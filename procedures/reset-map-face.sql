/*
Procedure to create map faces in bulk after deleting all of them.
*/
-- Every topology face is dirty
INSERT INTO map_topology.__dirty_face (id, topology)
SELECT face_id, st.id
FROM map_topology.face
CROSS JOIN map_topology.subtopology st
ON CONFLICT DO NOTHING;

TRUNCATE TABLE map_topology.map_face CASCADE;

