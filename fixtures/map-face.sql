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
    p.type,
    p.geometry
  FROM map_digitizer.polygon p
  JOIN mapping.unit unit ON p.type = unit.id
  ORDER BY p.id
)
SELECT
  row_number() OVER () face_id,
  face.geometry,
  unit.id AS unit_id,
  coalesce(unit.color, '#000000') color
FROM face
JOIN polygon p
    ON ST_Contains(face.geometry, p.geometry)
JOIN mapping.unit unit ON p.type = unit.id
WHERE face.geometry IS NOT NULL
  AND unit.id NOT IN ('basement','highlands')
ORDER BY ST_Area(face.geometry);

CREATE INDEX map_face_gix ON mapping.map_face USING GIST (geometry);

