/*
Functions allowing changes to topological relations
// Should merge with similar functions for Naukluft
*/

CREATE OR REPLACE FUNCTION map_topology.topologizeGeometry(geom geometry, tolerance numeric = 1)
RETURNS topogeometry AS
$$
DECLARE
topo topogeometry;
layer_id integer;
BEGIN
  SELECT layer_id
      INTO layer_id
      FROM topology.layer
      WHERE schema_name='map_topology'
      AND table_name='contact';

  topo := topology.toTopoGeom(geom, 'map_topology', layer_id, tolerance); -- 10 cm tolerance
  RAISE NOTICE 'Added geometry';
  RETURN topo;
EXCEPTION WHEN others THEN
  RAISE NOTICE 'Error code: %', SQLSTATE;
  RAISE NOTICE 'Error message: %', SQLERRM;
  RETURN null;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE OR REPLACE FUNCTION map_topology.removeNodeMaybe(node_id integer)
RETURNS boolean AS
$$
DECLARE
edge_id int[];
len int;
outnode int;
BEGIN
  SELECT
    abs((GetNodeEdges('map_topology', node_id)).edge) edge_id
  INTO edge_id
  FROM map_topology.edge;

  len := array_length(edge_id);

  IF len = 2 THEN
    outnode := ST_ModEdgeHeal('map_topology',edge_id[1], edge_id[2]);
    RETURN true;
  ELSIF len = 0 THEN
    outnode := ST_RemIsoNode('map_topology', node_id);
    RETURN true;
  END IF;
  RETURN false;
EXCEPTION WHEN others THEN
  RAISE NOTICE 'Error code: %', SQLSTATE;
  RAISE NOTICE 'Error message: %', SQLERRM;
  RETURN false;
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION map_topology.removeEdgeMaybe(eid integer)
RETURNS boolean AS
$$
DECLARE
fid integer;
BEGIN
  fid := ST_RemEdgeModFace('map_topology', eid);
  RETURN true;
EXCEPTION WHEN others THEN
  RAISE NOTICE 'Error code: %', SQLSTATE;
  RAISE NOTICE 'Error message: %', SQLERRM;
  RETURN false;
END
$$
LANGUAGE 'plpgsql';


