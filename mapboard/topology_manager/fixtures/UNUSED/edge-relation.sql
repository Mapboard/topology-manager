/** EDGE INFRASTRUCTURE
This table exists to hold all the edges that are relevant to a particular map
layer.
*/
CREATE TABLE IF NOT EXISTS {topo_schema}.__edge_relation (
  edge_id   integer NOT NULL REFERENCES {topo_schema}.edge_data(edge_id) ON DELETE CASCADE,
  map_layer integer NOT NULL REFERENCES {data_schema}.map_layer(id) ON DELETE CASCADE,
  line_id   integer NOT NULL REFERENCES {data_schema}.linework(id) ON DELETE CASCADE,
  is_child  boolean NOT NULL,
  PRIMARY KEY (edge_id, map_layer)
);

