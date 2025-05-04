/**
  Get rid of orphaned topogeometries in the map_bounds.map_topo table.
  This is required as deleting topogeometry rows does not delete the
  underlying topogeometry primitives.

  The clearTopoGeom procedure can be used instead of this one to
  remove old elements when a topogeometry is modified.
 */

WITH lyr AS (
  SELECT (topology.FindLayer(:table_name , :column_name)).*
), to_delete AS (
  SELECT topogeo_id
  FROM {topo_schema}.relation r
  WHERE layer_id = (SELECT layer_id FROM lyr)
  EXCEPT
  SELECT ({column}).id
  FROM {table}
  WHERE {column} IS NOT NULL
), deleted AS (
  DELETE FROM {topo_schema}.relation
    WHERE topogeo_id IN (SELECT topogeo_id FROM to_delete)
      AND layer_id = (SELECT layer_id FROM lyr)
    RETURNING *
)
SELECT count(*) FROM deleted;
