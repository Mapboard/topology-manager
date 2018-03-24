SELECT
  map_topology.update_linework_topo(l) e
FROM map_digitizer.linework l
WHERE geometry_hash IS null
  AND map_topology.line_topology(l.type) IS NOT null
  AND l.topology_error IS null
LIMIT 1

