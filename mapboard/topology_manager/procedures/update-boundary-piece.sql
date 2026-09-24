/* Node one piece of a boundary row's geometry into its topogeometry (the piece
   form of update_boundary_topo). Returns the failure text, NULL on success; no
   row when the id does not exist. */
SELECT {topo_schema}.update_boundary_topo(l, :piece::geometry, :noding_tolerance::numeric) err
FROM {boundary_table} l
WHERE l.id = :id
