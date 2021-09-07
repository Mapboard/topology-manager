-- https://www.zimmi.cz/posts/2017/postgis-as-a-mapbox-vector-tiles-generator/
CREATE OR REPLACE FUNCTION
tiles.createVectorTile(coord tile_coord)
RETURNS bytea
AS $$
DECLARE
srid integer;
mercator_bbox geometry;
projected_bbox geometry;
bedrock_clip geometry;
bedrock bytea;
surface bytea;
contact bytea;
line bytea;
zres float;
BEGIN

SELECT ST_SRID(geometry)
INTO srid
FROM ${topo_schema~}.face_display
LIMIT 1;

mercator_bbox := TileBBox(coord.z, coord.x, coord.y, 3857);
projected_bbox := ST_Transform(mercator_bbox, srid);

zres := ZRes(coord.z)/2;

SELECT
  coalesce(ST_Union(geometry), ST_SetSRID(ST_GeomFromText('POLYGON EMPTY'), srid))
FROM ${topo_schema~}.face_display
INTO bedrock_clip
WHERE ST_Intersects(geometry, projected_bbox)
  AND topology = 'surficial';

SELECT
  ST_AsMVT(a, 'bedrock', 4096, 'geom')
INTO bedrock
FROM (
  SELECT
    id,
    unit_id,
    ST_AsMVTGeom(
      ST_Simplify(
        ST_Transform(geometry, 3857),
        zres/2
      ),
      mercator_bbox
    ) geom
  FROM ${topo_schema~}.face_display
  WHERE ST_Intersects(geometry, projected_bbox)
    AND topology = 'main'
) a;

SELECT
  ST_AsMVT(a, 'surficial', 4096, 'geom')
INTO surface
FROM (
  SELECT
    id,
    unit_id,
    ST_AsMVTGeom(
      ST_Simplify(
        ST_Transform(geometry, 3857),
        zres/2
      ),
      mercator_bbox
    ) geom
  FROM ${topo_schema~}.face_display
  WHERE ST_Intersects(geometry, projected_bbox)
    AND topology = 'surficial'
    AND unit_id != 'surficial-none'
) a;

/*
SELECT
  ST_AsMVT(a, 'contact', 4096, 'geom')
INTO contact
FROM (
SELECT
  e.edge_id,
  er.line_id,
  er.type,
  ST_AsMVTGeom(
    ST_ChaikinSmoothing(
      ST_Segmentize(
        ST_Transform(
          ST_Simplify(e.geom, zres/2),
          3857
        ), zres*6
      ), 1, true
    ),
    mercator_bbox
  ) geom
FROM ${topo_schema~}.edge_data e
JOIN ${topo_schema~}.__edge_relation er
  ON er.edge_id = e.edge_id
JOIN ${topo_schema~}.face_type f1
  ON e.left_face = f1.face_id
 AND er.topology = f1.topology
JOIN ${topo_schema~}.face_type f2
  ON e.right_face = f2.face_id
 AND er.topology = f2.topology
WHERE e.geom && projected_bbox
  AND er.type NOT IN (
    'arbitrary-bedrock',
    'arbitrary-surficial-contact'
)) a;
*/
SELECT
  ST_AsMVT(a, 'contact', 4096, 'geom')
INTO contact
FROM (
SELECT
  l.id,
  l.type,
  lt.topology,
  lt.color,
  ST_AsMVTGeom(
    ST_ChaikinSmoothing(
      ST_Segmentize(
        ST_Transform(
          ST_Simplify(l.geometry, zres/2),
          3857
        ), zres*6
      ), 1, true
    ),
    mercator_bbox
  ) geom
FROM ${data_schema~}.linework l
JOIN ${data_schema~}.linework_type lt
  ON lt.id = l.type
WHERE 
  topology IS NOT null
  AND l.type NOT IN (
    'arbitrary-bedrock',
    'arbitrary-surficial-contact'
)) a;

SELECT
  ST_AsMVT(a, 'line', 4096, 'geom')
INTO line
FROM (
SELECT
  null AS edge_id,
  l.id AS line_id,
  l.type,
  ST_AsMVTGeom(
    ST_ChaikinSmoothing(
      ST_Segmentize(
        ST_Transform(
          ST_Simplify(l.geometry, zres/2),
          3857
        ), zres*6
      ), 1, true
    ),
    mercator_bbox
  ) geom
FROM ${data_schema~}.linework l
JOIN ${data_schema~}.linework_type t
  ON l.type = t.id
WHERE l.geometry && projected_bbox
  AND t.topology IS null
) a;

RETURN bedrock || surface || contact || line;

END;
$$
LANGUAGE plpgsql;
