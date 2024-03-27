INSERT INTO {data_schema}.map_layer (id, name, topological)
VALUES
  ('surficial', 'Surficial', true),
  ('bedrock', 'Bedrock', true),
  ('other', 'Other', false);

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

INSERT INTO {data_schema}.polygon_type
SELECT id, name, color
FROM tmp_polygon_type
ON CONFLICT (id)
DO UPDATE
SET
name = EXCLUDED.name,
color = EXCLUDED.color;

/**
-- Linking tables for the next stage of this.

INSERT INTO {data_schema}.map_layer_linework_type (layer, type)
SELECT DISTINCT ON (layer, id)
  layer, id
FROM tmp_linework_type
ON CONFLICT DO NOTHING;

INSERT INTO {data_schema}.map_layer_polygon_type (layer, type)
SELECT DISTINCT ON (layer, id)
  layer, id
FROM tmp_polygon_type
ON CONFLICT DO NOTHING;
*/

DELETE FROM {data_schema}.linework_type
WHERE id NOT IN (SELECT id FROM tmp_linework_type);

DELETE FROM {data_schema}.polygon_type
WHERE id NOT IN (SELECT id FROM tmp_polygon_type);

DROP TABLE tmp_linework_type;
DROP TABLE tmp_polygon_type;
