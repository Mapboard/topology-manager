/*
        SELECT
            f.id
        FROM {topo_schema}.map_face f
        JOIN {topo_schema}.relation r
          ON (f.topo).id = r.topogeo_id
          AND r.layer_id = (f.topo).layer_id
        WHERE r.element_id = ANY(:faces)
          AND r.element_type = 3
          AND f.map_layer = :map_layer
 */

WITH RECURSIVE
  -- These first two are mirrors of the __edge_relations table,
  -- designed to remove that as a source of potential confusion
  line_data AS (
    SELECT
      l.id,
      l.topo,
      l.map_layer
    FROM {data_schema}.linework l
    WHERE l.topo IS NOT null
     -- AND l.map_layer IS NOT null
  ),
  edge_relations AS (
    SELECT
      f.id line_id,
      r.element_id edge_id,
      f.map_layer map_layer
    FROM line_data f
    JOIN {topo_schema}.relation r
      ON (f.topo).id = r.topogeo_id
      AND r.layer_id = (f.topo).layer_id
    WHERE r.element_type = 2 -- edges
  ),
  edges AS (SELECT
              edge_id,
              left_face,
              right_face
            FROM
              {topo_schema}.edge_data
            WHERE
              left_face != right_face
  ),
  joinable_edges AS (
    SELECT
      edges.edge_id,
      left_face,
      right_face,
      er.map_layer,
      er.line_id
    FROM edges
    LEFT JOIN edge_relations er
    ON er.edge_id = edges.edge_id
    WHERE er.map_layer NOT IN (
      SELECT * FROM {topo_schema}.parent_map_layers(:map_layer)
    )
    --AND NOT er.is_child
    OR er.map_layer IS NULL -- no line is registered to this edge in any layer
    -- (it may not be yet cleaned up, or is just attached to a map face)

  ),
  face_relations AS (
    SELECT left_face, right_face FROM joinable_edges
    UNION ALL
    SELECT right_face, left_face FROM joinable_edges
  ),
  face_adjacency AS (
    SELECT left_face this_face, right_face opp_face
    FROM face_relations
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
      ARRAY[:face_id] edge_faces,
      0 AS depth
    UNION ALL
    SELECT
      r.faces || r.edge_faces faces,
      array(
        SELECT opp_face
        FROM face_adjacency fa
        WHERE fa.this_face = ANY(r.edge_faces)
        AND NOT fa.opp_face = ANY(r.faces)
        AND NOT fa.opp_face = ANY(r.edge_faces)
      ) AS edge_faces,
      r.depth + 1
    FROM r
    WHERE array_length(r.edge_faces, 1) > 0
    GROUP BY r.faces, r.edge_faces, r.depth
  )
SELECT faces, depth
FROM r
ORDER BY depth DESC
LIMIT 1;
