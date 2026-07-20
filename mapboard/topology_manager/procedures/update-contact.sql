SELECT
  l.id,
  {topo_schema}.update_boundary_topo(l) err
FROM {boundary_table} l
WHERE {topo_schema}.get_topological_map_layer(l) IS NOT null
  AND l.topology_error IS NULL
  AND geometry_hash IS NULL
ORDER BY ST_MemSize(geometry) DESC
LIMIT :n
