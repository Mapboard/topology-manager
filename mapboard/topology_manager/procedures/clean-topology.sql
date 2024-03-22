DELETE FROM ${topo_schema~}.relation
WHERE layer_id = ${topo_schema~}.__linework_layer_id()
AND topogeo_id NOT IN (
  SELECT (topo).id
  FROM ${data_schema~}.linework
  WHERE topo IS NOT null
);

DELETE FROM ${topo_schema~}.relation
WHERE layer_id = ${topo_schema~}.__map_face_layer_id()
AND topogeo_id NOT IN (
  SELECT (topo).id
  FROM ${topo_schema~}.map_face
  WHERE topo IS NOT null
);

SELECT
  topology.ST_RemEdgeModFace( ${topo_schema}, edge_id)
FROM ${topo_schema~}.edge_data
WHERE edge_id NOT IN (
  SELECT element_id
  FROM ${topo_schema~}.relation
  WHERE element_type = 2
)
AND left_face = right_face;

SELECT
  topology.ST_RemEdgeModFace( ${topo_schema}, edge_id)
FROM ${topo_schema~}.edge_data
WHERE edge_id NOT IN (SELECT edge_id FROM ${topo_schema~}.edge_topology);

SELECT topology.ST_RemIsoNode( ${topo_schema},node_id)
FROM ${topo_schema~}.node
WHERE node_id NOT IN (SELECT node_id FROM ${topo_schema~}.node_edge);

SELECT ${topo_schema~}.healEdges();
