CREATE TABLE IF NOT EXISTS ${topo_schema~}.subtopology (
    id text PRIMARY KEY
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
