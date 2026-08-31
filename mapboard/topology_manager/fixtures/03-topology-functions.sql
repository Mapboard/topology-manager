/*
Functions allowing changes to topological relations
// Should merge with similar functions for Naukluft
*/

CREATE OR REPLACE FUNCTION {topo_schema}.__map_face_layer_id()
RETURNS integer AS $$
SELECT layer_id
FROM topology.layer
WHERE schema_name={topo_name_literal}
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
      WHERE schema_name={topo_name_literal}
      AND table_name='contact';

  topo := topology.toTopoGeom(geom, {topo_name_literal} , layer_id, tolerance); -- 10 cm tolerance
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
      WHERE schema_name={topo_name_literal}
      AND table_name='map_face';

  topo := topology.toTopoGeom(geom, {topo_name_literal} , layer_id, tolerance); -- 10 cm tolerance
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
    abs((GetNodeEdges({topo_name_literal} , node_id)).edge) edge_id
  INTO edge_id
  FROM {topo_schema}.edge;

  len := array_length(edge_id);

  IF len = 2 THEN
    outnode := ST_ModEdgeHeal({topo_name_literal},edge_id[1], edge_id[2]);
    RETURN true;
  ELSIF len = 0 THEN
    outnode := ST_RemIsoNode({topo_name_literal} , node_id);
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
  RETURN ST_RemEdgeModFace({topo_name_literal} , eid);
EXCEPTION WHEN others THEN
  RAISE NOTICE 'Error code: %', SQLSTATE;
  RAISE NOTICE 'Error message: %', SQLERRM;
  RETURN NULL;
END;
$$
LANGUAGE 'plpgsql';


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

CREATE OR REPLACE FUNCTION {topo_schema}.parent_map_layers(
  _map_layer integer,
  _topological boolean DEFAULT true
)
RETURNS setof integer AS $$
WITH RECURSIVE r AS (
SELECT
  id,
  parent
FROM {data_schema}.map_layer
WHERE id = _map_layer
  AND CASE WHEN _topological THEN topological ELSE true END
UNION
SELECT
  ml.id,
  ml.parent
FROM {data_schema}.map_layer ml
JOIN r
  ON ml.id = r.parent
  AND CASE WHEN _topological THEN ml.topological ELSE true END
)
SELECT id FROM r;
$$ LANGUAGE SQL IMMUTABLE;

/** Every layer whose boundaries constrain a dissolve of `_map_layer`.

  Two relations feed this, and they run in opposite directions:

  - `map_layer.parent` -- a child inherits its ancestors' linework as barriers.
  - `map_layer_composition` -- a composite layer draws its content from its
    members, so its faces must not span a contact that exists in one of them.

  Both are "from the current layer, reach the next one", so a single recursive
  walk over the union of the two edge sets covers them (and picks up the
  ancestors of composition members, which constrain those members in turn).

  Until composite layers are solved by dissolving rather than filled by overlay,
  the composition half is inert: only composite layers have members, and those
  are never passed to the dissolve.
*/
CREATE OR REPLACE FUNCTION {topo_schema}.constraining_layers(
  _map_layer integer,
  _topological boolean DEFAULT true
)
RETURNS setof integer AS $$
WITH RECURSIVE edges AS (
  SELECT id AS src, parent AS dst
  FROM {data_schema}.map_layer
  WHERE parent IS NOT NULL
  UNION ALL
  SELECT parent_id AS src, member_id AS dst
  FROM {data_schema}.map_layer_composition
), r AS (
  SELECT id
  FROM {data_schema}.map_layer
  WHERE id = _map_layer
    AND CASE WHEN _topological THEN topological ELSE true END
  UNION
  SELECT ml.id
  FROM r
  JOIN edges e ON e.src = r.id
  JOIN {data_schema}.map_layer ml
    ON ml.id = e.dst
   AND CASE WHEN _topological THEN ml.topological ELSE true END
)
SELECT id FROM r;
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION {topo_schema}.child_map_layers(
  _map_layer integer,
  _topological boolean DEFAULT true
)
RETURNS setof integer AS $$
WITH RECURSIVE r AS (
SELECT
  id,
  parent
FROM {data_schema}.map_layer
WHERE id = _map_layer
  AND CASE WHEN _topological THEN topological ELSE true END
UNION
SELECT
  ml.id,
  ml.parent
FROM {data_schema}.map_layer ml
JOIN r
  ON ml.parent = r.id
  AND CASE WHEN _topological THEN ml.topological ELSE true END
)
SELECT id FROM r;
$$ LANGUAGE SQL IMMUTABLE;
