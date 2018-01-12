DELETE FROM map_topology.relation
WHERE layer_id = map_topology.__linework_layer_id()
AND topogeo_id NOT IN (
  SELECT (topo).id
  FROM map_digitizer.linework
  WHERE topo IS NOT null
);

DELETE FROM map_topology.relation
WHERE layer_id = map_topology.__map_face_layer_id()
AND topogeo_id NOT IN (
  SELECT (topo).id
  FROM map_topology.map_face
  WHERE topo IS NOT null
);

