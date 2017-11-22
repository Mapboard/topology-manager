INSERT INTO map_topology.contact (id, geometry, hash, topology)
SELECT
  id,
  topology.toTopoGeom(geometry, 'map_topology',
    (SELECT layer_id FROM topology.layer
      WHERE schema_name='map_topology'
      AND table_name='contact'), 1),
  md5(ST_AsBinary(geometry))::uuid,
  t.topology
FROM map_digitizer.linework l
JOIN mapping.linework_type t
  ON l.type = t.id
WHERE id = :id
  AND t.topology != null
RETURNING (geometry IS null);
