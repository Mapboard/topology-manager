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