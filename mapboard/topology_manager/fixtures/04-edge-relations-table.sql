/** Edge relations table view

This creates a dynamic, table-based materialized "view" of the
relationships between edges and faces. This is used to speed up
adjacency queries, and is updated by the triggers on the linework
and relation tables.
*/


/** A dynamic view that can store a guide */
CREATE OR REPLACE VIEW {topo_schema}.__edge_relation_dynamic AS
SELECT
  l.id line_id,
  l.map_layer,
  abs(r.element_id) edge_id
FROM {topo_schema}.edge_data e
JOIN {topo_schema}.relation r
  ON e.edge_id = abs(r.element_id)
 AND r.element_type = 2 -- edges
JOIN {data_schema}.linework l
  ON (l.topo).id = r.topogeo_id
  AND r.layer_id = (l.topo).layer_id
JOIN {data_schema}.map_layer ml
  ON l.map_layer = ml.id
WHERE l.topo IS NOT null
  AND ml.topological;

/** Initially create the table */
CREATE TABLE IF NOT EXISTS {topo_schema}.__edge_relation (
  line_id integer NOT NULL REFERENCES {data_schema}.linework(id) ON DELETE CASCADE,
  map_layer integer NOT NULL REFERENCES {data_schema}.map_layer(id) ON DELETE CASCADE,
  edge_id integer NOT NULL REFERENCES {topo_schema}.edge_data(edge_id) ON DELETE CASCADE,
  topogeo_id integer NOT NULL,
  topolayer_id integer NOT NULL,
  PRIMARY KEY (line_id, edge_id)
);

/** Initial population of the table */
INSERT INTO {topo_schema}.__edge_relation (
  line_id,
  map_layer,
  edge_id,
  topogeo_id,
  topolayer_id
)
SELECT
  l.id line_id,
  l.map_layer,
  abs(r.element_id) edge_id,
  (l.topo).id topogeo_id,
  (l.topo).layer_id topolayer_id
FROM {topo_schema}.edge_data e
JOIN {topo_schema}.relation r
  ON e.edge_id = abs(r.element_id)
 AND r.element_type = 2 -- edges
JOIN {data_schema}.linework l
  ON (l.topo).id = r.topogeo_id
  AND r.layer_id = (l.topo).layer_id
JOIN {data_schema}.map_layer ml
  ON l.map_layer = ml.id
ON CONFLICT DO NOTHING;

/** Update this table based on changes to the "relation" table */
CREATE OR REPLACE FUNCTION {topo_schema}.update_edge_relation()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- not sure if we need to delete on update
    DELETE FROM {topo_schema}.__edge_relation
    WHERE edge_id = abs(OLD.element_id)
      AND topolayer_id = OLD.layer_id
      AND topogeo_id = OLD.topogeo_id;

    RETURN OLD;
  END IF;

  IF NEW.element_type != 2 THEN
    RETURN NULL;
  END IF;

  -- In all other cases we insert
  INSERT INTO {topo_schema}.__edge_relation (
    line_id,
    map_layer,
    edge_id,
    topogeo_id,
    topolayer_id
  )
  SELECT
    l.id line_id,
    l.map_layer,
    abs(NEW.element_id) edge_id,
    (l.topo).id topogeo_id,
    (l.topo).layer_id topolayer_id
  FROM {data_schema}.linework l
  WHERE l.topo IS NOT NULL
    AND (l.topo).id = NEW.topogeo_id
    AND (l.topo).layer_id = NEW.layer_id
  ON CONFLICT (line_id, edge_id) DO UPDATE
  SET
    topogeo_id = EXCLUDED.topogeo_id,
    topolayer_id = EXCLUDED.topolayer_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_edge_relation
AFTER INSERT OR UPDATE OR DELETE
ON {topo_schema}.relation
FOR EACH ROW
EXECUTE FUNCTION {topo_schema}.update_edge_relation();

/** Change the map layer if it is updated for a line */
CREATE OR REPLACE FUNCTION {topo_schema}.update_edge_relation_map_layer()
RETURNS trigger AS $$
BEGIN
  UPDATE {topo_schema}.__edge_relation
  SET map_layer = NEW.map_layer
  WHERE line_id = OLD.id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_edge_relation_map_layer
AFTER UPDATE
ON {data_schema}.linework
FOR EACH ROW
WHEN (OLD.map_layer IS DISTINCT FROM NEW.map_layer)
EXECUTE FUNCTION {topo_schema}.update_edge_relation_map_layer();
