SELECT topology.ST_RemIsoNode(  :topo_name ,node_id)
FROM {topo_schema}.node
WHERE node_id NOT IN (SELECT node_id FROM {topo_schema}.node_edge);
