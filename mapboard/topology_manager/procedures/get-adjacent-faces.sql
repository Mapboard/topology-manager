WITH RECURSIVE r(faces, adjacent, cycle) AS (
  SELECT
    ARRAY[edge.left_face, edge.right_face] AS faces,
    {topo_schema}.opposite_face(edge, :face_id) AS adjacent,
    false AS cycle
  FROM {topo_schema}.edge_data edge
    LEFT JOIN {topo_schema}.__edge_relation er
  ON er.edge_id = edge.edge_id
  WHERE (edge.left_face = :face_id OR edge.right_face = :face_id)
                                 AND edge.left_face != edge.right_face
                                 AND er.map_layer != :map_layer
    AND NOT EXISTS (
    SELECT 1
    FROM {topo_schema}.__edge_relation er_sub
    WHERE er_sub.edge_id = edge.edge_id
    AND er_sub.map_layer IN (
    SELECT * FROM {topo_schema}.parent_map_layers(:map_layer)
    )
    )
  UNION ALL
  SELECT
    r1.faces || {topo_schema}.opposite_face(edge, r1.adjacent) AS faces,
    {topo_schema}.opposite_face(edge, r1.adjacent) AS adjacent,
    {topo_schema}.opposite_face(edge, r1.adjacent) = ANY(r1.faces) AS cycle
  FROM {topo_schema}.edge_data edge
    LEFT JOIN {topo_schema}.__edge_relation er
  ON er.edge_id = edge.edge_id
    JOIN r r1
    ON (r1.adjacent = edge.left_face OR r1.adjacent = edge.right_face)
  WHERE edge.left_face != edge.right_face
  AND NOT r1.cycle
  AND r1.adjacent != 0
  AND er.map_layer != :map_layer
    AND NOT EXISTS (
    SELECT 1
    FROM {topo_schema}.__edge_relation er_sub
    WHERE er_sub.edge_id = edge.edge_id
    AND er_sub.map_layer IN (
    SELECT * FROM {topo_schema}.parent_map_layers(:map_layer)
    )
  )
), b AS (
  SELECT DISTINCT unnest(r.faces) AS face
  FROM r
  WHERE NOT r.cycle
)
SELECT array_agg(b.face) AS faces
FROM b;
