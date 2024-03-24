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
BEGIN

  __added := 0;
  __deleted := 0;
  IF (TG_OP = 'DELETE') THEN
    __geometry := (SELECT ST_Union(geometry) FROM old_table);
    __deleted := (SELECT count(*) FROM old_table);
  ELSIF (TG_OP = 'UPDATE') THEN
    SELECT ST_Union(a.geometry) INTO __geometry
    FROM (
      SELECT geometry FROM old_table
      UNION
      SELECT geometry FROM new_table
    ) AS a;
    __deleted := (SELECT count(*) FROM old_table);
    __added := (SELECT count(*) FROM new_table);
  ELSIF (TG_OP = 'INSERT') THEN
    __geometry := (SELECT ST_Union(geometry) FROM new_table);
    __added := (SELECT count(*) FROM new_table);
  END IF;

  __envelope := ST_Envelope(__geometry);

  __payload := json_build_object(
    'table', 'map_face',
    'envelope', ST_AsGeoJSON(__envelope)::jsonb,
    'n_deleted', __deleted,
    'n_created', __added,
    'n_faces', (SELECT count(*) FROM {topo_schema}.map_face)
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
