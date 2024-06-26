SELECT
  l.id,
  {topo_schema}.update_linework_topo(l) err
FROM {data_schema}.linework l
WHERE {topo_schema}.line_topology(l) IS NOT null
  AND l.topology_error IS NULL
  AND geometry_hash IS NULL
ORDER BY ST_Length(geometry)
LIMIT :n
