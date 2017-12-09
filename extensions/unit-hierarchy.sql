--ALTER TABLE map_digitizer.polygon_type ADD COLUMN member_of text
--REFERENCES map_digitizer.polygon_type(id);

CREATE OR REPLACE VIEW map_topology.unit_tree AS
WITH RECURSIVE t(member_of) AS (
       SELECT unit.member_of,
          unit.id::text AS id,
          ARRAY[unit.id::text] AS hierarchy,
          1 AS n_levels
         FROM map_digitizer.polygon_type unit
      UNION ALL
       SELECT u2.member_of,
          t_1.id,
          u2.id::text || t_1.hierarchy,
          t_1.n_levels + 1
         FROM t t_1
           JOIN map_digitizer.polygon_type u2 ON t_1.member_of = u2.id
      )
SELECT DISTINCT ON (t.id) t.id,
  t.hierarchy AS tree,
  t.n_levels
 FROM t
ORDER BY t.id, t.n_levels DESC;


-- The commonality between two units
-- (units are part of the same what?)
CREATE OR REPLACE
  FUNCTION map_topology.unit_commonality(text, text)
  RETURNS integer AS $$
    WITH t AS (
      SELECT UNNEST(tree) id
      FROM map_topology.unit_tree
      WHERE id = $1
      INTERSECT
      SELECT UNNEST(tree) id
      FROM map_topology.unit_tree
      WHERE id = $2
    )
    SELECT count(*)::integer
    FROM t
$$ LANGUAGE SQL;


-- Subunits of a unit
CREATE OR REPLACE FUNCTION map_topology.subunits(text) RETURNS text[] AS $$
    SELECT ARRAY(SELECT id
      FROM map_topology.unit_tree
      WHERE $1 = ANY(tree));
$$ LANGUAGE SQL;

DROP MATERIALIZED VIEW IF EXISTS map_topology.contact_display;
CREATE MATERIALIZED VIEW map_topology.contact_display AS
WITH face_unit AS (
SELECT DISTINCT ON (f.face_id)
  f.face_id,
  m.unit_id,
  m.topology
FROM map_topology.face_data f
LEFT JOIN map_topology.map_face m
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
JOIN map_topology.contact c
  ON ec.contact_id = c.id
JOIN map_topology.edge_data e ON ec.edge_id = e.edge_id
JOIN map_digitizer.linework_type t
  ON c.type = t.id
 AND eu.topology = t.topology
WHERE c.type = 'contact'
  AND array_length(eu.units,1) > 1
),
--SELECT * FROM main;
--- We could split this out if we don't want to define
--- commonality levels in all cases
vals AS (
SELECT c.*,
  coalesce(map_topology.unit_commonality(units[1], units[2]),-1) commonality
FROM main c
WHERE type = 'contact'
)
SELECT DISTINCT ON (id)
  id,
  geometry,
  (2-commonality)*0.5 AS width
FROM vals v;

CREATE INDEX map_topology_contact_display_gix ON map_topology.contact_display
  USING GIST (geometry);

