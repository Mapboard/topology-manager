WITH node_edge AS (
SELECT
  node_id,
  unnest(edges) edge_id
FROM map_topology.node_edge
WHERE n_edges = 2
  AND edges[1] != edges[2]
),
ec AS (
SELECT
  node_id,
  array_agg(contact_id) contacts,
  array_agg(ec.edge_id) edges
FROM node_edge ne
JOIN map_topology.edge_contact ec
  ON ne.edge_id = ec.edge_id
GROUP BY node_id
)
SELECT
  edges[1] edge1,
  edges[2] edge2
FROM ec
WHERE contacts[1] = contacts[2]
  AND array_length(edges,1) = 2
  AND array_length(contacts,1) = 2
