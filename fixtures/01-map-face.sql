-- Map face
DROP MATERIALIZED VIEW IF EXISTS mapping.map_face CASCADE;
CREATE MATERIALIZED VIEW mapping.map_face AS
WITH face AS (
  SELECT
    (ST_Dump(ST_Polygonize(e.geometry))).geom geometry
  FROM map_topology.topology_edges e
  WHERE e.topology = 'bedrock'
),
polygon AS (
  SELECT
    p.id,
    p.type,
    p.geometry
  FROM map_digitizer.polygon p
  JOIN mapping.unit unit ON p.type = unit.id
),
pf AS (
SELECT
  p.id,
  p.type,
  face.geometry
FROM face
LEFT JOIN polygon p
    ON ST_Contains(face.geometry, p.geometry)
WHERE face.geometry IS NOT NULL
)
SELECT DISTINCT ON (geometry)
 row_number() OVER () AS id,
 type unit_id,
 geometry,
 u.color
FROM pf
JOIN mapping.unit u ON type = u.id
ORDER BY geometry, type;

CREATE INDEX map_face_gix ON mapping.map_face USING GIST (geometry);

