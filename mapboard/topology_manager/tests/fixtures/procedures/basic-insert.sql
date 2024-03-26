WITH newline AS (
  INSERT INTO {data_schema}.linework (
    geometry,
    type
  ) VALUES (
   ST_SetSRID('LINESTRING(16.17 -24.364,16.182 -24.348)'::geometry, :srid),
  'bedrock'
  ) RETURNING *
)
SELECT
  l.id,
  l.geometry,
  l.type,
  t.name
FROM newline l
JOIN {data_schema}.linework_type t
  ON l.type = t.id;