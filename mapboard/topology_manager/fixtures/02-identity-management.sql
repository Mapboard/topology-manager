/** Unused function
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
 */

CREATE OR REPLACE FUNCTION
  {topo_schema}.register_face_identity(__map_face_id integer)
  RETURNS void AS $$
WITH t AS (
SELECT
  id map_face,
  {face_identity_column} identity,
  map_layer,
  (topo).*
FROM {topo_schema}.map_face
WHERE id = __map_face_id
)
INSERT INTO {topo_schema}.face_identity AS ft
  (face_id, map_face, {face_identity_column}, map_layer)
SELECT
  face_id,
  map_face,
  identity,
  map_layer
FROM t
JOIN {topo_schema}.relation r
  ON r.layer_id = t.layer_id
  AND r.element_type = t.type
  AND r.topogeo_id = t.id
JOIN {topo_schema}.face f
  ON r.element_id = f.face_id
ON CONFLICT (face_id, map_layer)
DO UPDATE SET
  map_face = EXCLUDED.map_face,
  {face_identity_column} = EXCLUDED.{face_identity_column}
WHERE ft.face_id = EXCLUDED.face_id
  AND ft.map_layer = EXCLUDED.map_layer;
$$ LANGUAGE SQL;

