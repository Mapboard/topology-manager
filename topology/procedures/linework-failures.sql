CREATE TABLE IF NOT EXISTS map_topology.linework_failures (
  id integer REFERENCES map_digitizer.linework ON DELETE CASCADE
);

CREATE OR REPLACE VIEW map_topology.invalid_linework AS
SELECT
  f.id,
  geometry,
  type
FROM map_topology.linework_failures f
JOIN map_digitizer.linework l ON l.id = f.id;

TRUNCATE TABLE map_topology.linework_failures;

INSERT INTO map_topology.linework_failures (id)
SELECT id
FROM UNNEST(CAST(:values AS integer[])) id;
