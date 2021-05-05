SET session_replication_role = replica;

INSERT INTO ${data_schema~}.linework (id, geometry, type, created, certainty, hidden, map_width, pixel_width, source)
SELECT id, wkb_geometry, type, created::timestamp, certainty::numeric, arbitrary::boolean, map_width::numeric, pixel_width::numeric, 'sqlite' FROM ${data_schema~}.linework_import
WHERE wkb_geometry IS NOT null;

INSERT INTO ${data_schema~}.polygon (id, geometry, type, created, certainty, source)
SELECT id, ST_Multi(wkb_geometry), type, created::timestamp, certainty::numeric, 'sqlite' FROM ${data_schema~}.polygon_import
WHERE wkb_geometry IS NOT null;

SET session_replication_role = DEFAULT;

SELECT setval(pg_get_serial_sequence('${data_schema}.linework', 'id'), coalesce(max(id),0)+1, false)
  FROM ${data_schema~}.linework;

SELECT setval(pg_get_serial_sequence('${data_schema}.polygon', 'id'), coalesce(max(id),0)+1, false)
  FROM ${data_schema~}.polygon;

DROP TABLE ${data_schema~}.linework_import;
DROP TABLE ${data_schema~}.polygon_import;

