/*
When `map_topology.contact` table is updated, changes should propagate
to `map_topology.map_face`
*/

/*
A table to hold dirty faces
*/
CREATE TABLE IF NOT EXISTS map_topology.__dirty_face (
  id integer REFERENCES map_topology.face ON DELETE CASCADE,
  topology text references map_topology.subtopology ON DELETE CASCADE,
  PRIMARY KEY(id, topology)
);

CREATE OR REPLACE FUNCTION map_topology.contact_geometry_changed()
RETURNS trigger AS $$
DECLARE
  CURRENT_TOPOGEOM topogeometry;
  CURRENT_TOPOLOGY text;
BEGIN

-- DISABLE THIS TRIGGER FOR NOW ---

-- set the feature depending on type of operation
IF (TG_OP = 'DELETE') THEN
  CURRENT_TOPOGEOM := OLD.geometry;
  CURRENT_TOPOLOGY := OLD.topology;
ELSE
  CURRENT_TOPOGEOM := NEW.geometry;
  CURRENT_TOPOLOGY := NEW.topology;
END IF;

INSERT INTO map_topology.__dirty_face (face_id, topology)
SELECT face_id, CURRENT_TOPOLOGY
FROM map_topology.edge_face ef
WHERE ef.edge_id IN (SELECT
  (topology.GetTopoGeomElements(CURRENT_TOPOGEOM))[1]);

RETURN NULL;
END;
$$ LANGUAGE plpgsql;

/*
WITH edges AS (
SELECT
  abs(
    (ST_GetFaceEdges('map_topology',
     (topology.GetTopoGeomElements(f.topo))[1])
    ).edge
  ) edge_id
FROM map_topology.map_face f
WHERE f.topology = CURRENT_TOPOLOGY
  AND ST_Intersects(f.geometry, CURRENT_TOPOGEOM)
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
  AND ST_Intersects(CURRENT_TOPOGEOM, f.geometry);

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
  ST_Multi(f.geometry)
FROM face f;
RAISE NOTICE 'Created new faces';

RETURN null;
*/

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


