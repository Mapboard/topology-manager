DROP MATERIALIZED VIEW IF EXISTS mapping.contact CASCADE;
CREATE MATERIALIZED VIEW mapping.contact AS
  SELECT
    c.id,
    t.id AS type,
    t.color,
    c.geometry::geometry,
    c.map_width,
    t.bedrock
  FROM map_topology.contact c
  JOIN map_digitizer.linework_type t ON t.id = c.type
  WHERE t.id = 'contact';

CREATE INDEX mapping_contact_gix ON mapping.contact USING GIST (geometry);


