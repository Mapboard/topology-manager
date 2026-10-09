/* Display attributes for the library's own data tables: `unit_id` and
   `polygon_type` exist only when the library creates them, so this fixture is
   skipped for a host that creates its own (see `create_tables`). */

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
