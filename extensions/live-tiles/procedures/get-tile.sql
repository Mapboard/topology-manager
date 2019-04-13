SELECT tile
FROM tiles.tile
WHERE z = ${z}
  AND x = ${x}
  AND y = ${y}
  AND layer_id = ${layer_id}
  AND NOT stale
