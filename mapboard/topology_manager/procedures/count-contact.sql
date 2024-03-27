SELECT count(*)::integer nlines
FROM {data_schema}.linework l
WHERE geometry_hash IS null
  AND {topo_schema}.line_topology(l) IS NOT null
  AND l.topology_error IS null

