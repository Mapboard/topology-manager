/*
Update the data associated with each edge on
what contact it is associated with.

The trigger *should* keep integrity but we can just be safe
*/
WITH line_data AS (
  SELECT
    l.id,
    l.topo,
    {topo_schema}.child_map_layers(l.map_layer) map_layer,
    l.map_layer root_map_layer,
    l.type
  FROM {data_schema}.linework l
  JOIN {data_schema}.linework_type t
    ON l.type = t.id
  WHERE l.topo IS NOT null
    AND l.map_layer IS NOT null
)
INSERT INTO {topo_schema}.__edge_relation (edge_id, map_layer, is_child, line_id)
SELECT
  (topology.GetTopoGeomElements(topo))[1] edge_id,
  l.map_layer,
  l.map_layer != l.root_map_layer,
  l.id
FROM line_data l
WHERE map_layer IS NOT null
ON CONFLICT (edge_id, map_layer) DO NOTHING;
