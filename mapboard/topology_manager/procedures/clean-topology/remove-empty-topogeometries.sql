/**
  Get rid of orphaned topogeometries in the various feature tables.
  This is required as deleting topogeometry rows does not delete the
  underlying topogeometry primitives.

  The clearTopoGeom procedure can be used instead of this one to
  remove old elements when a topogeometry is modified.
 */
WITH stale_ids AS (
  SELECT topogeo_id FROM {topo_schema}.relation
  WHERE layer_id = :layer_id AND element_type = :feature_type
  EXCEPT
  SELECT ({feature_column}).id FROM {table}
  WHERE topo IS NOT NULL
    AND ({feature_column}).layer_id = :layer_id
    AND ({feature_column}).type = :feature_type
    AND ({feature_column}).topology_id = :topology_id
),
  deleted AS (
    DELETE FROM {topo_schema}.relation r
      WHERE r.layer_id = :layer_id
        AND r.topogeo_id IN (SELECT topogeo_id FROM stale_ids)
      RETURNING r.topogeo_id
  )
SELECT count(*) FROM deleted;
