/*
MAP LAYERS
link together data tables
*/


CREATE TABLE IF NOT EXISTS {data_schema}.map_layer (
    id serial PRIMARY KEY,
    name text NOT NULL,
    description text,
    parent integer CHECK (id != parent) REFERENCES {data_schema}.map_layer(id),
    topological boolean DEFAULT false,
    editable boolean DEFAULT true
    -- Ideas for future functionality:
    -- simplified boolean DEFAULT false,
    -- derived_from integer[],
);

/**
  COMPOSITE LAYER MEMBERSHIP

  A composite layer draws its content from other layers. This table replaces the
  former `map_layer.composited_from integer[]`, which could not carry a foreign
  key (hence the hand-written existence trigger it needed) and encoded ordering
  positionally.

  `priority` is explicit and higher-wins: the member with the highest priority is
  topmost in the composite. That is the same convention the array's order implied
  -- last element painted last -- but stated rather than positional, and it gives
  a place to hang a priority that is a property of the *relationship*, so one
  layer can sit at different priorities under different parents.
*/
CREATE TABLE IF NOT EXISTS {data_schema}.map_layer_composition (
    parent_id integer NOT NULL
      REFERENCES {data_schema}.map_layer(id) ON DELETE CASCADE,
    member_id integer NOT NULL
      REFERENCES {data_schema}.map_layer(id) ON DELETE CASCADE,
    priority integer NOT NULL,
    PRIMARY KEY (parent_id, member_id),
    CONSTRAINT map_layer_composition_no_self_reference CHECK (parent_id != member_id),
    CONSTRAINT map_layer_composition_distinct_priority UNIQUE (parent_id, priority)
      DEFERRABLE INITIALLY IMMEDIATE
);

CREATE INDEX IF NOT EXISTS map_layer_composition_member_idx
  ON {data_schema}.map_layer_composition (member_id);

/** Whether a layer draws its content from other layers. */
CREATE OR REPLACE FUNCTION {data_schema}.is_composite_layer(_layer_id integer)
  RETURNS boolean AS $$
SELECT EXISTS (
  SELECT 1 FROM {data_schema}.map_layer_composition WHERE parent_id = _layer_id
);
$$ LANGUAGE SQL STABLE;

/** A composite layer's members, bottom-to-top (ascending priority).

  This is the order the former `composited_from` array held, so callers that
  paint in reverse keep working unchanged.
*/
CREATE OR REPLACE FUNCTION {data_schema}.composite_layer_members(_layer_id integer)
  RETURNS integer[] AS $$
SELECT array_agg(member_id ORDER BY priority)
FROM {data_schema}.map_layer_composition
WHERE parent_id = _layer_id;
$$ LANGUAGE SQL STABLE;

/** Composite layer constraints.

  Enforced from both sides: adding a membership edge checks the parent, and
  editing a layer that already has members checks that it stays valid. Unlike the
  `composited_from` trigger this replaces, a single-member composite is allowed --
  a compilation is legitimately built up one member at a time.
*/
CREATE OR REPLACE FUNCTION {data_schema}.check_map_layer_composition()
  RETURNS trigger AS $$
DECLARE
  __parent {data_schema}.map_layer;
BEGIN
  SELECT * INTO __parent
  FROM {data_schema}.map_layer
  WHERE id = NEW.parent_id;

  IF NOT coalesce(__parent.topological, false) THEN
    RAISE EXCEPTION 'Composite layers must be topological';
  END IF;

  IF coalesce(__parent.editable, true) THEN
    RAISE EXCEPTION 'Composite layers cannot be editable';
  END IF;

  -- Walk upwards from the parent; reaching the member would close a cycle.
  -- The array form never checked this, but membership is now traversed
  -- recursively, so a cycle is no longer merely wrong -- it fails to terminate.
  IF EXISTS (
    WITH RECURSIVE ancestors AS (
      SELECT NEW.parent_id AS id
      UNION
      SELECT m.parent_id
      FROM {data_schema}.map_layer_composition m
      JOIN ancestors a ON m.member_id = a.id
    )
    SELECT 1 FROM ancestors WHERE id = NEW.member_id
  ) THEN
    RAISE EXCEPTION USING MESSAGE =
      'Layer ' || NEW.parent_id || ' cannot composite from ' || NEW.member_id
      || ' - that would create a cycle';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER check_map_layer_composition_trigger
  BEFORE INSERT OR UPDATE ON {data_schema}.map_layer_composition
  FOR EACH ROW EXECUTE FUNCTION {data_schema}.check_map_layer_composition();

CREATE OR REPLACE FUNCTION {data_schema}.check_composite_layer_flags()
  RETURNS trigger AS $$
BEGIN
  IF (coalesce(NEW.editable, true) OR NOT coalesce(NEW.topological, false))
     AND {data_schema}.is_composite_layer(NEW.id)
  THEN
    RAISE EXCEPTION 'Composite layers must be topological and cannot be editable';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER check_composite_layer_flags_trigger
  BEFORE UPDATE ON {data_schema}.map_layer
  FOR EACH ROW EXECUTE FUNCTION {data_schema}.check_composite_layer_flags();

/** Migrate `composited_from` into the membership table, then retire the column.

  Array ordinality becomes priority directly: the array ran bottom-to-top, so
  ordinality 1 is the lowest priority. Guarded on the column's existence, so this
  is a no-op on every run after the first.

  TODO: create a migration script to handle this going forward.
*/
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = {data_schema_name_literal}
      AND table_name = 'map_layer'
      AND column_name = 'composited_from'
  ) THEN
    INSERT INTO {data_schema}.map_layer_composition (parent_id, member_id, priority)
    SELECT ml.id, m.member_id, m.ord
    FROM {data_schema}.map_layer ml
    CROSS JOIN LATERAL unnest(ml.composited_from) WITH ORDINALITY AS m(member_id, ord)
    WHERE ml.composited_from IS NOT NULL
    ON CONFLICT (parent_id, member_id) DO NOTHING;
  END IF;
END
$$;

DROP TRIGGER IF EXISTS check_composited_from_trigger ON {data_schema}.map_layer;
DROP FUNCTION IF EXISTS {data_schema}.check_composited_from();
ALTER TABLE {data_schema}.map_layer DROP COLUMN IF EXISTS composited_from;


/** A view to summarize the tree of map layers */
CREATE OR REPLACE VIEW {data_schema}.map_layer_tree AS
WITH RECURSIVE parents AS (
SELECT
	id base,
  id,
  parent
FROM {data_schema}.map_layer
UNION
SELECT
	base,
	ml.id,
  ml.parent
FROM parents
JOIN {data_schema}.map_layer ml
  ON ml.id = parents.parent
),
children AS (
SELECT
	id base,
  id,
  parent
FROM {data_schema}.map_layer
UNION
SELECT
	base,
	ml.id,
  ml.parent
FROM children
JOIN {data_schema}.map_layer ml
  ON ml.parent = children.id
),
p1 AS (
SELECT
	p.base map_layer,
	array_agg(id) with_parents
FROM parents p
GROUP BY p.base
),
c1 AS (
SELECT
	c.base map_layer,
	array_agg(id) with_children
FROM children c
GROUP BY c.base
)
SELECT
	p1.map_layer,
	p1.with_parents,
	c1.with_children
FROM p1
JOIN c1
  ON p1.map_layer = c1.map_layer;
