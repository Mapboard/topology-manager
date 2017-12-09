SET session_replication_role = replica;

INSERT INTO map_digitizer.linework (id, geometry, type, created, certainty, hidden, map_width, pixel_width, source)
SELECT id, wkb_geometry, type, created::timestamp, certainty::numeric, arbitrary::boolean, map_width::numeric, pixel_width::numeric, 'sqlite' FROM map_digitizer.linework_import
WHERE wkb_geometry IS NOT null;

INSERT INTO map_digitizer.polygon (id, geometry, type, created, certainty, source)
SELECT id, ST_Multi(wkb_geometry), type, created::timestamp, certainty::numeric, 'sqlite' FROM map_digitizer.polygon_import
WHERE wkb_geometry IS NOT null;

SET session_replication_role = DEFAULT;

SELECT setval(pg_get_serial_sequence('map_digitizer.linework', 'id'), coalesce(max(id),0)+1, false)
  FROM map_digitizer.linework;

SELECT setval(pg_get_serial_sequence('map_digitizer.polygon', 'id'), coalesce(max(id),0)+1, false)
  FROM map_digitizer.polygon;

DROP TABLE map_digitizer.linework_import;
DROP TABLE map_digitizer.polygon_import;

