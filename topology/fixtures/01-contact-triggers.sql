/*
When `map_topology.contact` table is updated, changes should propagate
to `map_topology.map_face`
*/

/* on CREATE */

CREATE OR REPLACE FUNCTION map_topology.contact_geometry_changed()
RETURNS trigger AS $$
DECLARE
  working_topology text;
  edge_agg geometry;
BEGIN

-- Get the active topology
SELECT topology INTO working_topology
FROM map_digitizer.linework_type t
WHERE t.id = NEW.type;

-- Get the edges surrounding these faces
-- and the edges defining our geometry

WITH edges AS (
SELECT
  abs(
    (ST_GetFaceEdges('map_topology',
     (topology.GetTopoGeomElements(f.topo))[1])
    ).edge
  ) edge_id
FROM map_topology.map_face f
WHERE f.topology = working_topology
  AND ST_Touches(f.geometry, NEW.geometry)
UNION ALL
SELECT
  (topology.GetTopoGeomElements(NEW.geometry))[1] edge_id
)
SELECT
  ST_Union(d.geom) geometry
INTO edge_agg
FROM edges e
JOIN map_topology.edge_topology t
  ON e.edge_id = t.edge_id
 AND t.topology = working_topology
JOIN map_topology.edge_data d
  ON e.edge_id = d.edge_id;


-- Delete the old faces
DELETE
FROM map_topology.map_face f
WHERE topology = working_topology
  AND ST_Intersects(NEW.geometry, f.geometry)
  AND NOT ST_Within(NEW.geometry, f.geometry);

-- Polygonize the edges into faces
WITH face AS (
  SELECT (ST_Dump(ST_Polygonize(edge_agg))).geom geometry
)
INSERT INTO map_topology.map_face (unit_id,topo,topology, geometry)
SELECT
  map_topology.unitForArea(f.geometry, working_topology),
  map_topology.addMapFace(f.geometry, 1),
  working_topology,
  f.geometry
FROM face f
JOIN map_digitizer.polygon_type t
  ON type = t.id;

END;

$$ LANGUAGE plpgsql;


/* on UPDATE */

/* on DELETE

*/

-- Trigger to create a non-topogeometry representation for
-- storage on each row (for speed of lookup)
DROP TRIGGER IF EXISTS map_topology_contact_update_trigger ON map_topology.map_contact;
CREATE TRIGGER map_face_update_trigger
AFTER INSERT OR UPDATE OF geometry OR DELETE ON map_topology.map_face
FOR EACH ROW
EXECUTE PROCEDURE map_topology.map_face_was_updated();


