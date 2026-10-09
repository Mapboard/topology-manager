/* Procedure to delete topology without affecting
mapping data stored in `data_schema`. */

SELECT topology.DropTopoGeometryColumn(:data_schema_name, {boundary_table_literal}, 'topo');
SELECT topology.DropTopology(:topo_name);

UPDATE {boundary_table} SET geometry_hash = null;
