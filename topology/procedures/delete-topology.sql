/* Procedure to delete topology without affecting
mapping data stored in `data_schema`. */

SELECT topology.DropTopoGeometryColumn(${data_schema}, 'linework', 'topo');
SELECT topology.DropTopology(${topo_schema});
