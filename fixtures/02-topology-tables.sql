CREATE TABLE IF NOT EXISTS ${topo_schema~}.subtopology (
  id text PRIMARY KEY
);

INSERT INTO ${topo_schema~}.subtopology (id)
VALUES ('default')
ON CONFLICT DO NOTHING;

-- Create an initial linework type
INSERT INTO ${data_schema~}.linework_type (
  id, name,color,topology)
VALUES (
  'default',
  'Default',
  '#000000',
  'default'
);

-- Insert initial values into subtopology column
INSERT INTO ${topo_schema~}.subtopology (id)
SELECT DISTINCT ON (topology)
  topology
FROM ${data_schema~}.linework_type
WHERE topology IS NOT NULL
ON CONFLICT DO NOTHING;

-- Refer to this on our linework tables
ALTER TABLE ${data_schema~}.linework_type
ADD CONSTRAINT ${topo_schema^}_linework_topology
FOREIGN KEY (topology)
  REFERENCES ${topo_schema~}.subtopology(id) ON UPDATE CASCADE;

/* Add topology columns to table */
SELECT topology.AddTopoGeometryColumn(${topo_schema},
  ${data_schema},'linework', 'topo','LINE');
ALTER TABLE ${data_schema~}.linework
  ADD COLUMN geometry_hash uuid,
  ADD COLUMN topology_error text;

/* Map Face */
CREATE TABLE IF NOT EXISTS ${topo_schema~}.map_face (
  id SERIAL PRIMARY KEY,
  unit_id text,
  topology text REFERENCES ${topo_schema~}.subtopology (id),
  geometry geometry(MultiPolygon, ${srid})
);

CREATE TABLE IF NOT EXISTS ${topo_schema~}.face_type (
  face_id integer REFERENCES ${topo_schema~}.face (face_id) ON DELETE CASCADE,
  map_face integer REFERENCES ${topo_schema~}.map_face (id) ON DELETE CASCADE,
  topology text REFERENCES ${topo_schema~}.subtopology (id) ON UPDATE CASCADE,
  unit_id text,
  PRIMARY KEY (face_id, topology)
);
CREATE INDEX face_type_ix ON ${topo_schema~}.face_type (face_id);

SELECT topology.AddTopoGeometryColumn(${topo_schema},
  ${topo_schema}, 'map_face', 'topo', 'MULTIPOLYGON');

CREATE INDEX map_face_gix ON ${topo_schema~}.map_face USING GIST (geometry);

/*
A table to hold dirty faces
*/
CREATE TABLE IF NOT EXISTS ${topo_schema~}.__dirty_face (
  id integer REFERENCES ${topo_schema~}.face ON DELETE CASCADE,
  topology text references ${topo_schema~}.subtopology ON DELETE CASCADE,
  PRIMARY KEY(id, topology)
);
