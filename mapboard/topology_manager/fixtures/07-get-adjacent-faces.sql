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
  constraining integer[];
BEGIN
  constraining := array(
    SELECT DISTINCT ON (id) {topo_schema}.constraining_layers(lyr.id) AS id
    FROM unnest(boundary_layers) AS lyr(id)
  );

  RETURN NOT (edge_layers && constraining)
      OR array_length(edge_layers, 1) = 0
      OR array_length(constraining, 1) = 0;
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
  _barrier_layers integer[] DEFAULT ARRAY[]::integer[],
  -- Read joinability from `_layer_identity` rather than calling
  -- `faces_are_joinable` per edge. Only `dissolve_groups` sets this, because only
  -- it populates the cache; a standalone caller keeps the per-edge path.
  _use_identity_cache boolean DEFAULT false
)
RETURNS TABLE (faces integer[], existing_map_faces integer[], niter integer, map_layer integer)
AS $$
DECLARE
  _added integer;
  _niter integer := 0;
  _constraining integer[];
BEGIN
  -- Session-scoped scratch sets, reused across calls (the caller commits per
  -- component, so deliberately no ON COMMIT DROP).
  CREATE TEMP TABLE IF NOT EXISTS _component     (face_id integer PRIMARY KEY);
  CREATE TEMP TABLE IF NOT EXISTS _frontier      (face_id integer PRIMARY KEY);
  CREATE TEMP TABLE IF NOT EXISTS _frontier_next (face_id integer PRIMARY KEY);
  -- Populated per layer by `dissolve_groups`; created here so the frontier query
  -- plans whether or not the cache is in use.
  CREATE TEMP TABLE IF NOT EXISTS _layer_identity (
    face_id integer PRIMARY KEY,
    identity text
  );
  TRUNCATE _component, _frontier, _frontier_next;

  INSERT INTO _component VALUES (_seed);
  INSERT INTO _frontier  VALUES (_seed);
  _constraining := array(
    SELECT DISTINCT p.id
    FROM unnest(ARRAY[_map_layer]::integer[] || _barrier_layers) AS lyr(id)
    CROSS JOIN LATERAL {topo_schema}.constraining_layers(lyr.id) AS p(id)
  );

  LOOP
    -- Newly-reached joinable neighbors of the current frontier. The joins to
    -- _frontier drive index scans on edge_data.left_face/right_face; the
    -- anti-join against _component (PK) keeps us from revisiting.
    TRUNCATE _frontier_next;
    INSERT INTO _frontier_next (face_id)
    SELECT DISTINCT j.opp_face
    FROM (
      SELECT
        fe.opp_face,
        fe.left_face,
        fe.right_face,
        array_remove(array_agg(er.map_layer), null) edge_layers
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
      LEFT JOIN _component c ON c.face_id = fe.opp_face
      LEFT JOIN {topo_schema}.__edge_relation er ON er.edge_id = fe.edge_id
      WHERE c.face_id IS NULL
      GROUP BY fe.edge_id, fe.left_face, fe.right_face, fe.opp_face
    ) j
    LEFT JOIN _layer_identity il ON _use_identity_cache AND il.face_id = j.left_face
    LEFT JOIN _layer_identity ir ON _use_identity_cache AND ir.face_id = j.right_face
    WHERE (
            NOT (j.edge_layers && _constraining)
         OR array_length(j.edge_layers, 1) = 0
         OR array_length(_constraining, 1) = 0
          )
       OR CASE
            WHEN _use_identity_cache
              THEN il.identity IS NOT DISTINCT FROM ir.identity
            ELSE {topo_schema}.faces_are_joinable(
                   j.left_face, j.right_face, _map_layer)
          END;

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


/** Dissolve every dirty face in a layer, one component at a time, server-side.

  The same expansion `dissolve_component` performs -- this only moves the *loop*
  into the database. That matters because the caller was making one round trip per
  dirty face, and dirty sets run to tens of thousands: a third of a real topology's
  faces or more after a bulk update. Round-tripping each one left the database idle
  waiting on the client for a third of its time.

  Deliberately not whole-layer label propagation over `joinable_face_edges`, which
  would converge in as many iterations as the graph is wide -- a component spanning
  a continent is thousands of hops. Per-component BFS stays proportional to the
  component.

  `_max_groups` bounds how many components one call returns, so the caller can
  still persist and checkpoint in batches. Persisting unmarks those faces, so the
  next call simply sees a smaller dirty set. NULL means "all of them".
*/
CREATE OR REPLACE FUNCTION {topo_schema}.dissolve_groups(
  _map_layer integer,
  _barrier_layers integer[] DEFAULT ARRAY[]::integer[],
  _max_groups integer DEFAULT NULL
)
RETURNS TABLE (faces integer[], existing_map_faces integer[], niter integer, map_layer integer)
AS $$
DECLARE
  _seed integer;
  _groups integer := 0;
  _r record;
  _cached boolean := {bulk_identity};
BEGIN
  -- Faces already claimed by a component returned from *this* call. A separate
  -- name from `dissolve_component`'s scratch sets, which it truncates per call.
  CREATE TEMP TABLE IF NOT EXISTS _claimed (face_id integer PRIMARY KEY);
  TRUNCATE _claimed;

  /* Resolve every face's identity for this layer once.

     `faces_are_joinable` is evaluated per candidate edge, so without this each
     face's identity is re-resolved once per incident edge -- around six times
     over in a planar graph, and twice that because BFS reaches each edge from
     both ends. Where the strategy offers a set-oriented form, the whole layer
     costs about as much as a few hundred individual lookups.

     Only strategies that opt in have `resolve_layer_identity`; the rest keep the
     per-edge path, which is what `search` wants anyway -- its `faces_are_joinable`
     is a no-op, so there is nothing to cache. */
  CREATE TEMP TABLE IF NOT EXISTS _layer_identity (
    face_id integer PRIMARY KEY,
    identity text
  );
  IF _cached THEN
    TRUNCATE _layer_identity;
    INSERT INTO _layer_identity (face_id, identity)
    SELECT face_id, identity
    FROM {topo_schema}.resolve_layer_identity(_map_layer);
    ANALYZE _layer_identity;
  END IF;

  FOR _seed IN
    SELECT d.id
    FROM {topo_schema}.dirty_face d
    WHERE d.map_layer = _map_layer
    ORDER BY d.id
  LOOP
    EXIT WHEN _max_groups IS NOT NULL AND _groups >= _max_groups;
    -- Another seed already pulled this face into its component.
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM _claimed c WHERE c.face_id = _seed
    );

    SELECT * INTO _r
    FROM {topo_schema}.dissolve_component(
      _seed, _map_layer, _barrier_layers, _cached);

    INSERT INTO _claimed (face_id)
    SELECT unnest(_r.faces)
    ON CONFLICT DO NOTHING;

    faces := _r.faces;
    existing_map_faces := _r.existing_map_faces;
    niter := _r.niter;
    map_layer := _map_layer;
    _groups := _groups + 1;
    RETURN NEXT;
  END LOOP;
END;
$$ LANGUAGE plpgsql;


/** Get faces that can be dissolved into a given map layer */
CREATE OR REPLACE FUNCTION {topo_schema}.adjacent_faces(
  face_id integer,
  _map_layer integer
)
  RETURNS integer[]
AS $$
SELECT ({topo_schema}.dissolve_component(face_id, _map_layer)).faces
$$ LANGUAGE SQL STABLE;
