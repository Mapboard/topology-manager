/* A set of procedures to rebuild map_topology data from the 'map_digitizer.linework' table */

-- Delete changed geometries from contact
--   maybe we should do an update here instead
DELETE
 FROM {topo_schema}.contact c
USING {data_schema}.linework l
WHERE l.id = c.id
  AND md5(ST_AsBinary(l.geometry))::uuid != c.hash
  OR c.hash IS null;

DELETE FROM
  {topo_schema}.contact c
WHERE c.id NOT IN (SELECT id FROM {data_schema}.linework);


