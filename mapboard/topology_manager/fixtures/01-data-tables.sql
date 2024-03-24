/*
DATA TABLES
form the core of a mapping project. Polygons are stored in one table,
and polylines are stored in another.
*/


CREATE SCHEMA IF NOT EXISTS {data_schema};

CREATE TABLE IF NOT EXISTS {data_schema}.linework_type (
    id text PRIMARY KEY,
    name text,
    color text,
    topology text
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
    topology text,
    -- Optional, for display...
    symbol text,
    symbol_color text
);

/* Skeletal table structure needed to support linework for the map */
CREATE TABLE IF NOT EXISTS {data_schema}.linework (
  id            serial PRIMARY KEY,
  geometry      public.geometry(MultiLineString,${srid}) NOT NULL,
  type          text,
  created       timestamp without time zone DEFAULT now(),
  name          text,
  FOREIGN KEY (type) REFERENCES {data_schema}.linework_type(id) ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS ${data_schema^}_linework_geometry_idx
  ON {data_schema}.linework USING gist (geometry);

/* Skeletal table structure needed to support polygon for the map */
CREATE TABLE IF NOT EXISTS {data_schema}.polygon (
  id            serial PRIMARY KEY,
  geometry      public.geometry(MultiPolygon,${srid}) NOT NULL,
  type          text,
  created       timestamp without time zone DEFAULT now(),
  FOREIGN KEY (type) REFERENCES {data_schema}.polygon_type(id) ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS ${data_schema^}_polygon_geometry_idx
  ON {data_schema}.polygon USING gist (geometry);

