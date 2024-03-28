/*
Functions allowing changes to topological relations
// Should merge with similar functions for Naukluft
*/

CREATE OR REPLACE FUNCTION {topo_schema}.__map_face_layer_id()
RETURNS integer AS $$
SELECT layer_id
FROM topology.layer
WHERE schema_name=:topo_name 
  AND table_name='map_face'
  AND feature_column='topo';
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION {topo_schema}.topologizeGeometry(geom geometry, tolerance numeric = 1)
RETURNS topology.topogeometry AS
$$
DECLARE
topo topology.topogeometry;
layer_id integer;
BEGIN
  SELECT layer_id
      INTO layer_id
      FROM topology.layer
      WHERE schema_name=:topo_name 
      AND table_name='contact';

  topo := topology.toTopoGeom(geom, :topo_name , layer_id, tolerance); -- 10 cm tolerance
  RAISE NOTICE 'Added geometry';
  RETURN topo;
EXCEPTION WHEN others THEN
  RAISE NOTICE 'Error code: %', SQLSTATE;
  RAISE NOTICE 'Error message: %', SQLERRM;
  RETURN null;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE OR REPLACE FUNCTION {topo_schema}.addMapFace(geom geometry, tolerance numeric = 1)
RETURNS topology.topogeometry AS
$$
DECLARE
topo topology.topogeometry;
layer_id integer;
BEGIN
  SELECT l.layer_id
      INTO layer_id
      FROM topology.layer l
      WHERE schema_name=  :topo_name 
      AND table_name='map_face';

  topo := topology.toTopoGeom(geom, :topo_name , layer_id, tolerance); -- 10 cm tolerance
  RAISE NOTICE 'Added map face';
  RETURN topo;
EXCEPTION WHEN others THEN
  RAISE NOTICE 'Error code: %', SQLSTATE;
  RAISE NOTICE 'Error message: %', SQLERRM;
  RETURN null;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE OR REPLACE FUNCTION {topo_schema}.removeNodeMaybe(node_id integer)
RETURNS boolean AS
$$
DECLARE
edge_id int[];
len int;
outnode int;
BEGIN
  SELECT
    abs((GetNodeEdges(  :topo_name , node_id)).edge) edge_id
  INTO edge_id
  FROM {topo_schema}.edge;

  len := array_length(edge_id);

  IF len = 2 THEN
    outnode := ST_ModEdgeHeal(:topo_name ,edge_id[1], edge_id[2]);
    RETURN true;
  ELSIF len = 0 THEN
    outnode := ST_RemIsoNode(:topo_name , node_id);
    RETURN true;
  END IF;
  RETURN false;
EXCEPTION WHEN others THEN
  RETURN false;
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION {topo_schema}.removeEdgeMaybe(eid integer)
RETURNS integer AS
$$
DECLARE
fid integer;
BEGIN
  RETURN ST_RemEdgeModFace(:topo_name , eid);
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
CREATE OR REPLACE FUNCTION {topo_schema}.unitForArea(face geometry, map_layer integer)
RETURNS text AS $$
DECLARE result text;
BEGIN
-- Get polygons in requisite topology
WITH polygon AS (
SELECT
  p.id,
  p.type,
  p.geometry
FROM {data_schema}.polygon p
JOIN {data_schema}.polygon_type t
  ON p.type = t.id
JOIN {data_schema}.map_layer l
  ON p.map_layer = l.id
WHERE l.id = map_layer
  AND l.topological
  AND ST_Contains(face, p.geometry)
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

CREATE OR REPLACE FUNCTION {topo_schema}.unitForFace(face_id integer, map_layer integer)
RETURNS text AS $$
SELECT
  unit_id
FROM {topo_schema}.relation r
JOIN {topo_schema}.map_face f
  ON (f.topo).id = r.topogeo_id
WHERE element_id = $1
  AND element_type = 3
  AND r.layer_id = {topo_schema}.__map_face_layer_id()
  AND f.map_layer = $2;
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION {topo_schema}.containing_face(face_id integer, map_layer integer)
RETURNS {topo_schema}.map_face AS $$
SELECT f.*
FROM {topo_schema}.relation r
JOIN {topo_schema}.map_face f
  ON (f.topo).id = r.topogeo_id
WHERE element_id = $1
  AND element_type = 3
  AND r.layer_id = {topo_schema}.__map_face_layer_id()
  AND f.map_layer = $2;
$$ LANGUAGE SQL IMMUTABLE;
