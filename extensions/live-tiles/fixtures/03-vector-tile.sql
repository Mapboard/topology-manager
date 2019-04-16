-- https://www.zimmi.cz/posts/2017/postgis-as-a-mapbox-vector-tiles-generator/

CREATE OR REPLACE FUNCTION
tiles.createVectorTile(coord tile_coord)
RETURNS bytea
AS $$
DECLARE
srid integer;
mercator_bbox geometry;
projected_bbox geometry;
bedrock bytea;
surface bytea;
line bytea;
zres float;
BEGIN

SELECT ST_SRID(geometry)
INTO srid
FROM map_topology.face_display
LIMIT 1;

mercator_bbox := TileBBox(coord.z, coord.x, coord.y, 3857);
projected_bbox := ST_Transform(mercator_bbox, srid);

zres := ZRes(coord.z)/2;

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
  FROM map_topology.face_display
  WHERE ST_Intersects(geometry, projected_bbox)
    AND topology = 'bedrock'
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
  FROM map_topology.face_display
  WHERE ST_Intersects(geometry, projected_bbox)
    AND topology = 'surficial'
    AND unit_id != 'surficial-none'
) a;


RETURN bedrock || surface;

END;
$$
LANGUAGE plpgsql;
