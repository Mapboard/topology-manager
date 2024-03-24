-- Linework trigger
DROP TRIGGER IF EXISTS map_topology_topo_line_notify_trigger
ON {data_schema}.linework;

-- Polygon trigger
DROP TRIGGER IF EXISTS map_topology_topo_map_face_trigger
ON {topo_schema}.map_face;