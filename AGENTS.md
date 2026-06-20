# Agent guidance for topology-manager

## What this project does

A PostGIS-based library that maintains topological consistency for geologic maps.
It converts linework edits into space-filling polygonal map units by iteratively
solving a PostGIS topology. The core logic lives in SQL
(`mapboard/topology_manager/fixtures/` and `procedures/`); the Python module
wraps it for CLI and programmatic use.

**Two boundary modes.** The boundary features that drive the topology can be
either *lines* or *polygons*, selected by `in_macrostrat_mode` in
`create_context` (`config.py`):
- **Linework mode** (default) — boundaries are edits to a `linework` table whose
  topogeometries are *edge-based* (`element_type = 2`). Faces are identified by
  `unit_id`. This is the classic geologic-map case.
- **Map-area mode** (`in_macrostrat_mode=True`) — boundaries are polygons in a
  `map_area` table whose topogeometries are *face-based* (`element_type = 3`).
  Faces are identified by `map_id`, and overlapping areas are resolved by
  priority (`map_priority`). This manages topology for sets of identified
  polygons (e.g. map footprints/compilations).

The mode determines `boundary_table` and `face_identity_column` (see
`config.py`); most SQL is written against these template variables so it works
for both. When touching shared SQL, check it holds for **both** topogeometry
types, not just linework.

## Running tests

```bash
uv run pytest
```

Tests require a running PostgreSQL+PostGIS database. The connection URL is read
from the `TOPO_TESTING_DATABASE_URL` environment variable (see `.env`). Each test
session creates and tears down its own schema, so tests are safe to run against a
shared dev database.

Two suites exercise the two boundary modes:
- `tests/core/` — linework (edge-based) topology
- `tests/map_areas/` — map-area (face-based) topology, with its own fixtures
  under `tests/map_areas/fixtures/` that define the `map_area`/`map_priority`
  tables and `map_id`-based identity functions

Run both when changing shared `fixtures/` SQL.

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
- `get_adjacent_faces_core` (`fixtures/07-get-adjacent-faces.sql`) — recursive CTE that expands outward from a dirty face. An edge is crossable when `layers_are_joinable(...) OR faces_are_joinable(...)`: linework relies on the first term (a contact line blocks the join), map-area mode on the second (faces sharing a resolved identity join even across another map's footprint edge). The default `faces_are_joinable` (`fixtures/01.2-data-tables-identity.sql`) returns **false** so linework reduces to `layers_are_joinable` alone; the map-area override compares `map_id` identities.
- `RemoveUnusedPrimitives` — scans the whole topology; avoid calling when no contacts changed (already gated)
- `createTopoGeom` (`procedures/update-faces/insert-face-topogeom.sql`) — cheap reference assembly; uses `__map_face_layer_id()` IMMUTABLE function

**`__edge_relation` table** — a materialized, trigger-maintained mapping of topology edges → boundary feature → map layers. It exists purely for query performance; the triggers in `fixtures/04-edge-relations-table.sql` keep it in sync, and the `__edge_relation_dynamic` view is the authoritative definition the table must match. The `__topogeom_edges()` helper normalizes both topogeometry types: edge-based boundaries contribute their edges directly, while face-based boundaries contribute only the **exterior** bounding edges of their faces (interior edges that merely subdivide one area are excluded). Edge-relation rows act as join barriers *only* for lineal boundaries — for map areas, dissolves are gated by identity instead (see `get_adjacent_faces_core` above).

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
