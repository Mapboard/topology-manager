/*
DATA TABLES
form the core of a mapping project. Polygons are stored in one table,
and polylines are stored in another.
*/


CREATE SCHEMA IF NOT EXISTS {data_schema};

CREATE TABLE IF NOT EXISTS {data_schema}.map_layer (
    id text PRIMARY KEY,
    name text,
    description text,
    parent text CHECK (id != parent) REFERENCES {data_schema}.map_layer(id),
    topological boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS {data_schema}.linework_type (
    id text PRIMARY KEY,
    name text,
    color text
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
    symbol_color text
);

/**
Linking tables for the next stage of this

CREATE TABLE IF NOT EXISTS {data_schema}.map_layer_linework_type (
    layer text,
    type text,
    FOREIGN KEY (layer) REFERENCES {data_schema}.map_layer(id) ON UPDATE CASCADE,
    FOREIGN KEY (type) REFERENCES {data_schema}.linework_type(id) ON UPDATE CASCADE,
    PRIMARY KEY (layer, type)
);

CREATE TABLE IF NOT EXISTS {data_schema}.map_layer_polygon_type (
    layer text,
    type text,
    FOREIGN KEY (layer) REFERENCES {data_schema}.map_layer(id) ON UPDATE CASCADE,
    FOREIGN KEY (type) REFERENCES {data_schema}.polygon_type(id) ON UPDATE CASCADE,
    PRIMARY KEY (layer, type)
);
*/

/* Skeletal table structure needed to support linework for the map */
CREATE TABLE IF NOT EXISTS {data_schema}.linework (
  id            serial PRIMARY KEY,
  geometry      public.geometry(MultiLineString,:srid) NOT NULL,
  type          text NOT NULL REFERENCES {data_schema}.linework_type(id) ON UPDATE CASCADE,
  layer         text NOT NULL REFERENCES {data_schema}.map_layer(id) ON UPDATE CASCADE,
  created       timestamp without time zone DEFAULT now(),
  name          text
  /* FOREIGN KEY (type, layer) REFERENCES {data_schema}.map_layer_linework_type(type, layer) ON UPDATE CASCADE */
);

CREATE INDEX IF NOT EXISTS {index_prefix}_linework_geometry_idx
  ON {data_schema}.linework USING gist (geometry);

/* Skeletal table structure needed to support polygon for the map */
CREATE TABLE IF NOT EXISTS {data_schema}.polygon (
  id            serial PRIMARY KEY,
  geometry      public.geometry(MultiPolygon, :srid) NOT NULL,
  type          text NOT NULL REFERENCES {data_schema}.polygon_type(id) ON UPDATE CASCADE,
  layer         text NOT NULL REFERENCES {data_schema}.map_layer(id) ON UPDATE CASCADE,
  created       timestamp without time zone DEFAULT now(),
  name          text
  --FOREIGN KEY (type, layer) REFERENCES {data_schema}.map_layer_polygon_type(type, layer) ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS {index_prefix}_polygon_geometry_idx
  ON {data_schema}.polygon USING gist (geometry);
