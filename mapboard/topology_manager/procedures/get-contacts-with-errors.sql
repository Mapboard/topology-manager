SELECT
  l.id,
  l.topology_error
FROM {data_schema}.linework l
WHERE
  {topo_schema}.get_topological_map_layer(l) IS NOT null
  AND l.topology_error IS NOT null
