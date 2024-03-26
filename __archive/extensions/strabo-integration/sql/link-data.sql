INSERT INTO map_digitizer.polygon_type
SELECT
	id,
  id tag_id,
	data->>'name' AS name,
	coalesce(data->>'color', '#AAAAAA') AS color,
  'main' topology
FROM strabo.tags t
WHERE data->>'type' = 'geologic_unit'

-- INSERT INTO map_digitizer.polygon
--SELECT * FROM spots