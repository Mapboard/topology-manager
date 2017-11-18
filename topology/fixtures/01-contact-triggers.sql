/*
When `map_topology.contact` table is updated, changes should propagate
to `map_topology.map_face`
*/

/* on CREATE */

CREATE OR REPLACE FUNCTION map_topology.contact_geometry_changed()
RETURNS trigger AS $$
DECLARE
  CURRENT_TOPOGEOM topogeometry;
  CURRENT_TOPOLOGY text;
  GEOM_TYPE text;
  EDGE_AGG geometry;
BEGIN

-- set the feature depending on type of operation
IF (TG_OP = 'DELETE') THEN
  CURRENT_TOPOGEOM := OLD.geometry;
  GEOM_TYPE := OLD.type;
ELSE
  CURRENT_TOPOGEOM := NEW.geometry;
  GEOM_TYPE := NEW.type;
END IF;

-- Get the active topology
SELECT topology INTO CURRENT_TOPOLOGY
FROM map_digitizer.linework_type t
WHERE t.id = GEOM_TYPE;

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
WHERE f.topology = CURRENT_TOPOLOGY
  AND ST_Touches(f.geometry, CURRENT_TOPOGEOM)
UNION ALL
SELECT
  (topology.GetTopoGeomElements(CURRENT_TOPOGEOM))[1] edge_id
)
SELECT
  ST_Union(d.geom) geometry
INTO EDGE_AGG
FROM edges e
JOIN map_topology.edge_topology t
  ON e.edge_id = t.edge_id
 AND t.topology = CURRENT_TOPOLOGY
JOIN map_topology.edge_data d
  ON e.edge_id = d.edge_id;


-- Delete the old faces
DELETE
FROM map_topology.map_face f
WHERE topology = CURRENT_TOPOLOGY
  AND ST_Intersects(CURRENT_TOPOGEOM, f.geometry)
  AND NOT ST_Within(CURRENT_TOPOGEOM, f.geometry);

-- Polygonize the new edges into faces
WITH face AS (
  SELECT (ST_Dump(ST_Polygonize(EDGE_AGG))).geom geometry
)
INSERT INTO map_topology.map_face
  (unit_id,topo,topology, geometry)
SELECT
  map_topology.unitForArea(f.geometry, CURRENT_TOPOLOGY),
  map_topology.addMapFace(f.geometry, 1),
  CURRENT_TOPOLOGY,
  f.geometry
FROM face f
JOIN map_digitizer.polygon_type t
  ON GEOM_TYPE = t.id;

RETURN null;

END;

$$ LANGUAGE plpgsql;


/* on UPDATE */

/* on DELETE

*/

-- Trigger to create a non-topogeometry representation for
-- storage on each row (for speed of lookup)
DROP TRIGGER IF EXISTS map_topology_contact_update_trigger ON map_topology.contact;
CREATE TRIGGER map_topology_contact_update_trigger
AFTER INSERT OR UPDATE OR DELETE ON map_topology.contact
FOR EACH ROW
EXECUTE PROCEDURE map_topology.contact_geometry_changed();


