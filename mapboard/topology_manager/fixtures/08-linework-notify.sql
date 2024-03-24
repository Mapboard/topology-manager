/*
Post a notification each time linework is changed.
This allows a daemonized update process (<main> update --watch)
to incrementally build views on each update.
*/
CREATE OR REPLACE FUNCTION {topo_schema}.linework_notify()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM pg_notify('events',(TG_OP || 'on linework'));
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger to notify if linework has been changed
DROP TRIGGER IF EXISTS map_topology_linework_notify_trigger
ON {data_schema}.linework;

CREATE TRIGGER map_topology_linework_notify_trigger
BEFORE INSERT
    OR UPDATE OF geometry, type
    OR DELETE
    ON {data_schema}.linework
FOR EACH STATEMENT
EXECUTE PROCEDURE {topo_schema}.linework_notify();

