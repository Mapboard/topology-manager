-- Create an initial linework type (if nothing exists)
INSERT INTO {data_schema}.linework_type (id, name, color)
SELECT
  'default',
  'Default',
  '#000000'
FROM topology.topology -- dummy table
WHERE NOT EXISTS (SELECT * FROM {data_schema}.linework_type)
ON CONFLICT DO NOTHING;

-- Same for polygon-types
INSERT INTO {data_schema}.polygon_type (id, name, color)
SELECT
  'default',
  'Default',
  '#000000'
FROM topology.topology -- dummy table
WHERE NOT EXISTS (SELECT * FROM {data_schema}.polygon_type)
ON CONFLICT DO NOTHING;

INSERT INTO {data_schema}.map_layer (id, name, topological)
VALUES (0, 'Default', true)
ON CONFLICT DO NOTHING;

/* Add topology columns to table
TODO: we should consider migrating this to a separate table within the topology schema.
*/
SELECT topology.AddTopoGeometryColumn(:topo_name, :data_schema_name,'linework', 'topo','LINE');
ALTER TABLE {data_schema}.linework
  ADD COLUMN geometry_hash uuid,
  ADD COLUMN topology_error text;

/* Map Face */
CREATE TABLE IF NOT EXISTS {topo_schema}.map_face (
  id        serial  PRIMARY KEY,
  -- TODO: rename unit_id to type
  unit_id   text    REFERENCES {data_schema}.polygon_type (id) ON DELETE CASCADE,
  map_layer integer REFERENCES {data_schema}.map_layer (id) ON DELETE CASCADE,
  geometry  geometry(MultiPolygon, :srid)
);

CREATE TABLE IF NOT EXISTS {topo_schema}.face_type (
  face_id   integer REFERENCES {topo_schema}.face (face_id) ON DELETE CASCADE,
  map_face  integer REFERENCES {topo_schema}.map_face (id) ON DELETE CASCADE,
  map_layer integer REFERENCES {data_schema}.map_layer (id) ON DELETE CASCADE,
  unit_id   text    REFERENCES {data_schema}.polygon_type (id) ON DELETE CASCADE,
  PRIMARY KEY (face_id, map_layer)
);
CREATE INDEX face_type_ix ON {topo_schema}.face_type (face_id);

SELECT topology.AddTopoGeometryColumn(:topo_name, :topo_name , 'map_face', 'topo', 'MULTIPOLYGON');

CREATE INDEX map_face_gix ON {topo_schema}.map_face USING GIST (geometry);

/* A table to hold dirty faces */
CREATE TABLE IF NOT EXISTS {topo_schema}.__dirty_face (
  id        integer REFERENCES {topo_schema}.face(face_id) ON DELETE CASCADE,
  map_layer integer REFERENCES {data_schema}.map_layer(id) ON DELETE CASCADE,
  PRIMARY KEY (id, map_layer)
);

/** EDGE INFRASTRUCTURE
This table exists to hold all the edges that are relevant to a particular map
layer.
*/
CREATE TABLE IF NOT EXISTS {topo_schema}.__edge_relation (
  edge_id   integer NOT NULL REFERENCES {topo_schema}.edge_data ON DELETE CASCADE,
  map_layer integer NOT NULL REFERENCES {data_schema}.map_layer ON DELETE CASCADE,
  line_id   integer NOT NULL REFERENCES {data_schema}.linework ON DELETE CASCADE,
  PRIMARY KEY (edge_id, map_layer)
);

