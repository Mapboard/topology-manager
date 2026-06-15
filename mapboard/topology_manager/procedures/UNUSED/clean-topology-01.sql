DELETE FROM {topo_schema}.relation
WHERE layer_id = {topo_schema}.boundary_layer_id()
AND topogeo_id NOT IN (
  SELECT (topo).id
  FROM {boundary_table}
  WHERE topo IS NOT null
);

DELETE FROM {topo_schema}.relation
WHERE layer_id = {topo_schema}.boundary_layer_id()
AND topogeo_id NOT IN (
  SELECT (topo).id
  FROM {topo_schema}.map_face
  WHERE topo IS NOT null
);

