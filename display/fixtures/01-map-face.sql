-- Map face
DROP MATERIALIZED VIEW IF EXISTS mapping.map_face CASCADE;
CREATE MATERIALIZED VIEW mapping.map_face AS
WITH face AS (
  SELECT
    topology,
    (ST_Dump(ST_Polygonize(e.geometry))).geom geometry
  FROM map_topology.topology_edges e
  GROUP BY e.topology
),
polygon AS (
  SELECT
    p.id,
    p.type,
    p.geometry,
    t.topology
  FROM map_digitizer.polygon p
  JOIN map_digitizer.polygon_type t
    ON p.type = t.id
),
pf AS (
SELECT
  p.id,
  p.type,
  face.geometry
FROM face
LEFT JOIN polygon p
    ON ST_Contains(face.geometry, p.geometry)
   AND p.topology = face.topology
WHERE face.geometry IS NOT NULL
)
SELECT DISTINCT ON (geometry)
 row_number() OVER () AS id,
 type unit_id,
 geometry,
 t.topology,
 t.color
FROM pf
JOIN map_digitizer.polygon_type t ON type = t.id
ORDER BY geometry, type;

CREATE INDEX map_face_gix ON mapping.map_face USING GIST (geometry);

