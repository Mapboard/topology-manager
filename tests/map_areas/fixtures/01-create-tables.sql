CREATE SCHEMA IF NOT EXISTS map_bounds;

-- Pick a relatively small tolerance to avoid gaps

ALTER TABLE map_bounds.map_layer ADD COLUMN IF NOT EXISTS slug text UNIQUE;
ALTER TABLE map_bounds.map_layer ADD COLUMN IF NOT EXISTS bounds Geometry(MultiPolygon, 4326);

SELECT topology.CreateTopology('map_bounds_topology', 4326, 0.0001)
WHERE NOT EXISTS (
  SELECT 1
  FROM topology.topology
  WHERE name = 'map_bounds_topology'
);

/** The area of full maps in the topology */
CREATE TABLE IF NOT EXISTS map_bounds.map_area (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  geometry Geometry(MultiPolygon, 4326) NOT NULL,
  geometry_hash uuid,
  topology_error text,
  map_layer integer REFERENCES map_bounds.map_layer(id),
  area_km double precision
);

/** Create a topogeometry column for the area of full maps. */
SELECT topology.AddTopoGeometryColumn('map_bounds_topology', 'map_bounds','map_area', 'topo','POLYGON')
WHERE NOT EXISTS (
  SELECT 1
  FROM topology.topology
  JOIN topology.layer
  ON topology.topology.id = topology.layer.topology_id
  WHERE topology.name = 'map_bounds_topology'
    AND topology.layer.schema_name = 'map_bounds'
    AND topology.layer.table_name = 'map_area'
    AND topology.layer.feature_column = 'topo'
);

CREATE OR REPLACE FUNCTION map_bounds_topology.get_topological_map_layer(_line map_bounds.map_area)
  RETURNS integer AS $$
SELECT ml.id
FROM map_bounds.map_layer ml
WHERE ml.id = $1.map_layer
  AND ml.composited_from IS NULL
  AND ml.topological;
$$ LANGUAGE SQL IMMUTABLE;


CREATE TABLE IF NOT EXISTS map_bounds.map_priority (
  map_layer integer REFERENCES map_bounds.map_layer(id) ON DELETE CASCADE,
  map_id integer REFERENCES map_bounds.map_area(id) ON DELETE CASCADE,
  priority integer DEFAULT 0,
  PRIMARY KEY (map_layer, map_id)
);


CREATE OR REPLACE FUNCTION map_bounds.layer_id(_slug text)
  RETURNS integer AS $$
SELECT id FROM map_bounds.map_layer WHERE slug = _slug;
$$ LANGUAGE SQL IMMUTABLE;

/** Standard map compilations */
INSERT INTO map_bounds.map_layer (slug, name, bounds, topological)
VALUES
  ('tiny', 'Tiny',  ST_Multi(ST_MakeEnvelope(-180, -90, 180, 90, 4326)), true),
  ('small', 'Small', ST_Multi(ST_MakeEnvelope(-180, -90, 180, 90, 4326)), true),
  ('medium', 'Medium',  ST_Multi(ST_MakeEnvelope(-180, -90, 180, 90, 4326)), true),
  ('large', 'Large', ST_Multi(ST_MakeEnvelope(-180, -90, 180, 90, 4326)), true)
ON CONFLICT (slug) DO NOTHING;

/** Composite compilations */
INSERT INTO map_bounds.map_layer (slug, name, bounds, topological, editable, composited_from)
VALUES
 ('carto-small', 'Carto small',
  ST_Multi(ST_MakeEnvelope(-180, -90, 180, 90, 4326)), true, false,
  ARRAY[map_bounds.layer_id('tiny'), map_bounds.layer_id('small')]),
 ('carto-medium', 'Carto medium',
  ST_Multi(ST_MakeEnvelope(-180, -90, 180, 90, 4326)), true, false,
  ARRAY[map_bounds.layer_id('small'), map_bounds.layer_id('medium')]),
 ('carto-large', 'Carto large',
  ST_Multi(ST_MakeEnvelope(-180, -90, 180, 90, 4326)), true, false,
  ARRAY[map_bounds.layer_id('medium'), map_bounds.layer_id('large')])
ON CONFLICT (slug) DO NOTHING;
