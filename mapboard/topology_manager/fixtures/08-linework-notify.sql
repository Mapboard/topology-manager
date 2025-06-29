/*
Post a notification each time linework is changed.
This allows a daemonized update process (<main> update --watch)
to incrementally build views on each update.
*/
CREATE OR REPLACE FUNCTION {topo_schema}.linework_notify()
RETURNS TRIGGER AS $$
DECLARE
  row_id integer;
  editable boolean;
  composite boolean;
  envelope geometry;
  map_layer integer;
BEGIN
  -- Get the row ID
  -- TODO: use the old row for UPDATE operations as well.
  -- We could make this fancier using the approach used in map tables,
  -- but that's not necessary for now.
  IF (TG_OP = 'DELETE') THEN
    row_id := OLD.id;
    map_layer := OLD.map_layer;
    envelope := ST_Envelope(OLD.geometry);
  ELSE
    row_id := NEW.id;
    map_layer := NEW.map_layer;
    envelope := ST_Envelope(NEW.geometry);
  END IF;

  SELECT
    ml.editable
  INTO editable
  FROM {data_schema}.map_layer ml
  WHERE ml.id = map_layer;

  SELECT ml.composited_from IS NOT NULL
  INTO composite
  FROM {data_schema}.map_layer ml
  WHERE ml.id = map_layer;

  PERFORM pg_notify(
    'events',
    json_build_object(
      'schema', TG_TABLE_SCHEMA,
      'table', TG_TABLE_NAME,
      'operation', TG_OP,
      'row_id', row_id,
      'map_layers', ARRAY[map_layer],
      'affected_layers', {topo_schema}.child_map_layers(map_layer, true),
      'editable', editable,
      'composite', composite,
      'envelope', ST_AsGeoJSON(envelope, 6)::jsonb
    )::text
  );
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger to notify if linework has been changed
DROP TRIGGER IF EXISTS map_topology_linework_notify_trigger
ON {data_schema}.linework;

CREATE TRIGGER map_topology_linework_notify_trigger
BEFORE INSERT
    OR UPDATE OF geometry, type, map_layer
    OR DELETE
    ON {data_schema}.linework
FOR EACH STATEMENT
EXECUTE PROCEDURE {topo_schema}.linework_notify();

