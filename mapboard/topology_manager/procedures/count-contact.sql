SELECT count(*)::integer nlines
FROM {boundary_table} l
WHERE geometry_hash IS null
  AND {topo_schema}.get_topological_map_layer(l) IS NOT null
  AND l.topology_error IS null

