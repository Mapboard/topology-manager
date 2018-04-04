-- Map face
CREATE OR REPLACE VIEW mapping.map_face AS
SELECT
  f.id,
  f.unit_id,
  f.geometry,
  f.topology,
  t.color
FROM map_topology.map_face f
JOIN map_digitizer.polygon_type t
  ON f.unit_id = t.id
WHERE f.unit_id != 'surficial-none';



