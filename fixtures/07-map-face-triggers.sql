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
SELECT DISTINCT ON (map_topology.other_face(e,fid))
  ARRAY[left_face,right_face] faces,
  map_topology.other_face(e,fid) adjacent,
  false
FROM map_topology.edge_data e
LEFT JOIN map_topology.__edge_relation er
  ON er.edge_id = e.edge_id
WHERE (e.left_face = fid OR e.right_face = fid)
  AND e.left_face != e.right_face
  AND er.topology IS DISTINCT FROM topoid
UNION
SELECT DISTINCT ON (map_topology.other_face(e,r1.adjacent))
  r1.faces || map_topology.other_face(e,r1.adjacent) faces,
  map_topology.other_face(e,r1.adjacent) adjacent,
  (map_topology.other_face(e,r1.adjacent) = ANY(r1.faces)) AS cycle
FROM map_topology.edge_data e
LEFT JOIN map_topology.__edge_relation er
  ON er.edge_id = e.edge_id
JOIN r r1
  ON (r1.adjacent = e.left_face OR r1.adjacent = e.right_face)
WHERE e.left_face != e.right_face
  AND NOT cycle
  AND NOT r1.adjacent = 0
  AND er.topology IS DISTINCT FROM topoid
), b AS (
SELECT DISTINCT unnest(faces) face FROM r WHERE NOT cycle
)
SELECT array_agg(face) faces FROM b;
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION map_topology.update_map_face()
RETURNS map_topology.__dirty_face AS $$
DECLARE
  __topo_elements integer[][];
  __topo topology.topogeometry;
  __geometry geometry;
  __face map_topology.__dirty_face;
  __precision integer;
  __dissolved_faces integer[];
  __is_global boolean;
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

RAISE NOTICE 'Face ID: %, topology: %', __face.id, __face.topology;

-- Special case when adjacent to global face
IF (__face.id = 0) THEN
  DELETE
  FROM map_topology.__dirty_face df
  WHERE topology = __face.topology
    AND id = 0;
  RETURN __face;
END IF;

/* First, get the adjoining faces */
__dissolved_faces := map_topology.adjacent_faces(__face.id,__face.topology);
RAISE NOTICE 'Dissolved faces: %', __dissolved_faces;

-- Special case when adjoining global face
IF (__dissolved_faces IS NULL) THEN
  __dissolved_faces := ARRAY[__face.id];
END IF;

__is_global := (0 = ANY(__dissolved_faces));
IF (__is_global) THEN
  RAISE NOTICE 'Face % is adjacent to the global face',__face.id;
END IF;

/* Global face does not work for geometry operations */
-- PostgreSQL 9.3 and above
__dissolved_faces := array_remove(__dissolved_faces,0);

-- /* Delete all topogeometries currently inhabiting the space */
-- DELETE FROM map_topology.map_face
-- WHERE id IN (
  -- SELECT DISTINCT
    -- (map_topology.containing_face(
        -- unnest(__dissolved_faces), __face.topology)).id
-- );

--- Escape before topogeometry creation if global
IF (__is_global) THEN
  DELETE
  FROM map_topology.__dirty_face df
  WHERE topology = __face.topology
    AND (
      id = ANY(__dissolved_faces) OR id = 0
    );
  RETURN __face;
END IF;

--- Create a new topogeometry covering the whole area
WITH a AS (
  SELECT ARRAY[unnest(__dissolved_faces),3] vals
)
SELECT array_agg(a.vals)
INTO __topo_elements
FROM a;

__topo := topology.CreateTopoGeom('map_topology', 3, __layer_id, __topo_elements);

__geometry := ST_SetSRID(__topo::geometry,__srid);

DELETE FROM map_topology.map_face mf
WHERE id IN (
  SELECT DISTINCT
    (map_topology.containing_face(
        unnest(__dissolved_faces),
        __face.topology)
    ).id
  );

DELETE
FROM map_topology.__dirty_face df
WHERE topology = __face.topology
  AND id = ANY(__dissolved_faces);

IF (__is_global) THEN
  DELETE
  FROM map_topology.__dirty_face df
  WHERE topology = __face.topology
    AND id = 0;
  RETURN __face;
END IF;

INSERT INTO map_topology.map_face
  (unit_id, topo, topology, geometry)
SELECT
map_topology.unitForArea(
  __geometry,
  __face.topology) unit_id,
__topo,
__face.topology,
__geometry;

DELETE
FROM map_topology.__dirty_face df
WHERE topology = __face.topology
  AND id = ANY(__dissolved_faces);

RETURN __face;

END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION map_topology.update_all_map_faces()
RETURNS void AS $$
BEGIN

-- Loop throug table of dirty linework
WHILE EXISTS (SELECT * FROM map_topology.__dirty_face)
LOOP
  PERFORM map_topology.update_map_face();
END LOOP;

END;
$$ LANGUAGE plpgsql;
