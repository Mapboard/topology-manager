INSERT INTO map_topology.__dirty_face (id, topology)
SELECT f.face_id, st.id FROM map_topology.face f
CROSS JOIN map_topology.subtopology st
WHERE face_id NOT IN (
  SELECT face_id FROM map_topology.face_type
  WHERE face_id != 0
    AND topology = st.id)
ON CONFLICT DO NOTHING

