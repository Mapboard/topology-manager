CREATE SCHEMA IF NOT EXISTS strabo;
CREATE SCHEMA IF NOT EXISTS "ossp-uuid";

CREATE TABLE IF NOT EXISTS strabo.spots (
  id varchar(14) PRIMARY KEY,
  data jsonb
);