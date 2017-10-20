SELECT
  l.id
FROM map_digitizer.linework l
LEFT JOIN map_topology.contact c
  ON l.id = c.id
WHERE c.id IS null
   OR c.geometry IS null;

