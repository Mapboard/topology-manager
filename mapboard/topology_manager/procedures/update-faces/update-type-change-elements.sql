/**
  Update elements in the composite layer that have changed type.
 */

UPDATE {boundary_table} l1
SET type = l2.type
FROM {boundary_table} l2
WHERE l1.source_id = l2.id
  AND l1.source_layer = l2.map_layer
  AND l1.map_layer = :composite_layer
  AND l1.type != l2.type
RETURNING l1.id;
