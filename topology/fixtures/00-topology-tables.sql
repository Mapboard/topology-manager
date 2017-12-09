CREATE TABLE IF NOT EXISTS map_topology.subtopology (
    id text PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS map_topology.contact (
    id SERIAL PRIMARY KEY,
    certainty integer,
    geometry geometry(MultiLineString, ${srid}),
    type text DEFAULT 'bedrock'::text,
    hash uuid,
    map_width numeric,
    hidden boolean,
    topology text REFERENCES map_topology.subtopology (id)
);

SELECT topology.AddTopoGeometryColumn('map_topology',
  'map_topology','contact', 'topo','LINE');

/* Table to hold invalid linework */

CREATE TABLE IF NOT EXISTS map_topology.__linework_failures (
  id integer REFERENCES map_topology.contact (id) ON DELETE CASCADE
);

/*
Map Face
*/
CREATE TABLE IF NOT EXISTS map_topology.map_face (
  id SERIAL PRIMARY KEY,
  unit_id text,
  topology text REFERENCES map_topology.subtopology (id),
  geometry geometry(MultiPolygon, ${srid})
);

SELECT topology.AddTopoGeometryColumn('map_topology',
  'map_topology', 'map_face', 'topo', 'MULTIPOLYGON');

CREATE INDEX map_face_gix ON map_topology.map_face USING GIST (geometry);

/*
A table to hold dirty faces
*/
CREATE TABLE IF NOT EXISTS map_topology.__dirty_face (
  id integer REFERENCES map_topology.face ON DELETE CASCADE,
  topology text references map_topology.subtopology ON DELETE CASCADE,
  PRIMARY KEY(id, topology)
);
