INSERT INTO {topo_schema}.__dirty_face (id, topology)
SELECT f.face_id, st.id FROM {topo_schema}.face f
CROSS JOIN {data_schema}.map_layer st
WHERE face_id NOT IN (
  SELECT face_id FROM {topo_schema}.face_type
  WHERE face_id != 0
    AND topology = st.id)
AND st.topological
ON CONFLICT DO NOTHING

