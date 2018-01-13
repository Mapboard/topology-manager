DROP MATERIALIZED VIEW IF EXISTS mapping.contact CASCADE;
CREATE MATERIALIZED VIEW mapping.contact AS
WITH face_unit AS (
SELECT DISTINCT ON (f.face_id)
  f.face_id,
  m.unit_id,
  m.topology
FROM map_topology.face_data f
LEFT JOIN mapping.map_face m
  ON ST_Contains(m.geometry, ST_PointOnSurface(f.geometry))
), edge_unit AS (
SELECT
  array_agg(unit_id::text) units,
  edge_id,
  f.topology
FROM map_topology.edge_face e
LEFT JOIN face_unit f
  ON e.face_id = f.face_id
WHERE unit_id IS NOT null
GROUP BY edge_id, f.topology
),
main AS (
SELECT
  e.edge_id id,
  eu.units,
  c.id AS contact_id,
  c.map_width,
  c.certainty,
  c.hidden,
  t.color,
  t.id AS type,
  e.geom geometry,
  t.topology
FROM edge_unit eu
JOIN map_topology.edge_contact ec
  ON ec.edge_id = eu.edge_id
JOIN map_digitizer.linework c
  ON ec.contact_id = c.id
JOIN map_topology.edge_data e ON ec.edge_id = e.edge_id
JOIN map_digitizer.linework_type t
  ON c.type = t.id
 AND eu.topology = t.topology
),
--- We could split this out if we don't want to define
--- commonality levels in all cases
vals AS (
SELECT c.*,
  CASE WHEN array_length(units,1) = 2 THEN
    coalesce(mapping.unit_commonality(units[1], units[2]),-1)
  ELSE (SELECT max(id) FROM mapping.unit_level) END AS commonality
FROM main c
)
SELECT DISTINCT ON (v.id)
  v.*,
  l.name AS commonality_desc
FROM vals v
LEFT JOIN mapping.unit_level l
  ON commonality = l.id;

CREATE INDEX mapping_contact_gix ON mapping.contact USING GIST (geometry);


