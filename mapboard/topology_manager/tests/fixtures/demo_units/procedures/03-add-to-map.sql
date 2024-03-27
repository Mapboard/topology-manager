INSERT INTO {data_schema}.map_layer (id, name)
VALUES
  ('surficial', 'Surficial'),
  ('bedrock', 'Bedrock');

DELETE FROM {data_schema}.linework_type WHERE id = 'default';
DELETE FROM {data_schema}.polygon_type WHERE id = 'default';

INSERT INTO {data_schema}.linework_type
SELECT id, name, color
FROM tmp_linework_type
ON CONFLICT (id)
DO UPDATE
SET
name = EXCLUDED.name,
color = EXCLUDED.color;

INSERT INTO {data_schema}.map_layer_linework_type (layer, type)
SELECT DISTINCT ON (layer, id)
  layer, id
FROM tmp_linework_type
ON CONFLICT DO NOTHING;

DELETE FROM {data_schema}.linework_type
WHERE id NOT IN (SELECT id FROM tmp_linework_type);

DROP TABLE tmp_linework_type;

-- Polygons

INSERT INTO {data_schema}.polygon_type
SELECT id, name, color, topology
FROM tmp_polygon_type
ON CONFLICT (id)
DO UPDATE
SET
name = EXCLUDED.name,
color = EXCLUDED.color;

INSERT INTO {data_schema}.map_layer_polygon_type (layer, type)
SELECT DISTINCT ON (layer, id)
  layer, id
FROM tmp_polygon_type
ON CONFLICT DO NOTHING;

DELETE FROM {data_schema}.polygon_type
WHERE id NOT IN (SELECT id FROM tmp_polygon_type);

DROP TABLE tmp_polygon_type;
