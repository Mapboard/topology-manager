UPDATE map_topology.contact c
SET
  type = l.type,
  map_width = l.map_width
FROM
  map_digitizer.linework l
WHERE c.id = l.id
