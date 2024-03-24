/*
Map-Digitizer extension

Creates tables conforming to the map-digitizer spec as laid out in
https://github.com/davenquinn/map-digitizer-server/blob/master/db-fixtures/create-tables.sql

This table representation serves as a minimal interface that must
be implemented for a data_schema's compatibility with the Map-Digitizer server.
*/

ALTER TABLE {data_schema}.linework
  ADD COLUMN certainty integer,
  ADD COLUMN zoom_level integer,
  ADD COLUMN pixel_width numeric,
  ADD COLUMN map_width numeric,
  ADD COLUMN hidden boolean DEFAULT false,
  ADD COLUMN source text;

ALTER TABLE {data_schema}.polygon
  ADD COLUMN certainty integer,
  ADD COLUMN zoom_level integer,
  ADD COLUMN pixel_width numeric,
  ADD COLUMN map_width numeric,
  ADD COLUMN hidden boolean DEFAULT false,
  ADD COLUMN source text;
