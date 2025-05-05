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
WHERE (edge.left_face = face_id OR edge.right_face = face_id)
  AND edge.left_face != edge.right_face
  AND er.map_layer IS DISTINCT FROM _map_layer
  AND NOT EXISTS (
    SELECT edge_id FROM {topo_schema}.__edge_relation er
    WHERE edge_id = edge.edge_id
      AND er.map_layer IN (SELECT * FROM {topo_schema}.parent_map_layers(_map_layer))
  )
UNION
SELECT DISTINCT ON ({topo_schema}.opposite_face(edge, r1.adjacent))
  r1.faces || {topo_schema}.opposite_face(edge, r1.adjacent) faces,
  {topo_schema}.opposite_face(edge, r1.adjacent) adjacent,
  ({topo_schema}.opposite_face(edge, r1.adjacent) = ANY(r1.faces)) AS cycle
FROM {topo_schema}.edge_data edge
LEFT JOIN {topo_schema}.__edge_relation er
  ON er.edge_id = edge.edge_id
JOIN r r1
  ON (r1.adjacent = edge.left_face OR r1.adjacent = edge.right_face)
WHERE edge.left_face != edge.right_face
  AND NOT cycle
  AND NOT r1.adjacent = 0
  AND er.map_layer IS DISTINCT FROM _map_layer
  AND NOT EXISTS (
    SELECT edge_id FROM {topo_schema}.__edge_relation er
    WHERE edge_id = edge.edge_id
      AND er.map_layer IN (SELECT * FROM {topo_schema}.parent_map_layers(_map_layer))
  )
), b AS (
SELECT DISTINCT unnest(faces) face FROM r WHERE NOT cycle
)
SELECT array_agg(face) faces FROM b;
$$ LANGUAGE SQL IMMUTABLE;
