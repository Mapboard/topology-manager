SELECT count(*) nlines
FROM map_digitizer.linework l
WHERE geometry_hash IS null
  AND map_topology.line_topology(l.type) IS NOT null
  AND l.topology_error IS null

