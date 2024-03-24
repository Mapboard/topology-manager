/*
Update the data associated with each edge on
what contact it is associated with.

The trigger *should* keep integrity but we can just be safe
*/

INSERT INTO {topo_schema}.__edge_relation (edge_id, topology, line_id, type)
SELECT
  (topology.GetTopoGeomElements(topo))[1] edge_id,
  t.topology,
  l.id,
  l.type
FROM {data_schema}.linework l
JOIN {data_schema}.linework_type t
  ON l.type = t.id
WHERE topo IS NOT null
  AND t.topology IS NOT null
ON CONFLICT (edge_id, topology) DO NOTHING;
