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

INSERT INTO map_topology.__dirty_face (id, topology)
SELECT face_id, CURRENT_TOPOLOGY
FROM map_topology.edge_face ef
WHERE ef.edge_id IN (SELECT
  (topology.GetTopoGeomElements(CURRENT_TOPOGEOM))[1]);
RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION map_topology.update_map_face()
RETURNS void AS $$
DECLARE
  __face map_topology.__dirty_face;
  __dissolved_faces integer[];
  __n_updated integer;
  __new_geometry geometry;
BEGIN

CREATE TEMPORARY TABLE face_relation ON COMMIT DROP AS
WITH ec AS (
SELECT
c.id contact_id,
c.topology,
(topology.GetTopoGeomElements(c.geometry))[1] edge_id
FROM map_topology.contact c
)
SELECT
  f1.edge_id,
  f1.face_id f1,
  f2.face_id f2,
  ec.topology
FROM map_topology.edge_face f1
JOIN map_topology.edge_face f2
  ON f1.edge_id = f2.edge_id
 AND f1.face_id != f2.face_id
LEFT JOIN ec
  ON ec.edge_id = f1.edge_id;

-- Loop throug table of dirty linework
WHILE EXISTS (SELECT * FROM map_topology.__dirty_face)
LOOP

SELECT * INTO __face FROM map_topology.__dirty_face LIMIT 1;

RAISE NOTICE '%', __face.id;

WITH RECURSIVE joinable_face AS (
SELECT DISTINCT ON (topology, f1, f2)
  f1, f2, topology
FROM face_relation
WHERE coalesce(topology,'none') != __face.topology
),
r(faces,adjacent,cycle) AS (
SELECT
  ARRAY[f.f1, f.f2] faces,
  f.f2 adjacent,
  false
FROM joinable_face f
WHERE f1 = __face.id
UNION
SELECT DISTINCT ON (f2)
  r1.faces || j.f2 faces,
  j.f2 adjacent,
  (j.f2 = ANY(r1.faces)) AS cycle
FROM joinable_face j, r r1
WHERE r1.adjacent = j.f1
  AND NOT cycle
),
faces AS (
SELECT DISTINCT unnest(faces) face FROM r
)
SELECT coalesce(array_agg(face),ARRAY[__face.id])
INTO __dissolved_faces
FROM faces;

RAISE NOTICE '% for %', __dissolved_faces, __face.topology;

--- Update the geometry

--- Create geometry
SELECT ST_Union(
  ST_GetFaceGeometry('map_topology',face_id)) geom
FROM map_topology.face
INTO __new_geometry
WHERE face_id = ANY(__dissolved_faces);
--- Get overlapping topogeometries


--- Delete overlapping topogeometries and insert all of their
--- constituent faces into the dirty linework channel (if not
--- already there)
WITH del AS (
DELETE FROM map_topology.map_face mf
WHERE ST_Overlaps(__new_geometry, mf.topo)
RETURNING topology.GetTopoGeomElements(mf.topo))[1] face)
INSERT INTO map_topology.__dirty_face (id, topology)
SELECT
  face,
  __face.topology
FROM del
ON CONFLICT DO NOTHING;

--- Insert new topogeometry
INSERT INTO map_topology.map_face
  (unit_id,topo,topology, geometry)
SELECT
  map_topology.unitForArea(__new_geometry, __face.topology),
  map_topology.addMapFace(__new_geometry, 1),
  __face_topology,
  ST_Multi(__new_geometry)
FROM face f;

-- Delete from dirty faces where we just created a face
WITH a AS (
DELETE
FROM map_topology.__dirty_face df
WHERE topology = __face.topology
  AND id = ANY(__dissolved_faces)
RETURNING id
)
SELECT count(id)
INTO __n_updated FROM a;

RAISE NOTICE 'FIXED % FACES', __n_updated;

END LOOP;

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


