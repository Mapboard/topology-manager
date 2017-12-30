-- The subunits of a unit
CREATE OR REPLACE FUNCTION mapping.subunits(text) RETURNS text[] AS $$
    SELECT ARRAY(SELECT id
      FROM mapping.unit_tree
      WHERE $1 = ANY(tree));
$$ LANGUAGE SQL;

-- The commonality between two units
-- (units are part of the same what?)
CREATE OR REPLACE
  FUNCTION mapping.unit_commonality(text, text)
  RETURNS integer AS $$
    WITH t AS (
      SELECT UNNEST(tree) id
      FROM mapping.unit_tree
      WHERE id = $1
      INTERSECT
      SELECT UNNEST(tree) id
      FROM mapping.unit_tree
      WHERE id = $2
    )
    SELECT u.level
    FROM t
    JOIN mapping.unit u ON t.id = u.id
    WHERE u.level IS NOT NULL
    ORDER BY u.level DESC LIMIT 1
$$ LANGUAGE SQL;


