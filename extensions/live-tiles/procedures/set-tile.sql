INSERT INTO tiles.tile (z,x,y,tile,stale)
VALUES (${z},${x},${y},${tile},false)
ON CONFLICT (z,x,y)
DO UPDATE SET
  tile = EXCLUDED.tile,
  stale = false,
  created = now();
