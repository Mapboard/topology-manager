INSERT INTO map_digitizer.linework
SELECT
  map_topology.update_linework_topo(linework)
FROM map_digitizer.linework
WHERE geometry_hash IS null
LIMIT 1;

