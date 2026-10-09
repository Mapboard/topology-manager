/*
Post a notification each time the output topology changes

We use PostgreSQL 10 "transition tables" to get the set of changed rows
https://www.postgresql.org/docs/current/plpgsql-trigger.html#PLPGSQL-TRIGGER-AUDIT-TRANSITION-EXAMPLE
*/
CREATE OR REPLACE FUNCTION {topo_schema}.map_face_topology_notify()
RETURNS trigger AS $$
DECLARE
__payload text;
__deleted integer;
__added integer;
__geometry geometry;
__envelope geometry;
__editable boolean;
__composite boolean;
__map_layers integer[];
__affected_layers integer[];
BEGIN

  __added := 0;
  __deleted := 0;
  __affected_layers := ARRAY[]::integer[];
  IF (TG_OP = 'DELETE') THEN
    __geometry := (SELECT ST_Union(ST_Envelope(geometry)) FROM old_table);
    __deleted := (SELECT count(*) FROM old_table);
    __map_layers := (SELECT array_agg(DISTINCT map_layer) FROM old_table);

  ELSIF (TG_OP = 'UPDATE') THEN
    SELECT ST_Union(ST_Envelope(a.geometry)) INTO __geometry
    FROM (
      SELECT geometry FROM old_table
      UNION
      SELECT geometry FROM new_table
    ) AS a;

    __map_layers := (SELECT array_agg(DISTINCT a.map_layer) FROM (
      SELECT map_layer FROM old_table
      UNION
      SELECT map_layer FROM new_table
    ) AS a);
    __deleted := (SELECT count(*) FROM old_table);
    __added := (SELECT count(*) FROM new_table);
  ELSIF (TG_OP = 'INSERT') THEN
    __map_layers := (SELECT array_agg(DISTINCT map_layer) FROM new_table);
    __geometry := (SELECT ST_Union(ST_Envelope(geometry)) FROM new_table);
    __added := (SELECT count(*) FROM new_table);
  END IF;

  -- Get the child map layers for each map layer
  WITH ml AS (
    SELECT {topo_schema}.child_map_layers(unnest(__map_layers), true) AS id
  ),
  distinct_layers AS (
    SELECT DISTINCT id FROM ml
  )
  SELECT array_agg(id)
  INTO __affected_layers
  FROM distinct_layers
  WHERE id IS NOT NULL;

  -- If any of map layers are editable, set the editable flag
  SELECT bool_or(editable)
  INTO __editable
  FROM {data_schema}.map_layer
  WHERE id = ANY(__map_layers);

  -- If all of the map layers are composite, set the composite flag
  SELECT bool_and({data_schema}.is_composite_layer(id))
  INTO __composite
  FROM {data_schema}.map_layer
  WHERE id = ANY(__map_layers);

  __envelope := ST_Envelope(__geometry);

  __payload := json_build_object(
    'schema', TG_TABLE_SCHEMA,
    'table', TG_TABLE_NAME,
    'operation', TG_OP,
    'envelope', ST_AsGeoJSON(__envelope)::jsonb,
    'n_deleted', __deleted,
    'n_created', __added,
    'n_faces', (SELECT count(*) FROM {topo_schema}.map_face),
    'map_layers', __map_layers,
    'affected_layers', __affected_layers,
    'editable', __editable,
    'composite', __composite
  );

  PERFORM pg_notify('topology', __payload);
  PERFORM pg_notify('qgis', 'refresh qgis');
  RETURN null;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS map_topology_topo_map_face_trigger_insert
ON {topo_schema}.map_face;
DROP TRIGGER IF EXISTS map_topology_topo_map_face_trigger_update
ON {topo_schema}.map_face;
DROP TRIGGER IF EXISTS map_topology_topo_map_face_trigger_delete
ON {topo_schema}.map_face;

CREATE TRIGGER map_topology_topo_map_face_trigger_insert
AFTER INSERT ON {topo_schema}.map_face
REFERENCING
  NEW TABLE AS new_table
FOR EACH STATEMENT
EXECUTE PROCEDURE {topo_schema}.map_face_topology_notify();

CREATE TRIGGER map_topology_topo_map_face_trigger_update
AFTER UPDATE ON {topo_schema}.map_face
REFERENCING
  OLD TABLE AS old_table
  NEW TABLE AS new_table
FOR EACH STATEMENT
EXECUTE PROCEDURE {topo_schema}.map_face_topology_notify();

CREATE TRIGGER map_topology_topo_map_face_trigger_delete
AFTER DELETE ON {topo_schema}.map_face
REFERENCING
  OLD TABLE AS old_table
FOR EACH STATEMENT
EXECUTE PROCEDURE {topo_schema}.map_face_topology_notify();
