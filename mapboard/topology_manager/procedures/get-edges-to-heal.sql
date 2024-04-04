WITH node_edge AS (
SELECT
  node_id,
  unnest(edges) edge_id
FROM {topo_schema}.node_edge
WHERE n_edges = 2
  AND edges[1] != edges[2]
),
ec AS (
SELECT
  node_id,
  array_agg(line_id) contacts,
  array_agg(ec.edge_id) edges,
  count(r.topogeo_id) n_geom
FROM node_edge ne
JOIN {topo_schema}.__edge_relation ec
  ON ne.edge_id = ec.edge_id
 AND NOT ec.is_child
JOIN {topo_schema}.relation r
  ON ne.edge_id = r.element_id
 AND r.element_type = 2
GROUP BY node_id
)
SELECT
  node_id,
  edges[1] edge1,
  edges[2] edge2,
  n_geom
FROM ec
WHERE contacts[1] = contacts[2]
  AND array_length(edges,1) = 2
  AND array_length(contacts,1) = 2
  AND n_geom < 2

