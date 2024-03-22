CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "postgis_topology";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

SELECT topology.CreateTopology(${topo_schema},${srid}, ${tolerance});

CREATE SCHEMA IF NOT EXISTS ${data_schema~};
