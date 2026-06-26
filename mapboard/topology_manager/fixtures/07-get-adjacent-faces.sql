/*
This is the core algorithm that accumulates topology faces
into a map layer, starting from a given face_id.

Right now this works separately for each map layer,
but we might find optimizations by separately handling
nested map layers.

Potential alternate algorithm:

1. get overlapping map faces
2. split on new geometry
3. if original geometry is the same, leave alone
    (for partial overlaps)
4. else,
5. check if any edges do not have a face associated
  build them up the previous way.


*/

/*
A materialized view to store relationships between faces,
which saves ~0.5s per query. This is updated by default
but this can be disabled for speed.

Drastically simplified this view creation
*/

CREATE OR REPLACE FUNCTION {topo_schema}.opposite_face(
  edge {topo_schema}.edge_data,
  face_id integer
)
RETURNS integer
AS $$
SELECT CASE
  WHEN edge.left_face = face_id THEN edge.right_face
  WHEN edge.right_face = face_id THEN edge.left_face
  ELSE null
END
$$ LANGUAGE SQL IMMUTABLE;

DROP TYPE IF EXISTS {topo_schema}.face_group CASCADE;
CREATE TYPE {topo_schema}.face_group AS (
  faces integer[],
  niter integer,
  map_layer integer
);

CREATE OR REPLACE FUNCTION {topo_schema}.layers_are_joinable(
  boundary_layers integer[],
  edge_layers integer[]
)
RETURNS boolean
AS $$
DECLARE
  boundary_layers_with_parents integer[];
BEGIN
  boundary_layers_with_parents := array(
    SELECT DISTINCT ON (id) {topo_schema}.parent_map_layers(lyr.id) AS id
    FROM unnest(boundary_layers) AS lyr(id)
  );

  RETURN NOT (edge_layers && boundary_layers_with_parents)
      OR array_length(edge_layers, 1) = 0
      OR array_length(boundary_layers_with_parents, 1) = 0;
END;
$$ LANGUAGE plpgsql;


/** The joinable face-adjacency graph for a map layer.

Pairs of primitive faces that share an edge which is *not* a barrier (or whose
faces share an identity). This depends only on the map layer, not on any seed
face, so it can be computed once and traversed for many faces (e.g. a single
connected-components pass over a whole batch of dirty faces). */
CREATE OR REPLACE FUNCTION {topo_schema}.joinable_face_edges(
  _map_layer integer,
  _barrier_layers integer[] DEFAULT ARRAY[]::integer[]
)
RETURNS TABLE (left_face integer, right_face integer)
AS $$
  WITH edge_groups AS (
    SELECT
      e.edge_id,
      e.left_face,
      e.right_face,
      array_remove(array_agg(er.map_layer), null) layers
    FROM {topo_schema}.edge_data e
    LEFT JOIN {topo_schema}.__edge_relation er
      ON er.edge_id = e.edge_id
    WHERE e.left_face != e.right_face
    GROUP BY e.edge_id, e.left_face, e.right_face
  )
  SELECT
    eg.left_face,
    eg.right_face
  FROM edge_groups eg
  -- An edge can be crossed if it is not a barrier *or* the two faces share an
  -- identity. For lineal boundaries (contacts) `faces_are_joinable` is a no-op
  -- (returns false), so this reduces to `layers_are_joinable` — a contact
  -- blocks the join. For areal boundaries a map's footprint edge sets
  -- `layers_are_joinable` false, but same-identity faces still join via
  -- `faces_are_joinable`, so higher-priority maps act as the real barriers.
  WHERE {topo_schema}.layers_are_joinable(
      ARRAY[_map_layer]::integer[] || _barrier_layers,
      eg.layers
    )
    OR {topo_schema}.faces_are_joinable(eg.left_face, eg.right_face, _map_layer);
$$ LANGUAGE SQL STABLE;


CREATE OR REPLACE FUNCTION {topo_schema}.get_adjacent_faces_core(
  face_id integer,
  _map_layer integer,
  _barrier_layers integer[] DEFAULT ARRAY[]::integer[]
)
RETURNS {topo_schema}.face_group
AS $$
WITH RECURSIVE
  je AS (
    SELECT left_face, right_face
    FROM {topo_schema}.joinable_face_edges(_map_layer, _barrier_layers)
  ),
  face_adjacency AS (
    SELECT left_face this_face, right_face opp_face FROM je
    UNION
    SELECT right_face, left_face FROM je
  ),
  r(faces, edge_faces, depth) AS (
    /** This recursive query works outwards as a 'wave',
    * starting from the given face_id and moving outwards
      accumulating adjacent faces in a given map layer
      until there are no more to find.

      We should stop when we reach the global face, but we don't do this now.

      This works on face primitives but a similar approach
      could accumulate based on child topogeometries, for layers
      with child topological layers...
     */
    SELECT
      ARRAY[]::integer[] AS faces,
      ARRAY[face_id] edge_faces,
      0 AS depth
    UNION ALL
    SELECT
      r.faces || r.edge_faces faces,
      array(
        SELECT opp_face
        FROM face_adjacency fa
        WHERE fa.this_face = ANY(r.edge_faces)
        AND NOT fa.opp_face = ANY(r.faces || r.edge_faces)
      ) AS edge_faces,
      r.depth + 1
    FROM r
    WHERE array_length(r.edge_faces, 1) > 0
    GROUP BY r.faces, r.edge_faces, r.depth
  )
SELECT faces, depth niter, _map_layer map_layer
FROM r
ORDER BY depth DESC
LIMIT 1;
$$ LANGUAGE SQL STABLE;


/** Get faces that can be dissolved into a given map layer */
CREATE OR REPLACE FUNCTION {topo_schema}.adjacent_faces(
  face_id integer,
  _map_layer integer
)
RETURNS integer[]
AS $$
  SELECT ({topo_schema}.get_adjacent_faces_core(face_id, _map_layer)).faces
$$ LANGUAGE SQL STABLE;


/** Dissolve groups for every dirty face in a map layer.

Returns one row per connected component (in the joinable face graph) that
contains a dirty face: the full set of primitive faces in the group, and the
existing map_faces those primitives currently belong to (which the caller
replaces). The joinable adjacency is built once into an indexed temp table and
each component is expanded with a recursive walk, so the cost is O(edges) for the
whole layer rather than O(edges x groups) — the per-seed graph rebuild is gone.
*/
CREATE OR REPLACE FUNCTION {topo_schema}.dissolve_groups(
  _map_layer integer,
  _barrier_layers integer[] DEFAULT ARRAY[]::integer[]
)
RETURNS TABLE (faces integer[], existing_map_faces integer[])
AS $$
DECLARE
  _seed integer;
  _component integer[];
BEGIN
  -- Joinable adjacency for the layer, computed once (both directions, indexed).
  DROP TABLE IF EXISTS _dissolve_adj;
  CREATE TEMP TABLE _dissolve_adj AS
    SELECT j.left_face AS this_face, j.right_face AS opp_face
      FROM {topo_schema}.joinable_face_edges(_map_layer, _barrier_layers) j
    UNION
    SELECT j.right_face, j.left_face
      FROM {topo_schema}.joinable_face_edges(_map_layer, _barrier_layers) j;
  CREATE INDEX ON _dissolve_adj (this_face);

  -- Outstanding dirty faces for this layer.
  DROP TABLE IF EXISTS _dissolve_todo;
  CREATE TEMP TABLE _dissolve_todo AS
    SELECT id FROM {topo_schema}.dirty_face WHERE map_layer = _map_layer;

  LOOP
    SELECT id INTO _seed FROM _dissolve_todo LIMIT 1;
    EXIT WHEN NOT FOUND;

    -- Connected component reachable from the seed.
    WITH RECURSIVE walk(face) AS (
      SELECT _seed
      UNION
      SELECT a.opp_face
      FROM _dissolve_adj a
      JOIN walk w ON a.this_face = w.face
    )
    SELECT array_agg(face) INTO _component FROM walk;

    -- This group's dirty faces are now handled.
    DELETE FROM _dissolve_todo WHERE id = ANY(_component);

    faces := _component;
    SELECT coalesce(array_agg(DISTINCT f.id), ARRAY[]::integer[])
    INTO existing_map_faces
    FROM {topo_schema}.map_face f
    JOIN {topo_schema}.relation r
      ON (f.topo).id = r.topogeo_id
     AND r.layer_id = (f.topo).layer_id
    WHERE r.element_id = ANY(_component)
      AND r.element_type = 3
      AND f.map_layer = _map_layer;
    RETURN NEXT;
  END LOOP;

  DROP TABLE IF EXISTS _dissolve_adj;
  DROP TABLE IF EXISTS _dissolve_todo;
END;
$$ LANGUAGE plpgsql;

/** Dissolve a single joinable component, expanded lazily outward from a seed
face. Unlike dissolve_groups (which builds the whole layer's adjacency up front),
this touches only edges incident to faces already reached, so its cost is
proportional to the component, not the layer — the right shape for incremental,
dirty-face-driven updates where the caller loops one component at a time. Returns
the component's primitive faces and the existing map_faces they replace.
Membership is held in indexed temp tables so large components stay efficient. */
CREATE OR REPLACE FUNCTION {topo_schema}.dissolve_component(
  _seed integer,
  _map_layer integer,
  _barrier_layers integer[] DEFAULT ARRAY[]::integer[]
)
RETURNS TABLE (faces integer[], existing_map_faces integer[], niter integer, map_layer integer)
AS $$
DECLARE
  _added integer;
  _niter integer := 0;
BEGIN
  -- Session-scoped scratch sets, reused across calls (the caller commits per
  -- component, so deliberately no ON COMMIT DROP).
  CREATE TEMP TABLE IF NOT EXISTS _component     (face_id integer PRIMARY KEY);
  CREATE TEMP TABLE IF NOT EXISTS _frontier      (face_id integer PRIMARY KEY);
  CREATE TEMP TABLE IF NOT EXISTS _frontier_next (face_id integer PRIMARY KEY);
  TRUNCATE _component, _frontier, _frontier_next;

  INSERT INTO _component VALUES (_seed);
  INSERT INTO _frontier  VALUES (_seed);

  LOOP
    -- Newly-reached joinable neighbors of the current frontier. The joins to
    -- _frontier drive index scans on edge_data.left_face/right_face; the
    -- anti-join against _component (PK) keeps us from revisiting.
    TRUNCATE _frontier_next;
    INSERT INTO _frontier_next (face_id)
    SELECT DISTINCT j.opp_face
    FROM (
      SELECT fe.opp_face, fe.left_face, fe.right_face
      FROM (
        SELECT e.edge_id, e.left_face, e.right_face, e.right_face AS opp_face
        FROM {topo_schema}.edge_data e
        JOIN _frontier f ON e.left_face = f.face_id
        WHERE e.left_face <> e.right_face
        UNION ALL
        SELECT e.edge_id, e.left_face, e.right_face, e.left_face AS opp_face
        FROM {topo_schema}.edge_data e
        JOIN _frontier f ON e.right_face = f.face_id
        WHERE e.left_face <> e.right_face
      ) fe
      LEFT JOIN {topo_schema}.__edge_relation er ON er.edge_id = fe.edge_id
      GROUP BY fe.edge_id, fe.left_face, fe.right_face, fe.opp_face
      HAVING {topo_schema}.layers_are_joinable(
               ARRAY[_map_layer]::integer[] || _barrier_layers,
               array_remove(array_agg(er.map_layer), null))
          OR {topo_schema}.faces_are_joinable(fe.left_face, fe.right_face, _map_layer)
    ) j
    LEFT JOIN _component c ON c.face_id = j.opp_face
    WHERE c.face_id IS NULL;

    GET DIAGNOSTICS _added = ROW_COUNT;
    EXIT WHEN _added = 0;

    INSERT INTO _component (face_id) SELECT face_id FROM _frontier_next;
    TRUNCATE _frontier;
    INSERT INTO _frontier (face_id) SELECT face_id FROM _frontier_next;

    _niter := _niter + 1;
  END LOOP;

  RETURN QUERY
  SELECT
    (SELECT array_agg(face_id) FROM _component) faces,
    coalesce((
      SELECT array_agg(DISTINCT f.id)
      FROM {topo_schema}.map_face f
      JOIN {topo_schema}.relation r
        ON (f.topo).id = r.topogeo_id AND r.layer_id = (f.topo).layer_id
      WHERE r.element_id IN (SELECT face_id FROM _component)
        AND r.element_type = 3
        AND f.map_layer = _map_layer
    ), ARRAY[]::integer[]) existing_map_faces,
    _niter niter,
    _map_layer map_layer;
END;
$$ LANGUAGE plpgsql;
