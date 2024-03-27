SET session_replication_role = replica;

UPDATE {data_schema}.linework
SET
  topo = null,
  geometry_hash = null,
  topology_error = null;

TRUNCATE TABLE {topo_schema}.face CASCADE;
TRUNCATE TABLE {topo_schema}.relation CASCADE;
TRUNCATE TABLE {topo_schema}.map_face CASCADE;

INSERT INTO {topo_schema}.face (face_id) VALUES (0);

ALTER SEQUENCE {topo_schema}.node_node_id_seq RESTART WITH 1;
ALTER SEQUENCE {topo_schema}.face_face_id_seq RESTART WITH 1;
ALTER SEQUENCE {topo_schema}.edge_data_edge_id_seq RESTART WITH 1;
ALTER SEQUENCE {topo_schema}.topogeo_s_1 RESTART WITH 1;

SELECT setval(pg_get_serial_sequence('{topo_schema}.map_face', 'id'), coalesce(max(id),0)+1, false)
  FROM {topo_schema}.map_face;
SET session_replication_role = DEFAULT;
VACUUM ANALYZE;
