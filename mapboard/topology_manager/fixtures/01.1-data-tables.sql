/*
DATA TABLES
form the core of a mapping project. Polygons are stored in one table,
and polylines are stored in another.
*/

CREATE TABLE IF NOT EXISTS {data_schema}.linework_type (
    id text PRIMARY KEY,
    name text,
    color text,
    /** Whether this linework type is topological
    * If true, this linework type _must_ be used in a topological map layer.
    * If false, this linework type will not participate in topological operations,
    * even if the map layer is topological.
    * If null, the linework type will participate in topology only when used in
    * a topological map layer.
    */
    topological boolean
);

/*
Table to define feature types for polygon mode

It is typical usage to manually replace this table
with a view that refers to features from another table
(e.g. map units from a more broadly-defined table representation)

Other columns can also be added to this table as appropriate
*/
CREATE TABLE IF NOT EXISTS {data_schema}.polygon_type (
    id text PRIMARY KEY,
    name text,
    color text,
    -- Optional, for display...
    symbol text,
    symbol_color text,
    topological boolean
);

/**
Linking tables for the next stage of this
*/
CREATE TABLE IF NOT EXISTS {data_schema}.map_layer_linework_type (
    map_layer integer REFERENCES {data_schema}.map_layer(id) ON UPDATE CASCADE,
    type text REFERENCES {data_schema}.linework_type(id) ON UPDATE CASCADE,
    PRIMARY KEY (map_layer, type)
);

CREATE TABLE IF NOT EXISTS {data_schema}.map_layer_polygon_type (
    map_layer integer REFERENCES {data_schema}.map_layer(id) ON UPDATE CASCADE,
    type text REFERENCES {data_schema}.polygon_type(id) ON UPDATE CASCADE,
    PRIMARY KEY (map_layer, type)
);

/* Skeletal table structure needed to support linework for the map */
CREATE TABLE IF NOT EXISTS {data_schema}.linework (
  id            serial PRIMARY KEY,
  geometry      public.geometry(MultiLineString, {srid_literal}) NOT NULL,
  type          text NOT NULL REFERENCES {data_schema}.linework_type(id) ON UPDATE CASCADE,
  map_layer     integer NOT NULL REFERENCES {data_schema}.map_layer(id) ON UPDATE CASCADE,
  created       timestamp without time zone DEFAULT now(),
  name          text,
  -- Source layer for composite layers
  source_id     integer REFERENCES {data_schema}.linework(id) ON DELETE CASCADE,
  source_layer  integer REFERENCES {data_schema}.map_layer(id) ON DELETE CASCADE,
  covered       boolean DEFAULT false,
  FOREIGN KEY (type, map_layer) REFERENCES {data_schema}.map_layer_linework_type(type, map_layer) ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS {index_prefix}_linework_geometry_idx
  ON {data_schema}.linework USING gist (geometry);

/* Skeletal table structure needed to support polygon for the map */
CREATE TABLE IF NOT EXISTS {data_schema}.polygon (
  id            serial PRIMARY KEY,
  geometry      public.geometry(MultiPolygon, {srid_literal}) NOT NULL,
  type          text NOT NULL REFERENCES {data_schema}.polygon_type(id) ON UPDATE CASCADE,
  map_layer     integer NOT NULL REFERENCES {data_schema}.map_layer(id) ON UPDATE CASCADE,
  created       timestamp without time zone DEFAULT now(),
  name          text,
  FOREIGN KEY (type, map_layer) REFERENCES {data_schema}.map_layer_polygon_type(type, map_layer) ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS {index_prefix}_polygon_geometry_idx
  ON {data_schema}.polygon USING gist (geometry);


-- Create an initial linework type (if nothing exists)
INSERT INTO {data_schema}.linework_type (id, name, color)
SELECT
  'default',
  'Default',
  '#000000'
FROM topology.topology -- dummy table
WHERE NOT EXISTS (SELECT * FROM {data_schema}.linework_type)
  ON CONFLICT DO NOTHING;

-- Same for polygon-types
INSERT INTO {data_schema}.polygon_type (id, name, color)
SELECT
  'default',
  'Default',
  '#000000'
FROM topology.topology -- dummy table
WHERE NOT EXISTS (SELECT * FROM {data_schema}.polygon_type)
  ON CONFLICT DO NOTHING;

INSERT INTO {data_schema}.map_layer (id, name, topological)
VALUES (0, 'Default', true)
  ON CONFLICT DO NOTHING;

/* Add topology columns to linework table.
TODO: we should consider migrating this to a separate table within the topology schema.
*/
SELECT topology.AddTopoGeometryColumn(:topo_name, :data_schema_name,'linework', 'topo','LINE');
ALTER TABLE {data_schema}.linework
  ADD COLUMN geometry_hash uuid,
  ADD COLUMN topology_error text;
