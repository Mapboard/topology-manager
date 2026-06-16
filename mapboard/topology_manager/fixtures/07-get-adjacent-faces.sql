/*
This is the core algorithm that accumulates topology faces
into a map layer, starting from a given face_id.

Right now this works separately for each map layer,
but we might find optimizations by separately handling
nested map layers.

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

DROP TYPE IF EXISTS {topo_schema}.face_group CASCADE;
CREATE TYPE {topo_schema}.face_group AS (
  faces integer[],
  niter integer,
  map_layer integer
);

CREATE OR REPLACE FUNCTION {topo_schema}.get_adjacent_faces_core(
  face_id integer,
  _map_layer integer,
  _barrier_layers integer[] DEFAULT ARRAY[]::integer[]
)
RETURNS {topo_schema}.face_group
AS $$
WITH RECURSIVE
  boundary_layers_no_parents AS (
    -- Layers at which face dissolving stops
    SELECT _map_layer AS id
    -- Additional barrier layers can be added here. They and their parents will be used.
    -- This can be used to create composite layers, etc.
    UNION ALL
    SELECT unnest(_barrier_layers) AS id
  ),
  boundary_layers AS (
    -- Get all parent layers of the boundary layers
    SELECT DISTINCT ON (id) {topo_schema}.parent_map_layers(lyr.id) AS id
    FROM boundary_layers_no_parents lyr
  ),
  edge_groups AS (
    SELECT
      e.edge_id,
      e.left_face,
      e.right_face,
      array_remove(array_agg(er.map_layer), null) layers
    FROM {topo_schema}.edge_data e
    LEFT JOIN {topo_schema}.__edge_relation er
      ON er.edge_id = e.edge_id
    WHERE e.left_face != e.right_face
    GROUP BY e.edge_id, e.left_face, e.right_face
  ),
  joinable_edges AS (
    SELECT
      e.edge_id,
      e.left_face,
      e.right_face
    FROM edge_groups e
    WHERE
      NOT layers && array(SELECT * FROM boundary_layers)
      OR array_length(layers, 1) = 0
  ),
  face_relations AS (
    SELECT left_face, right_face FROM joinable_edges
    UNION ALL
    SELECT right_face, left_face FROM joinable_edges
  ),
  face_adjacency AS (
    SELECT left_face this_face, right_face opp_face
    FROM face_relations
    WHERE {topo_schema}.faces_are_joinable(left_face, right_face, _map_layer)
    GROUP BY left_face, right_face
  ),
  r(faces, edge_faces, depth) AS (
    /** This recursive query works outwards as a 'wave',
    * starting from the given face_id and moving outwards
      accumulating adjacent faces in a given map layer
      until there are no more to find.

      We should stop when we reach the global face, but we don't do this now.

      This works on face primitives but a similar approach
      could accumulate based on child topogeometries, for layers
      with child topological layers...
     */
    SELECT
      ARRAY[]::integer[] AS faces,
      ARRAY[face_id] edge_faces,
      0 AS depth
    UNION ALL
    SELECT
      r.faces || r.edge_faces faces,
      array(
        SELECT opp_face
        FROM face_adjacency fa
        WHERE fa.this_face = ANY(r.edge_faces)
        AND NOT fa.opp_face = ANY(r.faces || r.edge_faces)
      ) AS edge_faces,
      r.depth + 1
    FROM r
    WHERE array_length(r.edge_faces, 1) > 0
    GROUP BY r.faces, r.edge_faces, r.depth
  )
SELECT faces, depth niter, _map_layer map_layer
FROM r
ORDER BY depth DESC
LIMIT 1;
$$ LANGUAGE SQL STABLE;


/** Get faces that can be dissolved into a given map layer */
CREATE OR REPLACE FUNCTION {topo_schema}.adjacent_faces(
  face_id integer,
  _map_layer integer
)
RETURNS integer[]
AS $$
  SELECT ({topo_schema}.get_adjacent_faces_core(face_id, _map_layer)).faces
$$ LANGUAGE SQL STABLE;
