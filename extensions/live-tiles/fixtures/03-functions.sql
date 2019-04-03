/* Get tile index for a spherical mercator coordinate value */
CREATE OR REPLACE FUNCTION
tiles.GetTileIndex(n double precision, z integer)
RETURNS integer
AS $$
DECLARE
rng numeric;
BEGIN
-- 2*PI*6378137
rng := 40075016.6855785;
RETURN floor((n/rng+0.5)*2^z)::integer;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE TYPE tile_coord AS (
  x integer,
  y integer,
  z integer
);

CREATE OR REPLACE FUNCTION
tiles.CoveringTiles(geom geometry, z integer)
RETURNS SETOF tile_coord
AS $$
DECLARE
geom1 geometry;
tc tile_coord;
xmin integer;
xmax integer;
ymin integer;
ymax integer;
BEGIN
-- convert to spherical mercator
geom1 := ST_Transform(geom, 3857);
xmin := tiles.GetTileIndex(ST_XMin(geom1), z);
xmax := tiles.GetTileIndex(ST_XMax(geom1), z);
ymin := tiles.GetTileIndex(-ST_YMin(geom1), z);
ymax := tiles.GetTileIndex(-ST_YMax(geom1), z);

RETURN QUERY
SELECT DISTINCT ON (x,y,z)
  x,y,z
FROM generate_series(xmin,xmax) x
CROSS JOIN generate_series(ymin,ymax) y;

END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION
tiles.LargestContainingTile(geom geometry)
RETURNS tile_coord
AS $$
DECLARE
geom1 geometry;
xmin double precision;
xmax double precision;
ymin double precision;
ymax double precision;
x1 integer;
x2 integer;
y1 integer;
y2 integer;
res tile_coord;
zoom integer;
BEGIN
geom1 := ST_Transform(geom, 3857);
xmin := ST_XMin(geom1);
xmax := ST_XMax(geom1);
ymin := -ST_YMin(geom1);
ymax := -ST_YMax(geom1);
zoom := 0;
res := ROW(0,0,0);

LOOP
  x1 := tiles.GetTileIndex(xmin, zoom);
  x2 := tiles.GetTileIndex(xmax, zoom);
  EXIT WHEN x1 != x2;
  y1 := tiles.GetTileIndex(ymin, zoom);
  y2 := tiles.GetTileIndex(ymax, zoom);
  EXIT WHEN y1 != y2;
  res := ROW(x1,y1,zoom);
  zoom := zoom+1;
END LOOP;
RETURN res;
END
$$
LANGUAGE plpgsql IMMUTABLE;
