-- Map face
CREATE TABLE IF NOT EXISTS map_topology.map_face (
  id SERIAL PRIMARY KEY,
  unit_id text REFERENCES mapping.unit (id),
  topology text REFERENCES map_topology.sub_topology (id),
  geometry geometry(MultiPolygon, 32733)
);

SELECT topology.AddTopoGeometryColumn('map_topology',
  'map_topology', 'map_face', 'topo', 'MULTIPOLYGON');

