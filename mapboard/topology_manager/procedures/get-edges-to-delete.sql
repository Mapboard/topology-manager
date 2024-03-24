SELECT
  edge_id
FROM {topo_schema}.edge_data
WHERE edge_id NOT IN (
  SELECT element_id
  FROM {topo_schema}.relation
  WHERE element_type = 2
)
