/*
DATA TABLES
form the core of a mapping project. Polygons are stored in one table,
and polylines are stored in another.
*/


CREATE SCHEMA IF NOT EXISTS {data_schema};

CREATE TABLE IF NOT EXISTS {data_schema}.map_layer (
    id serial PRIMARY KEY,
    name text NOT NULL,
    description text,
    parent integer CHECK (id != parent) REFERENCES {data_schema}.map_layer(id),
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
  geometry      public.geometry(MultiLineString,:srid) NOT NULL,
  type          text NOT NULL REFERENCES {data_schema}.linework_type(id) ON UPDATE CASCADE,
  map_layer     integer NOT NULL REFERENCES {data_schema}.map_layer(id) ON UPDATE CASCADE,
  created       timestamp without time zone DEFAULT now(),
  name          text,
  FOREIGN KEY (type, map_layer) REFERENCES {data_schema}.map_layer_linework_type(type, map_layer) ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "{index_prefix}_linework_geometry_idx"
  ON {data_schema}.linework USING gist (geometry);

/* Skeletal table structure needed to support polygon for the map */
CREATE TABLE IF NOT EXISTS {data_schema}.polygon (
  id            serial PRIMARY KEY,
  geometry      public.geometry(MultiPolygon, :srid) NOT NULL,
  type          text NOT NULL REFERENCES {data_schema}.polygon_type(id) ON UPDATE CASCADE,
  map_layer     integer NOT NULL REFERENCES {data_schema}.map_layer(id) ON UPDATE CASCADE,
  created       timestamp without time zone DEFAULT now(),
  name          text,
  FOREIGN KEY (type, map_layer) REFERENCES {data_schema}.map_layer_polygon_type(type, map_layer) ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "{index_prefix}_polygon_geometry_idx"
  ON {data_schema}.polygon USING gist (geometry);

/** A view to summarize the tree of map layers */
CREATE OR REPLACE VIEW {data_schema}.map_layer_tree AS
WITH RECURSIVE parents AS (
SELECT
	id base,
  id,
  parent
FROM {data_schema}.map_layer
UNION
SELECT
	base,
	ml.id,
  ml.parent
FROM parents
JOIN {data_schema}.map_layer ml
  ON ml.id = parents.parent
),
children AS (
SELECT
	id base,
  id,
  parent
FROM {data_schema}.map_layer
UNION
SELECT
	base,
	ml.id,
  ml.parent
FROM children
JOIN {data_schema}.map_layer ml
  ON ml.parent = children.id
),
p1 AS (
SELECT
	p.base map_layer,
	array_agg(id) with_parents
FROM parents p
GROUP BY p.base
),
c1 AS (
SELECT
	c.base map_layer,
	array_agg(id) with_children
FROM children c
GROUP BY c.base
)
SELECT
	p1.map_layer,
	p1.with_parents,
	c1.with_children
FROM p1
JOIN c1
  ON p1.map_layer = c1.map_layer
