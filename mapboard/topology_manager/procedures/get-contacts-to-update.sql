/* Ids of the boundary rows `update_contacts` will node, largest geometry first
   (same selection as count-contact.sql). */
SELECT l.id
FROM {boundary_table} l
WHERE l.geometry_hash IS NULL
  AND {topo_schema}.get_topological_map_layer(l) IS NOT NULL
  AND (l.topology_error IS NULL OR {include_failed})
  AND ({row_filter})
ORDER BY ST_MemSize(l.geometry) DESC, l.id
