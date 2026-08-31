/*
Post a notification each time linework is changed.
This allows a daemonized update process (<main> update --watch)
to incrementally build views on each update.
*/
CREATE OR REPLACE FUNCTION {topo_schema}.linework_notify()
RETURNS TRIGGER AS $$
DECLARE
  _rec RECORD;
  envelope geometry;
  __affected_layers integer[];
  __map_layers integer[];
  __composite boolean;
  __editable boolean;
  __payload jsonb;
BEGIN

  raise notice 'linework_notify: TG_OP = %', TG_OP;

  -- Initialize an empty envelope
  envelope := null;
  __map_layers := ARRAY[]::integer[];

  IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
    FOR _rec IN SELECT * FROM old_table LOOP
        raise notice 'linework_notify: old table: %', _rec;
        envelope := ST_Union(envelope, ST_Envelope(_rec.geometry));
        __map_layers := array_append(__map_layers, _rec.map_layer);
    END loop;
  END IF;

  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    FOR _rec IN SELECT * FROM new_table LOOP
        raise notice 'linework_notify: new table: %', _rec;
        envelope := ST_Union(envelope, ST_Envelope(_rec.geometry));
        __map_layers := array_append(__map_layers, _rec.map_layer);
    END loop;
  END IF;

  -- Get the child map layers for each map layer
  WITH ml AS (
    SELECT {topo_schema}.child_map_layers(unnest(__map_layers), true) AS id
  )
  SELECT array_agg(DISTINCT id)
  INTO __affected_layers
  FROM ml;

  -- If any of map layers are editable, set the editable flag
  SELECT bool_or(coalesce(editable, true))
  INTO __editable
  FROM {data_schema}.map_layer
  WHERE id = ANY(__map_layers);

  -- If all of the map layers are composite, set the composite flag
  SELECT bool_and({data_schema}.is_composite_layer(id))
  INTO __composite
  FROM {data_schema}.map_layer
  WHERE id = ANY(__map_layers);

--   -- Bail out until we can figure this out
  if __composite THEN
    return null;
  end if;

  envelope := ST_Envelope(envelope);

  __payload := jsonb_build_object(
    'schema', TG_TABLE_SCHEMA,
    'table', TG_TABLE_NAME,
    'operation', TG_OP,
    'envelope', ST_AsGeoJSON(envelope)::jsonb,
    'map_layers', __map_layers,
    'affected_layers', __affected_layers,
    'editable', __editable,
    'composite', __composite
  );

  RAISE NOTICE 'linework_notify: payload: %', __payload;

  PERFORM pg_notify(
    'events',
    __payload::text
  );
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;


CREATE FUNCTION {data_schema}.test_notify()
RETURNS void AS $$
BEGIN
  PERFORM pg_notify(
    'events',
    jsonb_build_object(
      'message', 'Test notification'
    )::text
  );
END;
$$ LANGUAGE plpgsql;

-- Trigger to notify if linework has been changed
DROP TRIGGER IF EXISTS map_topology_linework_notify_trigger
ON {data_schema}.linework;

CREATE OR REPLACE TRIGGER map_topology_linework_insert_notify_trigger
  AFTER INSERT ON {data_schema}.linework
  REFERENCING NEW TABLE AS new_table
  FOR EACH STATEMENT
EXECUTE PROCEDURE {topo_schema}.linework_notify();

CREATE OR REPLACE TRIGGER map_topology_linework_update_notify_trigger
  AFTER UPDATE ON {data_schema}.linework
  REFERENCING NEW TABLE AS new_table OLD TABLE AS old_table
  FOR EACH STATEMENT
EXECUTE PROCEDURE {topo_schema}.linework_notify();

CREATE OR REPLACE TRIGGER map_topology_linework_delete_notify_trigger
  AFTER DELETE ON {data_schema}.linework
  REFERENCING OLD TABLE AS old_table
  FOR EACH STATEMENT
EXECUTE PROCEDURE {topo_schema}.linework_notify();
