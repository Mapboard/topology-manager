INSERT INTO {data_schema}.${table~} (geometry, type )
VALUES (
  ST_Multi(ST_SetSRID(${geometry}::geometry, ${srid})),
  ${type}
)
RETURNING *
