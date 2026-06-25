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
`__edge_relation_dirty` (O(1) per row); `rebuild_dirty_edge_relations()` does
the scoped recompute once per affected topogeometry. Callers run that function
after a batch of edits (e.g. at the end of adding a map). The `__edge_relation`
cache is thus eventually consistent — briefly stale between an edit and the
rebuild. */
CREATE OR REPLACE FUNCTION {topo_schema}.update_face_edge_relation()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    INSERT INTO {topo_schema}.__edge_relation_dirty (topogeo_id, topolayer_id)
    VALUES (OLD.topogeo_id, OLD.layer_id)
    ON CONFLICT DO NOTHING;
    RETURN OLD;
  END IF;

  INSERT INTO {topo_schema}.__edge_relation_dirty (topogeo_id, topolayer_id)
  VALUES (NEW.topogeo_id, NEW.layer_id)
  ON CONFLICT DO NOTHING;
  RETURN NEW;
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
  RETURN _n;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER update_face_edge_relation
AFTER INSERT OR UPDATE
ON {topo_schema}.relation
FOR EACH ROW
WHEN (NEW.element_type = 3)
EXECUTE FUNCTION {topo_schema}.update_face_edge_relation();

CREATE OR REPLACE TRIGGER delete_face_edge_relation
AFTER DELETE
ON {topo_schema}.relation
FOR EACH ROW
WHEN (OLD.element_type = 3)
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
