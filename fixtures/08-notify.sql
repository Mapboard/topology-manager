/*
Post a notification each time linework is changed.
This allows a daemonized update process (<main> update --watch)
to incrementally build views on each update.
*/
CREATE OR REPLACE FUNCTION map_topology.linework_notify()
RETURNS TRIGGER AS $$
SELECT pg_notify('events',(TG_OP || 'on linework'));
$$ LANGUAGE sql;

-- Trigger to notify if linework has been changed
DROP TRIGGER IF EXISTS map_topology_linework_notify_trigger
ON map_digitizer.linework;

CREATE TRIGGER map_topology_linework_notify_trigger
BEFORE INSERT
    OR UPDATE OF geometry, type
    OR DELETE
    ON map_digitizer.linework
FOR EACH STATEMENT
EXECUTE PROCEDURE map_topology.linework_notify();

