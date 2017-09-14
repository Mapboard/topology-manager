-- Map face
DROP MATERIALIZED VIEW IF EXISTS mapping.map_face CASCADE;
CREATE MATERIALIZED VIEW mapping.map_face AS
  WITH face AS (
    SELECT
      (ST_Dump(ST_Polygonize(e.geom))).geom geometry
    FROM map_topology.edge_contact ec
    JOIN map_topology.contact c ON ec.contact_id = c.id
    JOIN map_topology.edge e ON ec.edge_id = e.edge_id
    WHERE c.type = 'contact'
  ),
  point AS (
    SELECT
      p.unit_id,
      p.geometry
    FROM mapping.lithology_point p
    LEFT JOIN mapping.unit unit ON p.unit_id = unit.id
    WHERE p.used = true
      AND unit.bedrock = true
    ORDER BY p.id)
  SELECT DISTINCT ON (face.geometry)
    row_number() OVER () face_id,
    face.geometry,
    unit.id AS unit_id,
    unit.color
  FROM face
    LEFT JOIN point ON ST_Intersects(face.geometry, point.geometry)
    LEFT JOIN mapping.unit unit ON point.unit_id = unit.id
  WHERE face.geometry IS NOT NULL;
CREATE INDEX bedrock_face_gix ON mapping.bedrock_face USING GIST (geometry);


CREATE INDEX map_face_gix ON mapping.map_face USING GIST (geometry);

