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
  RETURN false;
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION map_topology.removeEdgeMaybe(eid integer)
RETURNS integer AS
$$
DECLARE
fid integer;
BEGIN
  RETURN ST_RemEdgeModFace('map_topology', eid);
EXCEPTION WHEN others THEN
  RAISE NOTICE 'Error code: %', SQLSTATE;
  RAISE NOTICE 'Error message: %', SQLERRM;
  RETURN NULL;
END;
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

CREATE OR REPLACE FUNCTION map_topology.healEdges()
RETURNS void AS $$
DECLARE
  __healed_edge integer;
  __edges integer[];
  __c1 integer;
  __c2 integer;
BEGIN

__healed_edge := 0;

WHILE (__healed_edge IS NOT null) LOOP

SELECT
  ST_ModEdgeHeal('map_topology', edges[1], edges[2])
INTO __healed_edge
FROM map_topology.node_edge
WHERE n_edges = 2
  AND edges[1] != edges[2]
  AND (SELECT contact_id
       FROM map_topology.edge_contact
       WHERE edge_id = edges[1]) = (SELECT contact_id
       FROM map_topology.edge_contact WHERE edge_id = edges[2])
LIMIT 1;

END LOOP;

END
$$ LANGUAGE plpgsql;
