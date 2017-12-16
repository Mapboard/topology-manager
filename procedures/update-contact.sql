SELECT
  map_topology.update_linework_topo(l)
FROM map_digitizer.linework l
WHERE geometry_hash IS null
LIMIT 1

