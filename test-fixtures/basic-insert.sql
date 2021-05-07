WITH newline AS (
  INSERT INTO ${data_schema~}.linework (
    geometry,
    type,
    pixel_width,
    map_width,
    certainty,
    zoom_level
  ) VALUES (
    (${data_schema~}.Linework_SnapEndpoints(
      ST_Transform(
        ST_SetSRID('LINESTRING(16.17 -24.364,16.182 -24.348)'::geometry, 4326),
        ${data_schema~}.Linework_SRID()),
      0, '{}'::text[]
    )).geometry, 'bedrock', 4.16, 112.66, null, 11.36
  ) RETURNING *
)
SELECT
  l.id,
  ST_Transform(geometry, 4326) geometry,
  type,
  map_width,
  certainty,
  coalesce(color, '#888888') color,
  false AS erased
FROM newline l
JOIN ${data_schema~}.linework_type t
  ON l.type = t.id;