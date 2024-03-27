/*
Update the data associated with each edge on
what contact it is associated with.

The trigger *should* keep integrity but we can just be safe
*/

INSERT INTO {topo_schema}.__edge_relation (edge_id, layer, line_id, type)
WITH line_data AS (
  SELECT
    l.id,
    l.topo,
    {topo_schema}.line_topology(l) layer,
    l.type
  FROM {data_schema}.linework l
  JOIN {data_schema}.linework_type t
    ON l.type = t.id
  WHERE l.topo IS NOT null
)
SELECT
  (topology.GetTopoGeomElements(topo))[1] edge_id,
  l.layer,
  l.id,
  l.type
FROM line_data l
WHERE layer IS NOT null
ON CONFLICT (edge_id, layer) DO NOTHING;
