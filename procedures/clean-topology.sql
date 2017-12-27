DELETE FROM map_topology.relation
WHERE layer_id = map_topology.__linework_layer_id()
  AND topogeo_id NOT IN (
  SELECT (topo).id FROM map_digitizer.linework
  );

DELETE FROM map_topology.relation
WHERE layer_id = map_topology.__map_face_layer_id()
  AND topogeo_id NOT IN (
  SELECT (topo).id FROM map_topology.map_face
  );

SELECT
  topology.ST_RemEdgeModFace('map_topology', edge_id)
FROM map_topology.edge_data
WHERE edge_id NOT IN (
  SELECT element_id
  FROM map_topology.relation
  WHERE element_type = 2
);

SELECT topology.ST_RemIsoNode('map_topology',node_id)
FROM map_topology.node
WHERE node_id NOT IN (SELECT node_id FROM map_topology.node_edge);

SELECT map_topology.healEdges();
