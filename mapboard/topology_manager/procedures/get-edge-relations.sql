WITH a AS (
SELECT
  l.id line_id,
  l.map_layer,
  r.element_id edge_id
FROM {topo_schema}.edge_data e
JOIN {topo_schema}.relation r
  ON e.edge_id = r.element_id
 AND r.element_type = 2 -- edges
JOIN {data_schema}.linework l
  ON (l.topo).id = r.topogeo_id
  AND r.layer_id = (l.topo).layer_id
  AND l.topo IS NOT null
)
SELECT
  a.line_id,
  {topo_schema}.parent_map_layers(a.map_layer) map_layer,
  a.edge_id
FROM a;


