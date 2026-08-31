/* Map Face */
CREATE TABLE IF NOT EXISTS {topo_schema}.map_face (
  id        serial  PRIMARY KEY,
  map_layer integer REFERENCES {data_schema}.map_layer (id) ON DELETE CASCADE,
  geometry  geometry(MultiPolygon, {srid_literal}),
  -- Extensions for composite layer
  source_id integer REFERENCES {topo_schema}.map_face (id) ON DELETE CASCADE,
  source_layer integer REFERENCES {data_schema}.map_layer (id) ON DELETE CASCADE
);

SELECT topology.AddTopoGeometryColumn(:topo_name, :topo_name , 'map_face', 'topo', 'MULTIPOLYGON');

/** This table should have an identifier of the map face it corresponds to, as well as the layer it is in. */
CREATE TABLE IF NOT EXISTS {topo_schema}.face_identity (
  face_id   integer REFERENCES {topo_schema}.face (face_id) ON DELETE CASCADE,
  map_face  integer REFERENCES {topo_schema}.map_face (id) ON DELETE CASCADE,
  map_layer integer REFERENCES {data_schema}.map_layer (id) ON DELETE CASCADE,
  PRIMARY KEY (face_id, map_layer)
);
CREATE INDEX face_identity_ix ON {topo_schema}.face_identity (face_id);
/* PostgreSQL does not index the *referencing* side of a foreign key, so without
   these every `map_face` delete sequentially scans both tables to check its
   `ON DELETE CASCADE` children -- ~23ms per deleted row on a real topology,
   which dominates face replacement during an update. */
CREATE INDEX IF NOT EXISTS face_identity_map_face_idx
  ON {topo_schema}.face_identity (map_face);
CREATE INDEX IF NOT EXISTS map_face_source_id_idx
  ON {topo_schema}.map_face (source_id);
/* `map_id` is a foreign key too, and unindexed it forces a sequential scan of the
   whole face table whenever faces are looked up by the map that owns them. */
CREATE INDEX IF NOT EXISTS map_face_map_id_idx
  ON {topo_schema}.map_face ({face_identity_column});
CREATE INDEX map_face_gix ON {topo_schema}.map_face USING GIST (geometry);
/* Dissolving a component looks up the map_faces it replaces by joining `relation`
   on the topogeometry id. A composite field access cannot use an ordinary index,
   so without this every component sequentially scans `map_face`. Only `(topo).id`
   is indexed -- `check_topogeom_topo` pins the layer, so it adds nothing. */
CREATE INDEX IF NOT EXISTS map_face_topogeom_id_idx
  ON {topo_schema}.map_face (((topo).id));

/* A table to hold dirty faces */
CREATE TABLE IF NOT EXISTS {topo_schema}.dirty_face (
  id        integer REFERENCES {topo_schema}.face(face_id) ON DELETE CASCADE,
  map_layer integer REFERENCES {data_schema}.map_layer(id) ON DELETE CASCADE,
  PRIMARY KEY (id, map_layer)
);


