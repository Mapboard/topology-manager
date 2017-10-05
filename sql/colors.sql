SELECT
  id::text,
  fgdc_color
FROM ${schema~}.${table~}
WHERE fgdc_color IS NOT null
ORDER BY id
