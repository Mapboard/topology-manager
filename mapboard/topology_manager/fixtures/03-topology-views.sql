CREATE OR REPLACE VIEW {topo_schema}.node_edge AS
  WITH a AS (
    SELECT edge.edge_id,
      edge.start_node AS node_id
     FROM {topo_schema}.edge
    UNION ALL
    SELECT edge.edge_id,
      edge.end_node AS node_id
    FROM {topo_schema}.edge
  )
  SELECT
    node_id,
    array_agg(edge_id) edges,
    count(edge_id) n_edges
  FROM a
  GROUP BY node_id;

CREATE OR REPLACE VIEW {topo_schema}.edge_face AS
WITH ef AS (
SELECT
  edge_id,
  left_face face_id
FROM {topo_schema}.edge_data
UNION ALL
SELECT
  edge_id,
  right_face face_id
FROM {topo_schema}.edge_data
)
SELECT DISTINCT ON (edge_id,face_id)
  edge_id, face_id
FROM ef;

CREATE OR REPLACE VIEW {topo_schema}.node_multiplicity AS
SELECT
  n.node_id,
  geom,
  n_edges
FROM {topo_schema}.node n
JOIN {topo_schema}.node_edge e ON n.node_id = e.node_id;

CREATE OR REPLACE VIEW {topo_schema}.face_data AS
WITH fg AS (
SELECT
face_id,
topology.ST_GetFaceGeometry(  :topo_name , face_id) geometry
FROM {topo_schema}.face
WHERE face_id <> 0
)
SELECT * FROM fg
WHERE NOT ST_IsEmpty(geometry);


-- Can be reworked with create table and triggers
-- http://lists.osgeo.org/pipermail/postgis-users/2015-June/040551.html
-- https://hashrocket.com/blog/posts/materialized-view-strategies-using-postgresql

CREATE OR REPLACE VIEW {topo_schema}.face_display AS
SELECT
  f.id,
  f.unit_id,
  f.geometry,
  t.topology,
  t.color,
  t.name
FROM {topo_schema}.map_face f
LEFT JOIN {data_schema}.polygon_type t
  ON f.unit_id = t.id;
