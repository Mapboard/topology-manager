/*
Map-Digitizer extension

Creates tables conforming to the map-digitizer spec as laid out in
https://github.com/davenquinn/map-digitizer-server/blob/master/db-fixtures/create-tables.sql

This table representation serves as a minimal interface that must
be implemented for a data_schema's compatibility with the Map-Digitizer server.
*/
CREATE SCHEMA IF NOT EXISTS ${data_schema~};

CREATE TABLE IF NOT EXISTS ${data_schema~}.linework_type (
    id text PRIMARY KEY,
    name text,
    color text,
    topology text
);

CREATE TABLE IF NOT EXISTS ${data_schema~}.linework (
  id            serial PRIMARY KEY,
  geometry      public.geometry(MultiLineString,${srid}) NOT NULL,
  type          text,
  created       timestamp without time zone DEFAULT now(),
  certainty     integer,
  zoom_level    integer,
  pixel_width   numeric,
  map_width     numeric,
  hidden        boolean DEFAULT false,
  source        text,
  name          text,
  FOREIGN KEY (type) REFERENCES ${data_schema~}.linework_type(id) ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS ${data_schema^}_linework_geometry_idx ON ${data_schema~}.linework USING gist (geometry);

/*
Table to define feature types for polygon mode

It is typical usage to manually replace this table
with a view that refers to features from another table
(e.g. map units from a more broadly-defined table representation)

Other columns can also be added to this table as appropriate
*/

CREATE TABLE IF NOT EXISTS ${data_schema~}.polygon_type (
    id text PRIMARY KEY,
    name text,
    color text,
    topology text
);

CREATE TABLE IF NOT EXISTS ${data_schema~}.polygon (
  id            serial PRIMARY KEY,
  geometry      public.geometry(MultiPolygon,${srid}) NOT NULL,
  type          text,
  created       timestamp without time zone DEFAULT now(),
  certainty     integer,
  zoom_level    integer,
  hidden        boolean DEFAULT false,
  source        text,
  name          text,
  FOREIGN KEY (type) REFERENCES ${data_schema~}.polygon_type(id) ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS ${data_schema^}_polygon_geometry_idx
   ON ${data_schema~}.polygon USING gist (geometry);

