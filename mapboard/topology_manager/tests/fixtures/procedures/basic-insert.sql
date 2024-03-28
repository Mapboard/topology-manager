WITH newline AS (
  INSERT INTO {data_schema}.linework (
    geometry,
    type,
    map_layer
  ) VALUES (
   ST_SetSRID('LINESTRING(16.17 -24.364,16.182 -24.348)'::geometry, :srid),
  'bedrock',
  (SELECT id FROM {data_schema}.map_layer WHERE name = 'bedrock')
  ) RETURNING *
)
SELECT
  l.id,
  l.geometry,
  l.type,
  l.map_layer,
  t.name AS type_name,
  ml.name AS layer_name
FROM newline l
JOIN {data_schema}.linework_type t
  ON l.type = t.id
JOIN {data_schema}.map_layer ml
  ON l.map_layer = ml.id;