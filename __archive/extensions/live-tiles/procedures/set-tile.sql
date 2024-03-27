INSERT INTO tiles.tile (z,x,y,tile,layer_id, stale)
VALUES (${z},${x},${y},${tile},${layer_id},false)
ON CONFLICT (z,x,y,layer_id)
DO UPDATE SET
  tile = EXCLUDED.tile,
  layer_id = ${layer_id},
  stale = false,
  created = now();
