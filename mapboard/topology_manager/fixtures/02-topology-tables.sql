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
VALUES
  ('default', 'Default', true);

/* Add topology columns to table
TODO: we should consider migrating this to a separate table within the topology schema.
*/
SELECT topology.AddTopoGeometryColumn(:topo_name, :data_schema_name,'linework', 'topo','LINE');
ALTER TABLE {data_schema}.linework
  ADD COLUMN geometry_hash uuid,
  ADD COLUMN topology_error text;

/* Map Face */
CREATE TABLE IF NOT EXISTS {topo_schema}.map_face (
  id SERIAL PRIMARY KEY,
  unit_id text,
  topology text REFERENCES {data_schema}.map_layer (id),
  geometry geometry(MultiPolygon, :srid)
);

CREATE TABLE IF NOT EXISTS {topo_schema}.face_type (
  face_id integer REFERENCES {topo_schema}.face (face_id) ON DELETE CASCADE,
  map_face integer REFERENCES {topo_schema}.map_face (id) ON DELETE CASCADE,
  topology text REFERENCES {data_schema}.map_layer (id) ON UPDATE CASCADE,
  unit_id text,
  PRIMARY KEY (face_id, topology)
);
CREATE INDEX face_type_ix ON {topo_schema}.face_type (face_id);

SELECT topology.AddTopoGeometryColumn(:topo_name, :topo_name , 'map_face', 'topo', 'MULTIPOLYGON');

CREATE INDEX map_face_gix ON {topo_schema}.map_face USING GIST (geometry);

/* A table to hold dirty faces */
CREATE TABLE IF NOT EXISTS {topo_schema}.__dirty_face (
  id integer REFERENCES {topo_schema}.face ON DELETE CASCADE,
  topology text references {data_schema}.map_layer ON DELETE CASCADE,
  PRIMARY KEY(id, topology)
);

/* EDGE INFRASTRUCTURE */

CREATE TABLE IF NOT EXISTS {topo_schema}.__edge_relation (
  edge_id integer REFERENCES {topo_schema}.edge_data ON DELETE CASCADE,
  topology text REFERENCES {data_schema}.map_layer ON DELETE CASCADE,
  line_id integer REFERENCES {data_schema}.linework ON DELETE CASCADE,
  "type" text
      REFERENCES {data_schema}.linework_type
      ON UPDATE CASCADE
      ON DELETE SET NULL,
  PRIMARY KEY(edge_id, topology)
);

