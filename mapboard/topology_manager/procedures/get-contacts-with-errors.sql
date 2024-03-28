SELECT
  l.id,
  l.topology_error
FROM {data_schema}.linework l
WHERE
  {topo_schema}.line_topology(l) IS NOT null
  AND l.topology_error IS NOT null
