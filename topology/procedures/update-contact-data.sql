UPDATE map_topology.contact c
SET
  type = l.type,
  certainty = l.certainty,
  map_width = l.map_width,
  hidden = l.hidden
FROM
  map_digitizer.linework l
WHERE c.id = l.id
