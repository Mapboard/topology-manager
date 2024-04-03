INSERT INTO {data_schema}.{table} (geometry, type, map_layer )
VALUES (
  ST_Multi(ST_SetSRID((:geometry)::geometry, :srid)),
  :type,
  (SELECT id FROM {data_schema}.map_layer WHERE name = :map_layer)
)
RETURNING *
