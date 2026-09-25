/*
Server-side face-update loop (the `plpgsql` engine).

`update_dirty_faces` drains `dirty_face` for one layer in a single call, up to a
chunk limit: dissolve the next dirty primitive's component, persist it with the
requested mode (`move` → map_face_absorb / map_face_release, `replace` →
map_face_replace), un-mark the component, repeat. It is the same algorithm as
the Python loop (`commands/update_faces/loop.py`) with `dirty_face` itself as the
queue — primitives re-marked by a shed are simply picked up by a later
iteration — so a chunk costs one network round trip instead of two per
component. The Python side calls this until nothing is left, which keeps
checkpointing (commit per chunk) and progress reporting.
*/

DROP TYPE IF EXISTS {topo_schema}.face_update_stats CASCADE;
CREATE TYPE {topo_schema}.face_update_stats AS (
  components integer,   -- components persisted in this call
  created integer,      -- map faces created
  updated integer,      -- existing map faces that absorbed a component
  deleted integer,      -- map faces deleted
  shed integer,         -- map faces that lost primitives and survive
  reseeded integer,     -- primitives re-marked dirty by sheds
  remaining integer     -- dirty primitives left in the layer afterwards
);

-- The 3-argument form would otherwise remain and make a 3-argument call ambiguous.
DROP FUNCTION IF EXISTS {topo_schema}.update_dirty_faces(integer, text, integer);

CREATE OR REPLACE FUNCTION {topo_schema}.update_dirty_faces(
  _map_layer integer,
  _mode text DEFAULT 'move',
  _limit integer DEFAULT 100,
  -- Refill the identity cache. The caller sets this false for every chunk after
  -- the first of a layer: identity does not change while faces are persisted, so
  -- one fill serves the whole layer. Refilling per chunk costs a whole-layer
  -- resolve (~180 ms on a 214k-face layer), which is most of a small chunk.
  _refresh_identity boolean DEFAULT true
)
RETURNS {topo_schema}.face_update_stats AS $$
DECLARE
  _seed integer;
  _faces integer[];
  _change {topo_schema}.map_face_change;
  _stats {topo_schema}.face_update_stats;
  _cached boolean := {bulk_identity};
BEGIN
  IF _mode NOT IN ('move', 'replace') THEN
    RAISE EXCEPTION 'Unknown face update mode %', _mode;
  END IF;

  -- Strategies that offer `resolve_layer_identity` get their identities cached
  -- once per chunk, so the walk compares cached values instead of calling
  -- `faces_are_joinable` per edge (see `dissolve_groups`). Identity does not
  -- change while faces are persisted, so the cache holds for the whole chunk.
  CREATE TEMP TABLE IF NOT EXISTS _layer_identity (
    face_id integer PRIMARY KEY,
    identity text
  );
  IF _cached AND _refresh_identity THEN
    PERFORM {topo_schema}.prepare_layer_identity(_map_layer);
  END IF;

  _stats.components := 0;
  _stats.created := 0;
  _stats.updated := 0;
  _stats.deleted := 0;
  _stats.shed := 0;
  _stats.reseeded := 0;

  WHILE _stats.components < _limit LOOP
    -- The universal face first (it only releases), then by id for determinism
    SELECT id INTO _seed
    FROM {topo_schema}.dirty_face
    WHERE map_layer = _map_layer
    ORDER BY id
    LIMIT 1;
    EXIT WHEN NOT FOUND;

    SELECT faces INTO _faces
    FROM {topo_schema}.dissolve_component(_seed, _map_layer, ARRAY[]::integer[], _cached);

    IF _mode = 'move' THEN
      IF 0 = ANY(_faces) THEN
        _change := {topo_schema}.map_face_release(_faces, _map_layer);
      ELSE
        _change := {topo_schema}.map_face_absorb(_faces, _map_layer, _cached);
      END IF;
    ELSE
      _change := {topo_schema}.map_face_replace(_faces, _map_layer, NOT (0 = ANY(_faces)), _cached);
    END IF;

    -- The component is settled; re-seeded primitives lie outside it and stay dirty
    DELETE FROM {topo_schema}.dirty_face
    WHERE map_layer = _map_layer AND (id = ANY(_faces) OR id = 0);

    _stats.components := _stats.components + 1;
    IF _change.created THEN
      _stats.created := _stats.created + 1;
    ELSIF _change.map_face IS NOT NULL THEN
      _stats.updated := _stats.updated + 1;
    END IF;
    _stats.deleted := _stats.deleted + coalesce(cardinality(_change.deleted), 0);
    _stats.shed := _stats.shed + coalesce(cardinality(_change.shed), 0);
    _stats.reseeded := _stats.reseeded + coalesce(cardinality(_change.reseeded), 0);
  END LOOP;

  SELECT count(*)::integer INTO _stats.remaining
  FROM {topo_schema}.dirty_face WHERE map_layer = _map_layer;
  RETURN _stats;
END;
$$ LANGUAGE plpgsql;
