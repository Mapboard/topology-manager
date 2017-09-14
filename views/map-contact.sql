CREATE SCHEMA IF NOT EXISTS map_display;

DROP MATERIALIZED VIEW IF EXISTS map_display.contact CASCADE;
CREATE MATERIALIZED VIEW map_display.contact AS
  WITH all_contacts AS (
    SELECT
      c.id,
      t.id AS type,
      t.color,
      c.geometry,
      c.map_width,
      t.bedrock
    FROM mapping.contact c
    JOIN mapping.linework_type t ON t.id = c.type
    WHERE NOT arbitrary
  ),
  surface AS (
    SELECT ST_Union(geometry) FROM mapping.surficial_face WHERE unit_id IS NOT null
  )
  SELECT
    id,
    type,
    color,
    geometry::geometry,
    map_width,
    bedrock
  FROM all_contacts
  WHERE type = 'surficial'
  UNION ALL
  SELECT
    id,
    type,
    color,
    geometry::geometry,
    map_width,
    bedrock
  FROM all_contacts
  WHERE bedrock;

CREATE INDEX map_display_contact_gix ON map_display.contact USING GIST (geometry);


