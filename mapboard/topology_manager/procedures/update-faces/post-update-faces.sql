/* Register units for faces that don't have units */
SELECT {topo_schema}.register_face_identity(id) FROM {topo_schema}.map_face
WHERE topo IS NOT null
  AND id NOT IN (SELECT DISTINCT map_face FROM {topo_schema}.face_identity);

