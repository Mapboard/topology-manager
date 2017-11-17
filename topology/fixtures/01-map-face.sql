-- Map face
CREATE TABLE IF NOT EXISTS map_topology.map_face (
  id SERIAL PRIMARY KEY,
  unit_id text REFERENCES mapping.unit (id),
  topology text REFERENCES map_topology.sub_topology (id),
  geometry geometry(MultiPolygon, 32733)
);

SELECT topology.AddTopoGeometryColumn('map_topology',
  'map_topology', 'map_face', 'topo', 'MULTIPOLYGON');

CREATE OR REPLACE FUNCTION map_topology.map_face_was_updated()
RETURNS trigger AS $$
BEGIN
  UPDATE map_topology.map_face
  SET geometry = topo::geometry
  WHERE id = NEW.id;
END;
$$ LANGUAGE plpgsql;

-- Trigger to create a non-topogeometry representation for
-- storage on each row (for speed of lookup)
DROP TRIGGER IF EXISTS map_face_update_trigger ON map_topology.map_face;
--CREATE TRIGGER map_face_update_trigger
--AFTER INSERT OR UPDATE ON map_topology.map_face
--FOR EACH ROW
--EXECUTE PROCEDURE map_topology.map_face_was_updated();

