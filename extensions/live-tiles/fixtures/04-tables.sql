CREATE TABLE IF NOT EXISTS tiles.tile (
  z integer NOT NULL,
  x integer NOT NULL,
  y integer NOT NULL,
  tile bytea NOT NULL,
  created timestamp without time zone DEFAULT now(),
  PRIMARY KEY (z, x, y)
);

