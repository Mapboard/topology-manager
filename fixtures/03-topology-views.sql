CREATE OR REPLACE VIEW map_topology.edge_contact AS
  SELECT
  	id contact_id,
  	r.element_id edge_id
	FROM map_digitizer.linework
  JOIN map_topology.relation r
	  ON (topo).id = r.topogeo_id
	  AND (topo).layer_id = r.layer_id
	  AND (topo).type = r.element_type;

CREATE OR REPLACE VIEW map_topology.node_edge AS
  WITH node_edge AS (
    SELECT
      edge_id,
      start_node node_id
    FROM map_topology.edge
    UNION ALL
    SELECT
      edge_id,
      end_node node_id
    FROM map_topology.edge
  ),
  node_contact AS (
  SELECT
    n.node_id,
    n.geom,
    ec.contact_id
  FROM map_topology.node n
  JOIN node_edge ne ON ne.node_id = n.node_id
  JOIN map_topology.edge_contact ec ON ne.edge_id = ec.edge_id
  )
  SELECT
    n.node_id,
    array_agg(contact_id) edges,
    count(contact_id) n_edges
  FROM map_topology.node n
  JOIN node_contact ne ON ne.node_id = n.node_id
  GROUP BY n.node_id;

CREATE OR REPLACE VIEW map_topology.edge_face AS
WITH ef AS (
SELECT
  edge_id,
  left_face face_id
FROM map_topology.edge_data
UNION ALL
SELECT
  edge_id,
  right_face face_id
FROM map_topology.edge_data
)
SELECT DISTINCT ON (edge_id,face_id)
  edge_id, face_id
FROM ef;

CREATE OR REPLACE VIEW map_topology.node_multiplicity AS
SELECT
  n.node_id,
  geom,
  n_edges
FROM map_topology.node n
JOIN map_topology.node_edge e ON n.node_id = e.node_id;

CREATE OR REPLACE VIEW map_topology.edge_type AS
  SELECT
    e.edge_id,
    geom geometry,
    c.id contact_id,
    c.type contact_type
  FROM map_topology.edge e
  JOIN map_topology.edge_contact ec ON e.edge_id = ec.edge_id
  JOIN map_digitizer.linework c ON c.id = ec.contact_id;

CREATE OR REPLACE VIEW map_topology.face_data AS
WITH fg AS (
SELECT
face_id,
ST_GetFaceGeometry('map_topology', face_id) geometry
FROM map_topology.face
WHERE face_id <> 0
)
SELECT * FROM fg
WHERE NOT ST_IsEmpty(geometry);


-- Can be reworked with create table and triggers
-- http://lists.osgeo.org/pipermail/postgis-users/2015-June/040551.html
-- https://hashrocket.com/blog/posts/materialized-view-strategies-using-postgresql
CREATE OR REPLACE VIEW map_topology.edge_topology AS
SELECT
  e.edge_id,
  t.topology,
  geometry
FROM map_topology.edge_contact ec
JOIN map_topology.edge e ON ec.edge_id = e.edge_id
JOIN map_digitizer.linework c ON ec.contact_id = c.id
JOIN map_digitizer.linework_type t ON c.type = t.id
WHERE t.topology IS NOT null;

CREATE OR REPLACE VIEW map_topology.face_display AS
SELECT
  f.id,
  f.unit_id,
  f.geometry,
  f.topology,
  t.color,
  t.name
FROM map_topology.map_face f
JOIN map_digitizer.polygon_type t
  ON f.unit_id = t.id;

