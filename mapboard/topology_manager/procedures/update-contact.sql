/* Node the whole geometry of each listed boundary row, at the given tolerance
   (NULL: the topology's precision). `err` is the failure text, NULL on success. */
SELECT
  l.id,
  {topo_schema}.update_boundary_topo(l, :noding_tolerance::numeric) err
FROM {boundary_table} l
WHERE l.id = ANY(:ids)
ORDER BY ST_MemSize(l.geometry) DESC, l.id
