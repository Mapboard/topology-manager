INSERT INTO {data_schema}.{table} (geometry, type, layer )
VALUES (
  ST_Multi(ST_SetSRID((:geometry)::geometry, :srid)),
  :type,
  :layer
)
RETURNING *
