-- Map face
DROP MATERIALIZED VIEW IF EXISTS mapping.map_face CASCADE;
CREATE MATERIALIZED VIEW mapping.map_face AS
WITH face AS (
  SELECT
    (ST_Dump(ST_Polygonize(e.geom))).geom geometry
  FROM map_topology.edge_contact ec
  JOIN map_topology.contact c ON ec.contact_id = c.id
  JOIN map_topology.edge e ON ec.edge_id = e.edge_id
  WHERE c.type LIKE '%contact%'
),
polygon AS (
  SELECT
    p.type,
    p.geometry
  FROM map_digitizer.polygon p
  LEFT JOIN mapping.unit unit ON p.type = unit.id
  ORDER BY p.id
)
SELECT
  row_number() OVER () face_id,
  face.geometry,
  unit.id AS unit_id,
  coalesce(unit.color, '#000000') color
FROM face
  LEFT JOIN polygon p
    ON p.geometry @ face.geometry
LEFT JOIN mapping.unit unit ON p.type = unit.id
WHERE face.geometry IS NOT NULL
ORDER BY ST_Area(face.geometry);

CREATE INDEX map_face_gix ON mapping.map_face USING GIST (geometry);

