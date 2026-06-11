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
topology.ST_GetFaceGeometry({topo_name_literal} , face_id) geometry
FROM {topo_schema}.face
WHERE face_id <> 0
)
SELECT * FROM fg
WHERE NOT ST_IsEmpty(geometry);

/** TODO: move this into the platform repository */
-- Can be reworked with create table and triggers
-- http://lists.osgeo.org/pipermail/postgis-users/2015-June/040551.html
-- https://hashrocket.com/blog/posts/materialized-view-strategies-using-postgresql
DROP VIEW IF EXISTS {topo_schema}.face_display;
CREATE OR REPLACE VIEW {topo_schema}.face_display AS
SELECT
  f.id,
  f.unit_id,
  f.geometry,
  f.map_layer,
  f.source_layer,
  t.color,
  t.name,
  'fgdc:' || replace(t.symbol, '-K', '') symbol,
  t.symbol_color
FROM {topo_schema}.map_face f
LEFT JOIN {data_schema}.polygon_type t
  ON f.unit_id = t.id
LEFT JOIN {data_schema}.map_layer l
  ON f.map_layer = l.id
WHERE l.topological;

SELECT DISTINCT ON (mf.id) *
FROM {topo_schema}.map_face mf
JOIN {topo_schema}.relation r
  ON (mf.topo).layer_id = r.layer_id
 AND (mf.topo).id = r.topogeo_id
 AND r.element_type = 3;

-- get a single representive face for each layer
CREATE OR REPLACE VIEW {topo_schema}.seed_face AS
SELECT mf.id,
  mf.map_layer,
  coalesce(mf.source_layer, mf.map_layer) source_layer,
  sub.face_id                             seed_face_id
FROM {topo_schema}.map_face mf
JOIN LATERAL (
    SELECT element_id face_id
    FROM {topo_schema}.relation r
    WHERE (mf.topo).layer_id = r.layer_id
    AND (mf.topo).id = r.topogeo_id
    AND r.element_type = 3
    LIMIT 1
) sub ON true;

/** Face parents */
CREATE OR REPLACE VIEW {topo_schema}.map_face_parents AS
WITH f1 AS (
  SELECT sf.*,
  {topo_schema}.parent_map_layers(sf.source_layer) parent_layer
  FROM {topo_schema}.seed_face sf)
SELECT
  f1.id map_face_id,
  f1.map_layer,
  f1.source_layer,
  f1.parent_layer,
  ml.name parent_layer_name,
  {topo_schema}.unitforface(f1.seed_face_id, parent_layer) unit_id
FROM f1
JOIN {data_schema}.map_layer ml
  ON f1.parent_layer = ml.id;
