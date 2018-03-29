SELECT
  map_topology.update_linework_topo(l) err
FROM map_digitizer.linework l
WHERE id = ${id}
