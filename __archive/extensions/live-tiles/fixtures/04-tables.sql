CREATE TABLE IF NOT EXISTS tiles.layer (
  id serial PRIMARY KEY,
  format text NOT NULL,
  content_type text NOT NULL,
  name text NOT NULL
);

CREATE TABLE IF NOT EXISTS tiles.tile (
  z integer NOT NULL,
  x integer NOT NULL,
  y integer NOT NULL,
  tile bytea NOT NULL,
  layer_id integer NOT NULL REFERENCES tiles.layer(id),
  created timestamp without time zone DEFAULT now(),
  stale boolean,
  PRIMARY KEY (z, x, y, layer_id)
);

INSERT INTO tiles.layer (id, format, content_type, name)
VALUES (0, 'pbf', 'application/protobuf', 'map-data')
ON CONFLICT DO NOTHING;


