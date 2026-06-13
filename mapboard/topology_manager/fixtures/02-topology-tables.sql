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
CREATE TABLE IF NOT EXISTS {topo_schema}.face_type (
  face_id   integer REFERENCES {topo_schema}.face (face_id) ON DELETE CASCADE,
  map_face  integer REFERENCES {topo_schema}.map_face (id) ON DELETE CASCADE,
  map_layer integer REFERENCES {data_schema}.map_layer (id) ON DELETE CASCADE,
  PRIMARY KEY (face_id, map_layer)
);
CREATE INDEX face_type_ix ON {topo_schema}.face_type (face_id);
CREATE INDEX map_face_gix ON {topo_schema}.map_face USING GIST (geometry);

/* A table to hold dirty faces */
CREATE TABLE IF NOT EXISTS {topo_schema}.dirty_face (
  id        integer REFERENCES {topo_schema}.face(face_id) ON DELETE CASCADE,
  map_layer integer REFERENCES {data_schema}.map_layer(id) ON DELETE CASCADE,
  PRIMARY KEY (id, map_layer)
);

/** Map face identifiers:
  links map_face to polygon_type identifier for geologic maps
  This could be changed if we wanted to use a different type of identification (e.g., for columns etc.)
*/
ALTER TABLE {topo_schema}.map_face ADD COLUMN unit_id text REFERENCES {data_schema}.polygon_type (id) ON DELETE CASCADE;
ALTER TABLE {topo_schema}.face_type ADD COLUMN unit_id text REFERENCES {data_schema}.polygon_type (id) ON DELETE CASCADE;




