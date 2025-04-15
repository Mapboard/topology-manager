WITH RECURSIVE
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
      er.line_id,
      er.is_child
    FROM edges
    LEFT JOIN {topo_schema}.__edge_relation er
    ON er.edge_id = edges.edge_id
    WHERE er.map_layer NOT IN (
      SELECT * FROM {topo_schema}.parent_map_layers(:map_layer)
    )
  ),
  face_relations AS (
    SELECT left_face, right_face FROM joinable_edges
    UNION ALL
    SELECT right_face, left_face FROM joinable_edges
  ),
  face_adjacency AS (
    SELECT left_face this_face, right_face opp_face
    FROM face_relations
    WHERE left_face != 0 AND right_face != 0
    GROUP BY left_face, right_face
  ),
  r(faces, edge_faces, depth) AS (
    /** This recursive query works outwards as a 'wave',
    * starting from the given face_id and moving outwards
      accumulating adjacent faces in a given map layer
      until there are no more to find.

      This works on face primitives but a similar approach
      could accumulate based on child topogeometries, for layers
      with child topological layers...
     */
    SELECT
      ARRAY[]::integer[] AS faces,
      ARRAY[:face_id] edge_faces,
      1 AS depth
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
