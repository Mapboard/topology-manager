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
    editable boolean DEFAULT true,
    composited_from integer[]
    -- Ideas for future functionality:
    -- simplified boolean DEFAULT false,
    -- derived_from integer[],
);

/** Trigger for composite layer constraints */
-- Check that all layers in composited_from exist.
-- This is in lieu of having a foreign key constraint on map_layer.composited_from
CREATE OR REPLACE FUNCTION {data_schema}.check_composited_from()
  RETURNS trigger AS $$
BEGIN
  IF NEW.composited_from IS NOT NULL THEN
    IF NOT NEW.topological THEN
      RAISE EXCEPTION 'Composite layers must be topological';
    END IF;

    IF NEW.editable THEN
      RAISE EXCEPTION 'Composite layers cannot be editable';
    END IF;

    IF cardinality(NEW.composited_from) < 2 THEN
      RAISE EXCEPTION 'Composite layers must reference at least two other layers';
    END IF;

    -- Check if all referenced layers exist
    IF EXISTS (
      SELECT *
      FROM unnest(NEW.composited_from)
      EXCEPT
      SELECT id
      FROM {data_schema}.map_layer
    ) THEN
      RAISE EXCEPTION 'All layers in composited_from must exist';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_composited_from_trigger
  BEFORE INSERT OR UPDATE ON {data_schema}.map_layer
  FOR EACH ROW EXECUTE FUNCTION {data_schema}.check_composited_from();


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

