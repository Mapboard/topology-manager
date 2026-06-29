/**
  Get rid of orphaned topogeometries in the various feature tables.
  This is required as deleting topogeometry rows does not delete the
  underlying topogeometry primitives.

  The clearTopoGeom procedure can be used instead of this one to
  remove old elements when a topogeometry is modified.
 */
WITH deleted AS (
  DELETE FROM {topo_schema}.relation r
  WHERE r.layer_id = :layer_id
  AND NOT EXISTS (
    SELECT 1
    FROM {table} a
    WHERE ({feature_column}).layer_id = :layer_id
      AND ({feature_column}).id = r.topogeo_id
      AND ({feature_column}).type = :feature_type
      AND ({feature_column}).topology_id = :topology_id
  )
  RETURNING r.topogeo_id
)
SELECT count(*) FROM deleted;
