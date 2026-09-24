SELECT
  l.id,
  l.topology_error
FROM {boundary_table} l
WHERE
  {topo_schema}.get_topological_map_layer(l) IS NOT null
  AND l.topology_error IS NOT null
  AND ({row_filter})
ORDER BY l.id
