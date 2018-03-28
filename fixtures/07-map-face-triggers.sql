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

CREATE OR REPLACE FUNCTION map_topology.__map_face_layer_id()
RETURNS integer AS $$
SELECT layer_id
FROM topology.layer
WHERE schema_name='map_topology'
  AND table_name='map_face'
  AND feature_column='topo';
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION map_topology.other_face(
  e map_topology.edge_data,
  fid integer
)
RETURNS integer
AS $$
SELECT CASE
  WHEN e.left_face = fid THEN e.right_face
  WHEN e.right_face = fid THEN e.left_face
  ELSE null
END
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION map_topology.adjacent_faces(
  fid integer,
  topoid text
)
RETURNS integer[]
AS $$
WITH RECURSIVE r(faces,adjacent,cycle) AS (
SELECT
  ARRAY[left_face,right_face] faces,
  map_topology.other_face(e,fid) adjacent,
  false
FROM map_topology.edge_data e
  WHERE (left_face = fid OR right_face = fid)
    AND coalesce(topology,'none') != topoid
UNION
SELECT DISTINCT ON (map_topology.other_face(e,r1.adjacent))
  r1.faces || map_topology.other_face(e,r1.adjacent) faces,
  map_topology.other_face(e,r1.adjacent) adjacent,
  (map_topology.other_face(e,r1.adjacent) = ANY(r1.faces)) AS cycle
FROM map_topology.edge_data e, r r1
WHERE (r1.adjacent = e.left_face OR r1.adjacent = e.right_face)
  AND coalesce(topology,'none') != topoid
  AND NOT cycle
  AND NOT r1.adjacent = 0
), b AS (
SELECT DISTINCT unnest(faces) face FROM r WHERE NOT cycle
)
SELECT array_agg(face) faces FROM b;
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION map_topology.update_map_face()
RETURNS map_topology.__dirty_face AS $$
DECLARE
  __face map_topology.__dirty_face;
  __precision integer;
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

SELECT precision
INTO __precision
FROM topology.topology
WHERE name = 'map_topology';

__layer_id := map_topology.__map_face_layer_id();

__dissolved_faces := map_topology.adjacent_faces(__face.id,__face.topology);

IF (0 = ANY(__dissolved_faces)) THEN
  RAISE NOTICE 'Face % is adjacent to the global face on topology "%"',
    __face.id,__face.topology;

  -- We assume that none of the other faces have map_faces
  -- If this is incorrect, we can change the assumption
  -- to do this for all the __dissolved_faces
  WITH face AS (
    SELECT (map_topology.containing_face(__face.id,__face.topology)).*
  ), d AS (
    DELETE FROM map_topology.map_face
    USING face
    WHERE face_id = face.id
  )
  DELETE FROM map_topology.__dirty_face
  USING face
  WHERE topology = __face.topology
    AND id IN (SELECT (topology.GetTopoGeomElements(face.topo))[1]);

  RETURN __face;
END IF;

RAISE NOTICE 'Dissolved faces: %', __dissolved_faces;

-- First, delete the faces we are going to fix
-- from the dirty faces list
DELETE
FROM map_topology.__dirty_face df
WHERE topology = __face.topology
  AND id = ANY(__dissolved_faces);

--- Update the geometry
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
),
d AS (
  --- already there)
  DELETE FROM map_topology.map_face mf
  USING g
  -- Intersection might be too wide a parameter
  WHERE (ST_Intersects(mf.geometry, ST_Buffer(g.geometry,__precision))
    AND NOT ST_Touches(mf.geometry, ST_Buffer(g.geometry,__precision)))
    AND mf.topology = __face.topology
)
INSERT INTO map_topology.map_face
  (unit_id, topo, topology, geometry)
SELECT
map_topology.unitForArea(g.geometry, g.topology) unit_id,
g.topo,
g.topology,
g.geometry
FROM g;

RETURN __face;

END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION map_topology.update_all_map_faces()
RETURNS void AS $$
BEGIN

-- Loop throug table of dirty linework
WHILE EXISTS (SELECT * FROM map_topology.__dirty_face)
LOOP
  PERFORM map_topology.update_map_face(false);
END LOOP;

END;
$$ LANGUAGE plpgsql;


