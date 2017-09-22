DROP MATERIALIZED VIEW IF EXISTS mapping.contact CASCADE;
CREATE MATERIALIZED VIEW mapping.contact AS
WITH face_unit AS (
SELECT DISTINCT ON (f.face_id)
  f.face_id,
  m.unit_id
FROM map_topology.face_data f
LEFT JOIN mapping.map_face m
  ON ST_Contains(m.geometry, ST_Centroid(f.geometry))
), edge_unit AS (
SELECT
  array_agg(unit_id::text) units,
  edge_id
FROM map_topology.edge_face e
JOIN face_unit f
  ON e.face_id = f.face_id
  GROUP BY edge_id
), contact_data AS (
SELECT
  e.edge_id id,
  c.id AS contact_id,
  c.map_width,
  t.color,
  t.id AS type,
  e.geom geometry
FROM map_topology.edge_contact ec
JOIN map_topology.contact c ON ec.contact_id = c.id
JOIN map_topology.edge_data e ON ec.edge_id = e.edge_id
JOIN map_digitizer.linework_type t ON c.type = t.id
WHERE t.topology = 'bedrock'
)
SELECT DISTINCT ON (c.id)
  c.*,
  units
FROM edge_unit e
JOIN contact_data c
  ON e.edge_id = c.id
-- ONLY join where there is a boundary between two different,
-- defined units
WHERE NOT coalesce(units[1] = ALL(units), true);

CREATE INDEX mapping_contact_gix ON mapping.contact USING GIST (geometry);


