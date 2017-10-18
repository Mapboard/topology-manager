INSERT INTO map_topology.contact (id, geometry, hash)
SELECT
  id,
  topology.toTopoGeom(geometry, 'map_topology',
    (SELECT layer_id FROM topology.layer WHERE schema_name='map_topology' AND table_name='contact'), 1),
  md5(ST_AsBinary(geometry))::uuid
FROM map_digitizer.linework l
--JOIN mapping.linework_type t
--  ON l.type = t.
WHERE id = :id
RETURNING (geometry IS null);
