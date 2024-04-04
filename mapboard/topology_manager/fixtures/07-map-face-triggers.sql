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

CREATE OR REPLACE FUNCTION {topo_schema}.opposite_face(
  edge {topo_schema}.edge_data,
  face_id integer
)
RETURNS integer
AS $$
SELECT CASE
  WHEN edge.left_face = face_id THEN edge.right_face
  WHEN edge.right_face = face_id THEN edge.left_face
  ELSE null
END
$$ LANGUAGE SQL IMMUTABLE;

/** Get faces that can be dissolved into a given map layer */
CREATE OR REPLACE FUNCTION {topo_schema}.adjacent_faces(
  face_id integer,
  _map_layer integer
)
RETURNS integer[]
AS $$
WITH RECURSIVE r(faces, adjacent, cycle) AS (
SELECT DISTINCT ON ({topo_schema}.opposite_face(edge, face_id))
  ARRAY[left_face, right_face] faces,
  {topo_schema}.opposite_face(edge, face_id) adjacent,
  false
FROM {topo_schema}.edge_data edge
LEFT JOIN {topo_schema}.__edge_relation er
  ON er.edge_id = edge.edge_id
 AND NOT er.is_child
WHERE (edge.left_face = face_id OR edge.right_face = face_id)
  AND edge.left_face != edge.right_face
  AND er.map_layer IS DISTINCT FROM _map_layer
UNION
SELECT DISTINCT ON ({topo_schema}.opposite_face(edge, r1.adjacent))
  r1.faces || {topo_schema}.opposite_face(edge, r1.adjacent) faces,
  {topo_schema}.opposite_face(edge, r1.adjacent) adjacent,
  ({topo_schema}.opposite_face(edge, r1.adjacent) = ANY(r1.faces)) AS cycle
FROM {topo_schema}.edge_data edge
LEFT JOIN {topo_schema}.__edge_relation er
  ON er.edge_id = edge.edge_id
 AND NOT er.is_child
JOIN r r1
  ON (r1.adjacent = edge.left_face OR r1.adjacent = edge.right_face)
WHERE edge.left_face != edge.right_face
  AND NOT cycle
  AND NOT r1.adjacent = 0
  AND er.map_layer IS DISTINCT FROM _map_layer
), b AS (
SELECT DISTINCT unnest(faces) face FROM r WHERE NOT cycle
)
SELECT array_agg(face) faces FROM b;
$$ LANGUAGE SQL IMMUTABLE;

/** This function controls the creation of map faces for
all map layers when an edge is updated.
*/
CREATE OR REPLACE FUNCTION {topo_schema}.update_map_face()
RETURNS {topo_schema}.__dirty_face AS $$
DECLARE
  __topo_elements integer[][];
  __topo topology.topogeometry;
  __geometry geometry;
  __face {topo_schema}.__dirty_face;
  __precision integer;
  __dissolved_faces integer[];
  __is_global boolean;
  __deleted_face integer;
  __topo_layer_id integer;
  __n_updated integer;
  __srid integer;
BEGIN

SELECT * INTO __face FROM {topo_schema}.__dirty_face LIMIT 1;

SELECT srid
INTO __srid
FROM topology.topology
WHERE name= :topo_name;

SELECT precision
INTO __precision
FROM topology.topology
WHERE name = :topo_name;

/* Topogeometry ID for the map_face.topo column */
__topo_layer_id := {topo_schema}.__map_face_layer_id();

RAISE NOTICE 'Face ID: %, topology: %', __face.id, __face.map_layer;

/* Special case when adjacent to global face...we just
   remove the global face from the "dirty" table */
IF (__face.id = 0) THEN
  DELETE
  FROM {topo_schema}.__dirty_face df
  WHERE df.map_layer = __face.map_layer
    AND id = 0;
  RETURN __face;
END IF;

/* First, get the adjoining faces */
__dissolved_faces := {topo_schema}.adjacent_faces(__face.id,__face.map_layer);
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
-- DELETE FROM {topo_schema}.map_face
-- WHERE id IN (
  -- SELECT DISTINCT
    -- (map_topology.containing_face(
        -- unnest(__dissolved_faces), __face.topology)).id
-- );

--- Escape before topogeometry creation if global
IF (__is_global) THEN
  DELETE
  FROM {topo_schema}.__dirty_face df
  WHERE df.map_layer = __face.map_layer
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

__topo := topology.CreateTopoGeom(:topo_name , 3, __topo_layer_id, __topo_elements);

__geometry := ST_SetSRID(__topo::geometry,__srid);

DELETE FROM {topo_schema}.map_face mf
WHERE id IN (
  SELECT DISTINCT
    ({topo_schema}.containing_face(
        unnest(__dissolved_faces),
        __face.map_layer)
    ).id
  );

DELETE
FROM {topo_schema}.__dirty_face df
WHERE df.map_layer = __face.map_layer
  AND id = ANY(__dissolved_faces);

IF (__is_global) THEN
  DELETE
  FROM {topo_schema}.__dirty_face df
  WHERE df.map_layer = __face.map_layer
    AND id = 0;
  RETURN __face;
END IF;

INSERT INTO {topo_schema}.map_face
  (unit_id, topo, map_layer, geometry)
SELECT
  {topo_schema}.unitForArea(
    __geometry,
    __face.map_layer
  ) unit_id,
  __topo,
  __face.map_layer,
  __geometry;

DELETE
FROM {topo_schema}.__dirty_face df
WHERE df.map_layer = __face.map_layer
  AND id = ANY(__dissolved_faces);

RETURN __face;

END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION {topo_schema}.update_all_map_faces()
RETURNS void AS $$
BEGIN

-- Loop throug table of dirty linework
WHILE EXISTS (SELECT * FROM {topo_schema}.__dirty_face)
LOOP
  PERFORM {topo_schema}.update_map_face();
END LOOP;

END;
$$ LANGUAGE plpgsql;
