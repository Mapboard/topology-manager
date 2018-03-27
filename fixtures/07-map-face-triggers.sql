/*
Potential alternate algorithm:

1. get overlapping map faces
2. split on new geometry
3. if original geometry is the same, leave alone
    (for partial overlaps)
4. else, 
5. check if any edges do not have a face associated
  build them up the previous way.


*/

/*
A materialized view to store relationships between faces,
which saves ~0.5s per query. This is updated by default
but this can be disabled for speed.

Drastically simplified this view creation
*/
DROP MATERIALIZED VIEW IF EXISTS map_topology.__face_relation;
CREATE MATERIALIZED VIEW map_topology.__face_relation AS
SELECT
  f1.edge_id,
  f1.face_id f1,
  f2.face_id f2,
  e.topology
FROM map_topology.edge_face f1
JOIN map_topology.edge_face f2
  ON f1.edge_id = f2.edge_id
 AND f1.face_id != f2.face_id
LEFT JOIN map_topology.edge_data e
  ON f1.edge_id = e.edge_id;
-- Indexes to speed things up
CREATE INDEX map_topology__face_relation_face_index
  ON map_topology.__face_relation (f1);

CREATE OR REPLACE FUNCTION map_topology.__map_face_layer_id()
RETURNS integer AS $$
SELECT layer_id
FROM topology.layer
WHERE schema_name='map_topology'
  AND table_name='map_face'
  AND feature_column='topo';
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION map_topology.update_map_face(
  refresh boolean DEFAULT true)
RETURNS map_topology.__dirty_face AS $$
DECLARE
  __face map_topology.__dirty_face;
  __dissolved_faces integer[];
  __deleted_face integer;
  __layer_id integer;
  __n_updated integer;
  __srid integer;
BEGIN

SELECT * INTO __face FROM map_topology.__dirty_face LIMIT 1;

SELECT srid
INTO __srid
FROM topology.topology
WHERE name='map_topology';

__layer_id := map_topology.__map_face_layer_id();

IF refresh THEN
  EXECUTE 'REFRESH MATERIALIZED VIEW map_topology.__face_relation';
END IF;

WITH RECURSIVE joinable_face AS (
SELECT DISTINCT ON (topology, f1, f2)
  f1, f2, topology
FROM map_topology.__face_relation
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

RAISE NOTICE 'Faces: %', __dissolved_faces;

WITH a AS (
  SELECT ARRAY[unnest((
      SELECT array_agg(e)
      FROM (SELECT * FROM unnest(__dissolved_faces) id
      WHERE id != 0) AS d(e)
    )),3]::topology.topoelement vals
),
b AS (
SELECT CreateTopoGeom('map_topology', 3, __layer_id,
  TopoElementArray_Agg(a.vals)) topo
FROM a
),
g AS (
SELECT
  topo,
  ST_SetSRID(topo::geometry,__srid) geometry,
  __face.topology
FROM b
)
--- Delete overlapping topogeometries and insert all of their
--- constituent faces into the dirty linework channel (if not
--- already there)
DELETE FROM map_topology.map_face mf
USING g
-- Intersection might be too wide a parameter
WHERE (ST_Intersects(mf.geometry, ST_Buffer(g.geometry,-1))
  AND NOT ST_Touches(mf.geometry, ST_Buffer(g.geometry,-1)))
  AND mf.topology = __face.topology;

--- Update the geometry
IF NOT (0 = ANY(__dissolved_faces)) THEN
  -- Handle cases where we're linked with the global face
  -- Delete all faces that touch these faces

--- Insert new topogeometry and recover ID
WITH a AS (
  SELECT ARRAY[unnest(__dissolved_faces),3]::topology.topoelement vals
),
b AS (
SELECT CreateTopoGeom('map_topology', 3, __layer_id,
  TopoElementArray_Agg(a.vals)) topo
FROM a
),
g AS (
SELECT
  topo,
  ST_SetSRID(topo::geometry,__srid) geometry,
  __face.topology
FROM b
)
INSERT INTO map_topology.map_face
  (unit_id, topo, topology, geometry)
SELECT
map_topology.unitForArea(g.geometry, g.topology) unit_id,
g.topo,
g.topology,
g.geometry
FROM g;

END IF;

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

RETURN __face;

END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION map_topology.update_all_map_faces()
RETURNS void AS $$
BEGIN

EXECUTE 'REFRESH MATERIALIZED VIEW map_topology.__face_relation';
-- Loop throug table of dirty linework
WHILE EXISTS (SELECT * FROM map_topology.__dirty_face)
LOOP
  PERFORM map_topology.update_map_face(false);
END LOOP;

END;
$$ LANGUAGE plpgsql;


