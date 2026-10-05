/* Map faces emptied by `release_boundary` served stale geometry while the update
   rebuilt their area; once their layer has nothing left to rebuild, they go. */
DELETE FROM {topo_schema}.map_face mf
WHERE mf.topo IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM {topo_schema}.dirty_face d WHERE d.map_layer = mf.map_layer
  )
  AND NOT EXISTS (
    SELECT 1 FROM {topo_schema}.relation r
    WHERE r.topogeo_id = (mf.topo).id AND r.layer_id = (mf.topo).layer_id
  );

/* Register units for faces that don't have units */
SELECT {topo_schema}.register_face_identity(id) FROM {topo_schema}.map_face
WHERE topo IS NOT null
  AND id NOT IN (SELECT DISTINCT map_face FROM {topo_schema}.face_identity);

