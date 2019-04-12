-- https://www.zimmi.cz/posts/2017/postgis-as-a-mapbox-vector-tiles-generator/

CREATE OR REPLACE FUNCTION
tiles.createVectorTile(coord tile_coord)
RETURNS bytea
AS $$
DECLARE
srid integer;
mercator_bbox geometry;
projected_bbox geometry;
res bytea;
BEGIN

SELECT ST_SRID(geometry)
INTO srid
FROM map_topology.face_display
LIMIT 1;

mercator_bbox := TileBBox(coord.z, coord.x, coord.y, 3857);
projected_bbox := ST_Transform(mercator_bbox, srid);

SELECT
  ST_AsMVT(a, 'polygon', 4096, 'geom')
INTO res
FROM (
SELECT
  ST_AsMVTGeom(
    ST_Transform(geometry, 3857),
    mercator_bbox
  ) geom
FROM map_topology.face_display
WHERE ST_Intersects(geometry, projected_bbox)
) a;

RETURN res;

END;
$$
LANGUAGE plpgsql IMMUTABLE;
