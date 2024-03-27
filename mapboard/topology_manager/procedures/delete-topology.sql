/* Procedure to delete topology without affecting
mapping data stored in `data_schema`. */

SELECT topology.DropTopoGeometryColumn(:data_schema_name, 'linework', 'topo');
SELECT topology.DropTopology(:topo_name);

UPDATE {data_schema}.linework SET geometry_hash = null;
