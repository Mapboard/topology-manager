/* A set of procedures to rebuild map_topology data from the 'map_digitizer.linework' table */

-- Delete changed geometries from contact
--   maybe we should do an update here instead
DELETE
 FROM map_topology.contact c
USING map_digitizer.linework l
WHERE l.id = c.id
  AND md5(ST_AsBinary(l.geometry))::uuid != c.hash
  OR c.hash IS null;

DELETE FROM
  map_topology.contact c
WHERE c.id NOT IN (SELECT id FROM map_digitizer.linework);


