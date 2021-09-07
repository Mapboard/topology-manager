SELECT
  json_agg(data) features,
  'FeatureCollection' AS "type"
FROM strabo.spots;