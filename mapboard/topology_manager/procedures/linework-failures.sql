/* Record a boundary row whose whole-row noding failed (the table is created by
   fixtures/05-linework-triggers.sql). */
INSERT INTO {topo_schema}.__boundary_failures (id, error)
VALUES (:id, :error)
ON CONFLICT (id) DO UPDATE
  SET error = EXCLUDED.error,
      recorded = now();
