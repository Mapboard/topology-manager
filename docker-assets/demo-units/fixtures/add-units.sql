INSERT INTO ${topo_schema~}.subtopology (id)
VALUES
  ('surficial'),
  ('bedrock')
ON CONFLICT DO NOTHING;

DELETE FROM ${data_schema~}.linework_type WHERE id = 'default';
DELETE FROM ${data_schema~}.polygon_type WHERE id = 'default';

CREATE TEMP TABLE tmp_linework_type
AS
SELECT * FROM ${data_schema~}.linework_type
WITH NO DATA;


COPY tmp_linework_type (id,name,color,topology)
FROM '/app/docker-assets/demo-units/linework-types.csv'
DELIMITER ',' CSV HEADER;

INSERT INTO ${data_schema~}.linework_type
SELECT id, name, color, topology
FROM tmp_linework_type
ON CONFLICT (id)
DO UPDATE
SET
name = EXCLUDED.name,
color = EXCLUDED.color,
topology = EXCLUDED.topology;

DELETE FROM ${data_schema~}.linework_type
WHERE id NOT IN (SELECT id FROM tmp_linework_type);

DROP TABLE tmp_linework_type;

-- Polygons

CREATE TEMP TABLE tmp_polygon_type
AS
SELECT * FROM ${data_schema~}.polygon_type
WITH NO DATA;

COPY tmp_polygon_type (id,name,color,topology)
FROM '/app/docker-assets/demo-units/polygon-types.csv'
DELIMITER ',' CSV HEADER;

INSERT INTO ${data_schema~}.polygon_type
SELECT id, name, color, topology
FROM tmp_polygon_type
ON CONFLICT (id)
DO UPDATE
SET
name = EXCLUDED.name,
color = EXCLUDED.color,
topology = EXCLUDED.topology;

DELETE FROM ${data_schema~}.polygon_type
WHERE id NOT IN (SELECT id FROM tmp_polygon_type);

DROP TABLE tmp_polygon_type;
