UPDATE {boundary_table} l
SET topology_error = null
WHERE l.topology_error IS NOT null
  AND ({row_filter})
