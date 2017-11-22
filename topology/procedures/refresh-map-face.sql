/*
Procedure to create map faces in bulk after deleting all of them.
*/
-- Every topology face is dirty
INSERT INTO map_topology.__dirty_face
SELECT face_id face, st.id topology
FROM map_topology.face
CROSS JOIN map_topology.subtopology st
ON CONFLICT DO NOTHING;

TRUNCATE TABLE map_topology.map_face;
SELECT pg_catalog.setval(
  pg_get_serial_sequence('map_topology.map_face', 'id'),
  MAX(id))
  FROM map_topology.map_face;

WITH face AS (
  SELECT
    topology,
    (ST_Dump(ST_Polygonize(e.geometry))).geom geometry
  FROM map_topology.topology_edges e
  GROUP BY e.topology
)
INSERT INTO map_topology.map_face (unit_id,topo,topology, geometry)
SELECT
  map_topology.unitForArea(f.geometry, f.topology),
  map_topology.addMapFace(f.geometry, 1),
  f.topology,
  f.geometry
FROM face f
JOIN map_digitizer.polygon_type t
  ON type = t.id;
