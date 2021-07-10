CREATE SCHEMA IF NOT EXISTS strabo;
CREATE SCHEMA IF NOT EXISTS "ossp-uuid";

CREATE TABLE IF NOT EXISTS strabo.spots (
  id varchar(14) PRIMARY KEY,
  data jsonb
);

CREATE TABLE IF NOT EXISTS strabo.tags (
  id varchar(14) PRIMARY KEY,
  data jsonb
);

CREATE TABLE IF NOT EXISTS strabo.spot_tags (
  spot_id varchar(14) REFERENCES strabo.spots(id),
  tag_id varchar(14) REFERENCES strabo.tags(id),
  PRIMARY KEY (spot_id, tag_id)
);

ALTER TABLE ${data_schema~}.polygon
  ADD COLUMN spot_id varchar(14) REFERENCES strabo.spots(id);

ALTER TABLE ${data_schema~}.polygon_type
  ADD COLUMN tag_id varchar(14) REFERENCES strabo.tags(id);

CREATE OR REPLACE VIEW map_digitizer.polygon_display AS
SELECT p.*, pt.color, pt.symbol, pt.symbol_color FROM map_digitizer.polygon p
JOIN map_digitizer.polygon_type pt
  ON p.type = pt.id