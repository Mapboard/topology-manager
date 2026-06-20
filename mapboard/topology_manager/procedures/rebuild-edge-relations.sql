/** Rebuild the cached __edge_relation table from its authoritative definition.

Used to repair the cache when the maintaining triggers have fallen out of sync.
This mirrors the initial population in fixtures/04-edge-relations-table.sql and
reuses the __topogeom_edges helper, so edge- and face-based boundaries are both
handled. A full delete + repopulate also corrects non-key drift (e.g. a stale
map_layer on an otherwise-present row).
*/
DELETE FROM {topo_schema}.__edge_relation;

INSERT INTO {topo_schema}.__edge_relation (
  line_id,
  map_layer,
  edge_id,
  topogeo_id,
  topolayer_id
)
SELECT
  l.id line_id,
  l.map_layer,
  e.edge_id,
  (l.topo).id topogeo_id,
  (l.topo).layer_id topolayer_id
FROM {boundary_table} l
JOIN {data_schema}.map_layer ml
  ON l.map_layer = ml.id
CROSS JOIN LATERAL {topo_schema}.__topogeom_edges((l.topo).id, (l.topo).layer_id) e
WHERE l.topo IS NOT null
  AND ml.topological
ON CONFLICT DO NOTHING;
