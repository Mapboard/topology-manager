/* Procedure to delete topology without affecting
mapping data stored in `data_schema`. */

SELECT topology.DropTopoGeometryColumn(${data_schema}, 'linework', 'topo');
SELECT topology.DropTopology(${data_schema});
DROP SCHEMA ${data_schema~} CASCADE;
