/** Edge relations table view

This creates a dynamic, table-based materialized "view" of the
relationships between edges and faces. This is used to speed up
adjacency queries, and is updated by the triggers on the linework
and relation tables.

Boundary features can carry either *edge-based* topogeometries (linework,
`element_type = 2`) or *face-based* topogeometries (map areas / polygons,
`element_type = 3`). In the edge-based case the relation table references the
constituent edges directly. In the face-based case it references faces, and the
edges we care about are the ones on the *exterior* boundary of those faces
(interior edges that merely subdivide a single area are not boundary contacts).
The `__topogeom_edges` helper below normalizes both cases so the rest of the
machinery is identical regardless of the topogeometry type.
*/

-- Some earlier iterations had a view for this...
DROP VIEW IF EXISTS {topo_schema}.__edge_relation_dynamic;
DROP VIEW IF EXISTS {topo_schema}.__edge_relation;
DROP VIEW IF EXISTS {topo_schema}.__edge_relation_base;

/** Return the edge ids that constitute (edge-based) or bound (face-based) a
topogeometry. Using UNION (not UNION ALL) deduplicates the face-based case,
where a single edge can be reached via both its left and right face. */
CREATE OR REPLACE FUNCTION {topo_schema}.__topogeom_edges(
  _topogeo_id integer,
  _topolayer_id integer
)
RETURNS TABLE (edge_id integer) AS $$
  -- Edge-based topogeometries reference their edges directly
  SELECT e.edge_id
  FROM {topo_schema}.relation r
  JOIN {topo_schema}.edge_data e
    ON e.edge_id = abs(r.element_id)
  WHERE r.topogeo_id = _topogeo_id
    AND r.layer_id = _topolayer_id
    AND r.element_type = 2 -- edges
  UNION
  -- Face-based topogeometries reference faces; take only the *exterior*
  -- bounding edges. An interior edge is shared by two faces that both belong
  -- to this topogeometry, so it matches two face relation rows (once via each
  -- face); an exterior edge has only one of its faces in the set and matches a
  -- single row. Dropping edges with a match count > 1 therefore keeps only the
  -- outer boundary of the area.
  SELECT e.edge_id
  FROM {topo_schema}.relation r
  JOIN {topo_schema}.edge_data e
    ON e.left_face = abs(r.element_id)
    OR e.right_face = abs(r.element_id)
  WHERE r.topogeo_id = _topogeo_id
    AND r.layer_id = _topolayer_id
    AND r.element_type = 3 -- faces
  GROUP BY e.edge_id
  HAVING count(*) = 1;
$$ LANGUAGE SQL STABLE;

/** A dynamic view that can store a guide. This is the authoritative definition
of the edge relations; the `__edge_relation` table below caches it. */
CREATE OR REPLACE VIEW {topo_schema}.__edge_relation_dynamic AS
SELECT
  l.id line_id,
  l.map_layer,
  e.edge_id
FROM {boundary_table} l
JOIN {data_schema}.map_layer ml
  ON l.map_layer = ml.id
CROSS JOIN LATERAL {topo_schema}.__topogeom_edges((l.topo).id, (l.topo).layer_id) e
WHERE l.topo IS NOT null
  AND ml.topological;

/** Initially create the table */
CREATE TABLE IF NOT EXISTS {topo_schema}.__edge_relation (
  line_id integer NOT NULL REFERENCES {boundary_table} (id) ON DELETE CASCADE,
  map_layer integer NOT NULL REFERENCES {data_schema}.map_layer(id) ON DELETE CASCADE,
  edge_id integer NOT NULL REFERENCES {topo_schema}.edge_data(edge_id) ON DELETE CASCADE,
  topogeo_id integer NOT NULL,
  topolayer_id integer NOT NULL,
  PRIMARY KEY (line_id, edge_id)
);

/** Create an index to make map-layer lookups faster */
CREATE INDEX IF NOT EXISTS edge_relation_map_layer_idx
ON {topo_schema}.__edge_relation (map_layer);
/** Create an index to make edge_id lookups faster */
CREATE INDEX IF NOT EXISTS edge_relation_edge_id_idx
ON {topo_schema}.__edge_relation (edge_id);

/** Face-based topogeometries whose cached edge relations are stale and need
recomputing. Populated cheaply (O(1) per row) by the deferred
`update_face_edge_relation` trigger and drained by
`rebuild_dirty_edge_relations()`. */
CREATE TABLE IF NOT EXISTS {topo_schema}.__edge_relation_dirty (
  topogeo_id integer NOT NULL,
  topolayer_id integer NOT NULL,
  PRIMARY KEY (topogeo_id, topolayer_id)
);

/** Initial population of the table (mirrors __edge_relation_dynamic) */
INSERT INTO {topo_schema}.__edge_relation (
  line_id,
  map_layer,
  edge_id,
  topogeo_id,
  topolayer_id
)
SELECT
  l.id line_id,
  l.map_layer,
  e.edge_id,
  (l.topo).id topogeo_id,
  (l.topo).layer_id topolayer_id
FROM {boundary_table} l
JOIN {data_schema}.map_layer ml
  ON l.map_layer = ml.id
CROSS JOIN LATERAL {topo_schema}.__topogeom_edges((l.topo).id, (l.topo).layer_id) e
WHERE l.topo IS NOT null
  AND ml.topological
ON CONFLICT DO NOTHING;

/** Update this table based on changes to the "relation" table.

For edge-based topogeometries we can act on the single edge referenced by the
changed relation row. For face-based topogeometries a relation row references a
face, whose set of bounding edges depends on the topology as a whole, so we
recompute the affected boundary feature's relations from scratch (see
`update_face_edge_relation` below). This function handles only the edge case.
*/
CREATE OR REPLACE FUNCTION {topo_schema}.update_edge_relation()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- not sure if we need to delete on update
    DELETE FROM {topo_schema}.__edge_relation
    WHERE edge_id = abs(OLD.element_id)
      AND topolayer_id = OLD.layer_id
      AND topogeo_id = OLD.topogeo_id;

    RETURN OLD;
  END IF;

  RAISE NOTICE 'Updating edge relation table for %', TG_OP;

  -- In all other cases we insert
  INSERT INTO {topo_schema}.__edge_relation (
    line_id,
    map_layer,
    edge_id,
    topogeo_id,
    topolayer_id
  )
  SELECT
    l.id line_id,
    l.map_layer,
    abs(NEW.element_id) edge_id,
    (l.topo).id topogeo_id,
    (l.topo).layer_id topolayer_id
  FROM {boundary_table} l
  WHERE l.topo IS NOT NULL
    AND (l.topo).id = NEW.topogeo_id
    AND (l.topo).layer_id = NEW.layer_id
    AND NEW.element_type = 2
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER update_edge_relation
BEFORE INSERT OR UPDATE
ON {topo_schema}.relation
FOR EACH ROW
WHEN (NEW.element_type = 2)
EXECUTE FUNCTION {topo_schema}.update_edge_relation();

CREATE OR REPLACE TRIGGER delete_edge_relation
BEFORE DELETE
ON {topo_schema}.relation
FOR EACH ROW
WHEN (OLD.element_type = 2)
EXECUTE FUNCTION {topo_schema}.update_edge_relation();

/** Keep edge relations in sync for *face-based* topogeometries — deferred.

A face-based relation row references a face, not an edge, and the edges that
bound a face depend on the topology as a whole, so the affected boundary
feature's relations must be recomputed from scratch. But `toTopoGeom` inserts
one relation row per face a feature covers — thousands for a large map — so
recomputing per row is O(N²) and dominates bulk topology population.

Instead, this trigger only records the touched topogeometry in
`__edge_relation_dirty` (one statement-level insert per statement, boundary
layers only); `rebuild_dirty_edge_relations()` does the scoped recompute once per
affected topogeometry. Callers run that function
after a batch of edits (e.g. at the end of adding a map). The `__edge_relation`
cache is thus eventually consistent — briefly stale between an edit and the
rebuild. */
CREATE OR REPLACE FUNCTION {topo_schema}.update_face_edge_relation()
RETURNS trigger AS $$
BEGIN
  -- Statement-level, with transition tables: one INSERT per statement however
  -- many rows it touched, instead of one per row. Only *boundary* topogeometries
  -- have cached edge relations; `map_face` rows (the bulk of relation traffic --
  -- every createTopoGeom, every primitive moved between faces) are skipped
  -- outright rather than queued and discarded by the rebuild.
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    INSERT INTO {topo_schema}.__edge_relation_dirty (topogeo_id, topolayer_id)
    SELECT DISTINCT n.topogeo_id, n.layer_id
    FROM changed_new n
    WHERE n.element_type = 3
      AND n.layer_id <> {topo_schema}.__map_face_layer_id()
    ON CONFLICT DO NOTHING;
  END IF;
  IF TG_OP IN ('DELETE', 'UPDATE') THEN
    INSERT INTO {topo_schema}.__edge_relation_dirty (topogeo_id, topolayer_id)
    SELECT DISTINCT o.topogeo_id, o.layer_id
    FROM changed_old o
    WHERE o.element_type = 3
      AND o.layer_id <> {topo_schema}.__map_face_layer_id()
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

/** Recompute cached edge relations for every topogeometry marked dirty by
`update_face_edge_relation`, then clear the dirty set. This is the deferred,
batched form of the old per-row recompute: identical logic, but run once per
affected topogeometry instead of once per relation row. It touches only the
dirty boundary features (unlike rebuild-edge-relations.sql, which rebuilds the
whole table). Returns the number of dirty topogeometries processed. */
CREATE OR REPLACE FUNCTION {topo_schema}.rebuild_dirty_edge_relations()
RETURNS integer AS $$
DECLARE
  _n integer;
BEGIN
  SELECT count(*) INTO _n FROM {topo_schema}.__edge_relation_dirty;

  -- Clear existing relations for any boundary feature using a dirty topogeometry
  DELETE FROM {topo_schema}.__edge_relation er
  USING {boundary_table} l, {topo_schema}.__edge_relation_dirty d
  WHERE er.line_id = l.id
    AND (l.topo).id = d.topogeo_id
    AND (l.topo).layer_id = d.topolayer_id;

  -- Recompute them from the current topology
  INSERT INTO {topo_schema}.__edge_relation (
    line_id,
    map_layer,
    edge_id,
    topogeo_id,
    topolayer_id
  )
  SELECT
    l.id line_id,
    l.map_layer,
    e.edge_id,
    (l.topo).id topogeo_id,
    (l.topo).layer_id topolayer_id
  FROM {topo_schema}.__edge_relation_dirty d
  JOIN {boundary_table} l
    ON (l.topo).id = d.topogeo_id
   AND (l.topo).layer_id = d.topolayer_id
  JOIN {data_schema}.map_layer ml
    ON l.map_layer = ml.id
  CROSS JOIN LATERAL {topo_schema}.__topogeom_edges((l.topo).id, (l.topo).layer_id) e
  WHERE l.topo IS NOT null
    AND ml.topological
  ON CONFLICT DO NOTHING;

  DELETE FROM {topo_schema}.__edge_relation_dirty;

  PERFORM {topo_schema}.refresh_dirty_face_edge_relations();
  RETURN _n;
END;
$$ LANGUAGE plpgsql;

/** Re-derive the cached edge relations of the edges around dirty faces.

An edge split by another boundary changes no `relation` row -- a face-based
topogeometry references faces, and splitting an edge splits no face -- so nothing
above queues the boundaries that own the new pieces, and those pieces stay
unregistered: crossable by the dissolve whatever the identities either side.
Every such piece borders a dirty face, because marking a boundary dirties the
faces on both sides of its edges.

So the refresh is local to those edges, not to the boundaries that own them.
For each edge bounding a dirty face, the owners are recomputed exactly as
`__topogeom_edges` defines them -- a face-based boundary owns an edge when one of
its face relations matches the edge's faces -- over both faces of the edge,
which covers a T-junction whose far face was not itself dirtied. Cached rows for
those edges that the recompute does not produce are removed.

Face-based boundaries only: an edge-based one references its edges directly, and
splitting an edge rewrites those relation rows, which the row-level trigger
above already follows. Returns the number of rows added. */
CREATE OR REPLACE FUNCTION {topo_schema}.refresh_dirty_face_edge_relations()
RETURNS integer AS $$
DECLARE
  _n integer;
BEGIN
  -- Session-scoped scratch, reused across calls like the dissolve's
  CREATE TEMP TABLE IF NOT EXISTS _dirty_face_edges (
    edge_id integer PRIMARY KEY,
    left_face integer,
    right_face integer
  );
  CREATE TEMP TABLE IF NOT EXISTS _dirty_face_edge_owners (
    line_id integer,
    map_layer integer,
    edge_id integer,
    topogeo_id integer,
    topolayer_id integer,
    PRIMARY KEY (line_id, edge_id)
  );
  TRUNCATE _dirty_face_edges, _dirty_face_edge_owners;

  -- The universal face is never a seed: every edge on it also bounds a real face,
  -- and seeding from it would pull in the whole outer boundary.
  INSERT INTO _dirty_face_edges (edge_id, left_face, right_face)
  SELECT DISTINCT e.edge_id, e.left_face, e.right_face
  FROM (
    SELECT DISTINCT id FROM {topo_schema}.dirty_face WHERE id <> 0
  ) d
  CROSS JOIN LATERAL (
    SELECT edge_id, left_face, right_face
    FROM {topo_schema}.edge_data WHERE left_face = d.id
    UNION ALL
    SELECT edge_id, left_face, right_face
    FROM {topo_schema}.edge_data WHERE right_face = d.id
  ) e;
  ANALYZE _dirty_face_edges;

  -- `count(*) = 1` is `__topogeom_edges`' own test: an edge matching two of a
  -- boundary's face relations is interior to it.
  --
  -- One equality join per face, not `element_id IN (left_face, right_face)`: the
  -- planner cannot drive `relation_element_id_idx` from that, and nested-looped
  -- every edge against every face relation instead -- 728 ms against 19 ms for a
  -- 1,697-edge layer, growing with the product. DISTINCT keeps an edge with the
  -- same face on both sides counting once, as `__topogeom_edges` does.
  INSERT INTO _dirty_face_edge_owners
  SELECT l.id, l.map_layer, e.edge_id, (l.topo).id, (l.topo).layer_id
  FROM _dirty_face_edges e
  CROSS JOIN LATERAL (
    SELECT DISTINCT face_id FROM (VALUES (e.left_face), (e.right_face)) v(face_id)
  ) f
  JOIN {topo_schema}.relation r
    ON r.element_id = f.face_id
   AND r.element_type = 3
  JOIN {boundary_table} l
    ON (l.topo).id = r.topogeo_id
   AND (l.topo).layer_id = r.layer_id
  JOIN {data_schema}.map_layer ml
    ON ml.id = l.map_layer
   AND ml.topological
  GROUP BY l.id, l.map_layer, e.edge_id, (l.topo).id, (l.topo).layer_id
  HAVING count(*) = 1;

  DELETE FROM {topo_schema}.__edge_relation er
  USING _dirty_face_edges e
  WHERE er.edge_id = e.edge_id
    AND er.topolayer_id IN (
      SELECT tl.layer_id
      FROM topology.layer tl
      JOIN topology.topology t ON t.id = tl.topology_id
      WHERE t.name = {topo_name_literal}
        AND tl.feature_type = 3
    )
    AND NOT EXISTS (
      SELECT 1 FROM _dirty_face_edge_owners o
      WHERE o.line_id = er.line_id
        AND o.edge_id = er.edge_id
    );

  INSERT INTO {topo_schema}.__edge_relation (
    line_id,
    map_layer,
    edge_id,
    topogeo_id,
    topolayer_id
  )
  SELECT line_id, map_layer, edge_id, topogeo_id, topolayer_id
  FROM _dirty_face_edge_owners
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS _n = ROW_COUNT;
  RETURN _n;
END;
$$ LANGUAGE plpgsql;

-- Earlier revisions were row-level; a statement-level trigger cannot replace
-- one in place, so drop them first.
DROP TRIGGER IF EXISTS update_face_edge_relation ON {topo_schema}.relation;
DROP TRIGGER IF EXISTS delete_face_edge_relation ON {topo_schema}.relation;
DROP TRIGGER IF EXISTS insert_face_edge_relation ON {topo_schema}.relation;

CREATE TRIGGER insert_face_edge_relation
AFTER INSERT ON {topo_schema}.relation
REFERENCING NEW TABLE AS changed_new
FOR EACH STATEMENT
EXECUTE FUNCTION {topo_schema}.update_face_edge_relation();

CREATE TRIGGER update_face_edge_relation
AFTER UPDATE ON {topo_schema}.relation
REFERENCING OLD TABLE AS changed_old NEW TABLE AS changed_new
FOR EACH STATEMENT
EXECUTE FUNCTION {topo_schema}.update_face_edge_relation();

CREATE TRIGGER delete_face_edge_relation
AFTER DELETE ON {topo_schema}.relation
REFERENCING OLD TABLE AS changed_old
FOR EACH STATEMENT
EXECUTE FUNCTION {topo_schema}.update_face_edge_relation();

/** Change the map layer if it is updated for a line */
CREATE OR REPLACE FUNCTION {topo_schema}.update_edge_relation_map_layer()
RETURNS trigger AS $$
BEGIN
  UPDATE {topo_schema}.__edge_relation
  SET map_layer = NEW.map_layer
  WHERE line_id = OLD.id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER update_edge_relation_map_layer
BEFORE UPDATE
ON {boundary_table}
FOR EACH ROW
WHEN (OLD.map_layer IS DISTINCT FROM NEW.map_layer)
EXECUTE FUNCTION {topo_schema}.update_edge_relation_map_layer();

/** Create trigger for boundary topology (linework or map areas).

Whenever a boundary feature's topogeometry is (re)set, rebuild its cached edge
relations. `__topogeom_edges` transparently handles both edge- and face-based
topogeometries. */
CREATE OR REPLACE FUNCTION {topo_schema}.update_line_edge_relation()
RETURNS trigger AS $$
BEGIN

  IF TG_OP = 'UPDATE' THEN
    -- not sure if we need to delete on update
    DELETE FROM {topo_schema}.__edge_relation
    WHERE line_id = OLD.id;
  END IF;

  IF NEW.map_layer IS NULL OR NEW.topo IS NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO {topo_schema}.__edge_relation (
    line_id,
    map_layer,
    edge_id,
    topogeo_id,
    topolayer_id
  )
  SELECT
    NEW.id line_id,
    NEW.map_layer,
    e.edge_id,
    (NEW.topo).id topogeo_id,
    (NEW.topo).layer_id topolayer_id
  FROM {topo_schema}.__topogeom_edges((NEW.topo).id, (NEW.topo).layer_id) e
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER update_line_edge_relation
BEFORE INSERT OR UPDATE ON {boundary_table}
FOR EACH ROW
WHEN (NEW.topo IS NOT NULL)
EXECUTE FUNCTION {topo_schema}.update_line_edge_relation();
