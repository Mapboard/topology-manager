SELECT topology.ST_RemIsoNode('map_topology',node_id)
FROM map_topology.node
WHERE node_id NOT IN (SELECT node_id FROM map_topology.node_edge);
