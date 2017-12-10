SELECT
  l.id
FROM map_digitizer.linework l
LEFT JOIN map_topology.contact c
  ON l.id = c.id
JOIN map_digitizer.linework_type t
  ON t.id = l.type
WHERE c.id IS null
   OR c.geometry IS null
  AND t.topology IS NOT null;

