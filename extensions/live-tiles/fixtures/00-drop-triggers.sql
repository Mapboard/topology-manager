-- Linework trigger
DROP TRIGGER IF EXISTS map_topology_topo_line_notify_trigger
ON map_digitizer.linework;

-- Polygon trigger
DROP TRIGGER IF EXISTS map_topology_topo_map_face_trigger
ON map_topology.map_face;