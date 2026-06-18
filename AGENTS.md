# Agent guidance for topology-manager

## What this project does

A PostGIS-based library that maintains topological consistency for geologic maps.
It converts linework edits into space-filling polygonal map units by iteratively
solving a PostGIS topology. The core logic lives in SQL
(`mapboard/topology_manager/fixtures/` and `procedures/`); the Python module
wraps it for CLI and programmatic use.

## Running tests

```bash
uv run pytest
```

Tests require a running PostgreSQL+PostGIS database. The connection URL is read
from the `TOPO_TEST_DATABASE_URL` environment variable. Each test session creates
and tears down its own schema, so tests are safe to run against a shared dev
database.

## Key architecture

**Two-schema design:**
- `map_data` (configurable) — editable linework, polygon identifiers, map layer hierarchy
- `map_topology` (configurable) — PostGIS topology primitives + solved `map_face` output

**Update pipeline** (`commands/update.py`):
1. `_update_contacts` — calls `toTopoGeom` per changed line; returns count of lines updated
2. `_clean_topology` (pre-faces) — only runs when contacts changed; removes empty topogeometries, calls `RemoveUnusedPrimitives`, heals degree-2 nodes
3. `update_faces` — resolves dirty faces into `map_face` polygons via recursive adjacency SQL
4. `_clean_topology` (post-faces)

**Performance-critical paths:**
- `toTopoGeom` (in `update_boundary_topo`) — most expensive per-line operation; modifies topology primitives
- `get_adjacent_faces_core` (`fixtures/07-get-adjacent-faces.sql`) — recursive CTE that expands outward from a dirty face
- `RemoveUnusedPrimitives` — scans the whole topology; avoid calling when no contacts changed (already gated)
- `createTopoGeom` (`procedures/update-faces/insert-face-topogeom.sql`) — cheap reference assembly; uses `__map_face_layer_id()` IMMUTABLE function

**`__edge_relation` table** — a materialized, trigger-maintained mapping of topology edges → linework → map layers. It exists purely for query performance; the triggers in `fixtures/04-edge-relations-table.sql` keep it in sync.

**Dirty face tracking** — when a line's topogeometry changes, `mark_surrounding_faces()` inserts affected face IDs into `dirty_face`. The update pipeline drains this table.

## What's safe to change

- `procedures/` SQL files — query logic, not schema; changes take effect on next `topo create-tables` or test run
- Python command files under `commands/` — business logic wrappers
- `utilities.py` — shared helpers (console, `print_step`)

## What needs care

- `fixtures/` SQL files — define the schema, triggers, and stored functions. Changes require re-running `topo create-tables` and may require a migration for existing deployments.
- The `topology.layer` catalog — PostGIS topology metadata. Never delete or rename rows manually; use topology API functions.
- `__edge_relation` triggers — if disabled for bulk loads, remember to re-enable and do a full refresh before running the update pipeline.
- Topology tolerance (`__topo_precision()`) — set at schema creation time; changing it on an existing topology will produce inconsistent results.

## Conventions

- SQL files under `procedures/` are loaded by name via `sql("path/to/file")` in Python; no `.sql` extension in the call.
- Template variables like `{topo_schema}`, `{data_schema}`, `{topo_name_literal}` are substituted at load time by the database layer — they are not SQL parameters.
- Named parameters in SQL use SQLAlchemy `:name` syntax.
- Timing output uses `print_step(name, elapsed)` from `utilities.py`.
