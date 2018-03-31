SELECT
  l.id,
  map_topology.update_linework_topo(l) err
FROM map_digitizer.linework l
WHERE map_topology.line_topology(l.type) IS NOT null
  AND l.topology_error IS NULL
  AND geometry_hash IS NULL
ORDER BY ST_Length(geometry)
LIMIT ${n}
