/*
Post a notification each time the output topology changes
*/
CREATE OR REPLACE FUNCTION map_topology.linework_topology_notify()
RETURNS trigger AS $$
DECLARE
__payload text;
__deletion_count integer;
__geometry geometry;
__tile tile_coord;
BEGIN

  IF (TG_OP = 'DELETE') THEN
    __geometry := OLD.geometry;
  ELSE
    __geometry := NEW.geometry;
  END IF;

  __tile := tiles.LargestContainingTile(__geometry);

  WITH deleted AS (
    DELETE FROM tiles.tile t
    WHERE tiles.contains(__tile, (t.x, t.y, t.z))
    RETURNING *
  )
  SELECT count(*)
  INTO __deletion_count
  FROM deleted;

  __payload := json_build_object(
    'type', 'line',
    'id', NEW.id,
    'x', __tile.x,
    'y', __tile.y,
    'z', __tile.z,
    'n_deleted', __deletion_count
  );

  PERFORM pg_notify('topology', __payload);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION map_topology.polygon_topology_notify()
RETURNS trigger AS $$
DECLARE
__payload text;
__deletion_count integer;
__geometry geometry;
__tile tile_coord;
BEGIN

  IF (TG_OP = 'DELETE') THEN
    __geometry := OLD.geometry;
  ELSE
    __geometry := NEW.geometry;
  END IF;

  __tile := tiles.LargestContainingTile(__geometry);

  WITH deleted AS (
    DELETE FROM tiles.tile t
    WHERE tiles.contains(__tile, (t.x, t.y, t.z))
    RETURNING *
  )
  SELECT count(*)
  INTO __deletion_count
  FROM deleted;

  __payload := json_build_object(
    'type', 'face',
    'id', NEW.id,
    'x', __tile.x,
    'y', __tile.y,
    'z', __tile.z,
    'n_deleted', __deletion_count
  );

  PERFORM pg_notify('topology', __payload);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Linework trigger
DROP TRIGGER IF EXISTS map_topology_topo_line_notify_trigger
ON map_digitizer.linework;

CREATE TRIGGER map_topology_topo_line_notify_trigger
AFTER INSERT
    OR UPDATE
    OR DELETE
    ON map_digitizer.linework
FOR EACH ROW
EXECUTE PROCEDURE map_topology.linework_topology_notify();

-- Polygon trigger
DROP TRIGGER IF EXISTS map_topology_topo_map_face_trigger
ON map_topology.map_face;

CREATE TRIGGER map_topology_topo_map_face_trigger
AFTER INSERT
    OR UPDATE
    OR DELETE
    ON map_topology.map_face
FOR EACH ROW
EXECUTE PROCEDURE map_topology.polygon_topology_notify();
