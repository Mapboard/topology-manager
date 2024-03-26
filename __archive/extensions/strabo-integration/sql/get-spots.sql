SELECT
  s.id,
  t.data->> 'color' AS tag_color,
  s.data
FROM strabo.spots s
LEFT JOIN strabo.spot_tags st ON s.id = st.spot_id
LEFT JOIN strabo.tags t ON st.tag_id = t.id;