/*
Post a notification each time linework is changed.
This allows a daemonized update process (<main> update --watch)
to incrementally build views on each update.
*/
CREATE OR REPLACE FUNCTION {topo_schema}.linework_notify()
RETURNS TRIGGER AS $$
DECLARE
  row_id integer;
BEGIN
  -- Get the row ID
  IF (TG_OP = 'DELETE') THEN
    row_id := OLD.id;
  ELSE
    row_id := NEW.id;
  END IF;


  PERFORM pg_notify(
    'events',
    json_build_object(
      'schema', TG_TABLE_SCHEMA,
      'table', TG_TABLE_NAME,
      'operation', TG_OP,
      'row_id', row_id
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

