SELECT
  edge_id
FROM map_topology.edge_data
WHERE edge_id NOT IN (
  SELECT element_id
  FROM map_topology.relation
  WHERE element_type = 2
)
