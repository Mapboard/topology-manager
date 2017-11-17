/*
When `map_topology.contact` table is updated, changes should propagate
to `map_topology.map_face`
*/

CREATE OR REPLACE FUNCTION map_topology.linework_update_trigger()
/*
Procedure to keep contact table in sync with linework table
*/
RETURNS trigger AS $$
DECLARE
  layerID integer;
BEGIN

  SELECT layer_id
  INTO layerID
  FROM topology.layer
  WHERE schema_name='map_topology'
    AND table_name='contact';

  IF (TG_OP = 'DELETE') THEN
    DELETE
    FROM map_topology.contact c
    WHERE OLD.id = c.id;
    RETURN OLD;
  ELSIF (TG_OP = 'UPDATE') THEN
    -- Set the geometry first, but only if it is changed
    UPDATE map_topology.contact c
    SET
      geometry = topology.toTopoGeom(NEW.geometry, 'map_topology',layerID, 1),
      hash = md5(ST_AsBinary(NEW.geometry))::uuid
    WHERE NEW.id = c.id
      AND md5(ST_AsBinary(NEW.geometry))::uuid != c.hash
      OR c.hash IS null;
    -- Set derived data regardless of what was changed
    UPDATE map_topology.contact c
    SET
      type = NEW.type,
      certainty = NEW.certainty,
      map_width = NEW.map_width,
      hidden = NEW.hidden
    WHERE c.id = NEW.id;

    RETURN NEW;

  ELSIF (TG_OP = 'INSERT') THEN
    -- Insert the row
    INSERT INTO map_topology.contact
      (id, geometry, hash, type, certainty, map_width, hidden)
    SELECT
      NEW.id,
      topology.toTopoGeom(NEW.geometry, 'map_topology',layerID, 1),
      md5(ST_AsBinary(NEW.geometry))::uuid,
      NEW.type,
      NEW.certainty,
      NEW.map_width,
      NEW.hidden;

    RETURN NEW;

  END IF;
  RETURN null;

END;
$$ LANGUAGE plpgsql;


-- Trigger to create a non-topogeometry representation for
-- storage on each row (for speed of lookup)
DROP TRIGGER IF EXISTS map_digitizer_linework_update_trigger
  ON map_topology.contact;
CREATE TRIGGER map_digitizer_linework_update_trigger
AFTER INSERT OR UPDATE OR DELETE ON map_digitizer.linework
FOR EACH ROW
EXECUTE PROCEDURE map_topology.linework_update_trigger();



