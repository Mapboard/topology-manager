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

CREATE OR REPLACE FUNCTION map_topology.addMapFace(geom geometry, tolerance numeric = 1)
RETURNS topogeometry AS
$$
DECLARE
topo topogeometry;
layer_id integer;
BEGIN
  SELECT l.layer_id
      INTO layer_id
      FROM topology.layer l
      WHERE schema_name='map_topology'
      AND table_name='map_face';

  topo := topology.toTopoGeom(geom, 'map_topology', layer_id, tolerance); -- 10 cm tolerance
  RAISE NOTICE 'Added map face';
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

/*
Get the map face that defines a polygon for a specific topology
*/
CREATE OR REPLACE FUNCTION map_topology.unitForArea(in_face geometry, in_topology text)
RETURNS text AS $$
DECLARE result text;
BEGIN
-- Get polygons in requisite topology
WITH polygon AS (
SELECT
  p.id,
  p.type,
  p.geometry
FROM map_digitizer.polygon p
JOIN map_digitizer.polygon_type t
  ON p.type = t.id
WHERE t.topology = in_topology
  AND ST_Contains(in_face, p.geometry)
)
-- Assign face that has the greatest area of polygons
-- assigned to it within the feature
SELECT
  type
INTO result
FROM polygon
GROUP BY type
ORDER BY ST_Area(ST_Union(geometry)) DESC
LIMIT 1;

RETURN result;
END
$$ LANGUAGE plpgsql;

