# Claude Code guidance for topology-manager

The project's agent guidance lives in [`AGENTS.md`](AGENTS.md) — read it first. It
covers what the library does, its configuration axes (identity strategy, boundary
table, data-table ownership, face-update mode), the update pipeline, the
performance-critical paths, and what is safe to change.

This file only adds Claude-Code-specific notes.

## Before you change anything

- Tests need a live PostgreSQL + PostGIS database and are the only validation
  the project has; see **Running tests** and **Validating a change** in
  `AGENTS.md`. Set `TOPO_TESTING_DATABASE_URL` (note the spelling) before
  running `uv run pytest`. If no database is available in your environment,
  install the PostGIS packages for the local PostgreSQL (`postgresql-16-postgis-3`
  on Debian/Ubuntu) or start the `postgis/postgis:16-3.4-alpine` container that CI
  uses.
- Run **both** test suites (`tests/core/`, `tests/map_areas/`) and, for anything
  touching `commands/update_faces/` or `fixtures/07*.sql`, both face-update modes
  (`MAPBOARD_FACE_UPDATE_MODE=move` and `=replace`), as CI does.
- SQL fixture errors are *logged*, not raised, while `create_tables` loads them.
  A test failing with "function ... does not exist" usually means a fixture failed
  to compile — look for `ERROR` lines in the captured log, or run
  `check_topology_setup(ctx)`.

## Conventions worth knowing

- SQL under `fixtures/` defines schema and stored functions (PL/pgSQL); SQL under
  `procedures/` is run as ad-hoc statements. Template variables (`{topo_schema}`,
  `{face_identity_column}`, `{srid_literal}`, `{topo_name_literal}`) are
  substituted client-side and are the only way to parameterize the *body* of a
  stored function — `:name` binds do not work inside `$$ ... $$`.
- Every `Database.run_query` / `run_sql` call commits. Atomicity across steps must
  come from a single SQL statement (e.g. one PL/pgSQL function call), which is why
  the face-update CRUD lives in `map_face_absorb` / `map_face_replace`.
- Prefer moving primitives (`FaceUpdateMode.MOVE`) when adding behaviour to the
  face loop; keep `replace` working as the fallback.
