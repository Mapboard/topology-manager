/* Boundary rows the next `update_contacts` run will node: not yet noded from their
   current geometry, in a topological layer, without a recorded failure (unless
   failed rows are included), and matching the caller's row filter. */
SELECT count(*)::integer nlines
FROM {boundary_table} l
WHERE l.geometry_hash IS NULL
  AND {topo_schema}.get_topological_map_layer(l) IS NOT NULL
  AND (l.topology_error IS NULL OR {include_failed})
  AND ({row_filter})
