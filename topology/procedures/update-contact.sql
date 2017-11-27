INSERT INTO map_topology.contact (id, geometry, topo, hash, topology)
SELECT
  l.id,
  geometry,
  topology.toTopoGeom(geometry, 'map_topology',
    (SELECT layer_id FROM topology.layer
      WHERE schema_name='map_topology'
      AND table_name='contact'), 1),
  md5(ST_AsBinary(geometry))::uuid,
  t.topology
FROM map_digitizer.linework l
JOIN map_digitizer.linework_type t
  ON l.type = t.id
WHERE l.id = :id
  AND t.topology IS NOT null
RETURNING (topo IS null);
