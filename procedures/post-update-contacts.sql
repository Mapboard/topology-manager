/*
Update the data associated with each edge on
what contact it is associated with. This could
probably be integrated into a trigger system
in the future, to guarantee referential integrity.
*/

UPDATE map_topology.edge_data ed
SET
  line_id = l.id,
  topology = lt.topology
FROM
  map_topology.relation r,
  map_digitizer.linework l,
  map_digitizer.linework_type lt
WHERE element_id = edge_id
 AND element_type = 2
 AND layer_id = map_topology.__linework_layer_id()
 AND r.topogeo_id = (l.topo).id
 AND lt.id = l.type
 AND (
  line_id IS null
  OR ed.topology IS null
  OR ed.topology != lt.topology);

UPDATE map_topology.edge_data e
SET
  line_id = null,
  topology = null
FROM map_digitizer.linework l
WHERE e.line_id = l.id
  AND l.topo IS NULL;
