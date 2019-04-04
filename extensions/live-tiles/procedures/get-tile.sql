SELECT tile
FROM tiles.tile
WHERE z = ${z}
  AND x = ${x}
  AND y = ${y}
  AND NOT stale
