# Agent guidance for topology-manager

## What this project does

A PostGIS-based library that maintains topological consistency for geologic maps.
It converts linework edits into space-filling polygonal map units by iteratively
solving a PostGIS topology. The core logic lives in SQL
(`mapboard/topology_manager/fixtures/` and `procedures/`); the Python module
wraps it for CLI and programmatic use.

**Configuration axes.** `create_context` (`config.py`) is parameterized by three
independent signals (there is no single "mode" flag):
- `identity_strategy` — how a face acquires its identity. An `IdentityStrategy`
  object; defaults to `config.SEARCH_STRATEGY` and is overridden by passing your own
  to `create_context` (no registry). The default `search` covers geologic mapping
  (identity *derived* by area-weighting the typed-polygon table; column `unit_id`).
  A host supplies, e.g., a `direct` strategy for footprints (identity *held* on the
  face/feature via the covering `map_area`, disambiguated by `map_priority`; column
  `map_id`). A strategy only *names* its identity column and provides an
  `install(ctx)` that defines four SQL functions (`identity_for_area`,
  `identity_for_face`, `faces_are_joinable`, `map_face_is_identified`); the column
  itself is created by data-table creation (it references a data table). See
  `docs/design/identity-strategy.md`.
- `boundary_table` — the table holding the boundary features that drive the
  topology (`linework` for lines / edge-based topogeoms; `map_area` for polygons /
  face-based topogeoms). Lineal-vs-areal is discoverable at runtime via
  `topology.layer.feature_type` (cf. `__boundary_is_lineal()`).
- `create_data_tables` — an optional callable. When `None`, the library creates its
  default data tables (the `data-tables`/`polygon-triggers` fixtures run, and they add
  the default `unit_id` identity column). When supplied, the host creates the data
  tables and the identity column, and those fixtures are skipped. `ctx.manage_data_tables`
  is just the derived `create_data_tables is None` (it also gates composite type/boundary
  management).

`identity_strategy` derives `face_identity_column`; `create_tables` calls
`create_data_tables` (or the default fixtures) — which add the identity column — then
runs `identity_strategy.install` *after* the core topology functions exist (the
identity functions depend on `__map_face_layer_id` from `03-topology-functions`) and
before the `04+` fixtures that consume them. Finally it runs `assert_topology_setup`
(see `commands/check_setup.py`) to fail fast if a host strategy / `create_data_tables`
left the identity column, identity functions, or boundary topogeometry missing — pass
`check=False` to skip. Most SQL is written against template vars (`{boundary_table}`,
`{face_identity_column}`), so it works for both edge- and face-based topogeometries.
When touching shared SQL, check it holds for **both** types.

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
3. `update_faces` — resolves dirty faces into `map_face` polygons. Dissolve groups are computed server-side (`dissolve_groups`, connected components of the joinable face graph). Default: persist all groups then commit once. `--incremental`: commit per group (checkpointing for long runs); same groups, just a finer commit cadence.
4. `_clean_topology` (post-faces)

**Performance-critical paths:**
- `toTopoGeom` (in `update_boundary_topo`) — most expensive per-line operation; modifies topology primitives
- Face dissolving (`fixtures/07-get-adjacent-faces.sql`). The joinable face graph comes from `joinable_face_edges(map_layer)`: an edge is crossable when `layers_are_joinable(...) OR faces_are_joinable(...)` — linework relies on the first term (a contact line blocks the join), map-area mode on the second (faces sharing a resolved identity join even across another map's footprint edge). The default `faces_are_joinable` (the `search` strategy, `fixtures/identity/search.sql`) returns **false** so linework reduces to `layers_are_joinable` alone; the `direct` strategy compares stored identities. Connected components are found **server-side** in `dissolve_groups(map_layer)`: it builds the joinable graph once into an indexed temp table and expands each dirty face's component with a recursive walk, returning each group's faces + the map_faces it replaces (so only O(V) groups cross the wire, not the O(E) edge list). `get_adjacent_faces_core` keeps the single-seed recursive traversal for callers that need one face's component. Checkpointing (`--incremental`) is safe because persisting a map_face does **not** change the dissolve graph — it only adds `relation` rows over existing primitives; joinability comes from `__edge_relation` + boundary identity, never from `map_face` contents. (A future strategy that fed persisted face identity back into `faces_are_joinable` would break that invariant — that's the deferred "reactive graph" case.)
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
- `__edge_relation` triggers — if disabled for bulk loads, remember to re-enable and rebuild the cache (`topo rebuild-edge-relations`, or `rebuild_edge_relations(ctx)` / `validate_edge_relations(ctx)`) before running the update pipeline.
- Topology tolerance (`__topo_precision()`) — set at schema creation time; changing it on an existing topology will produce inconsistent results.

## Conventions

- SQL files under `procedures/` are loaded by name via `sql("path/to/file")` in Python; no `.sql` extension in the call.
- Template variables like `{topo_schema}`, `{data_schema}`, `{topo_name_literal}` are substituted at load time by the database layer — they are not SQL parameters.
- Named parameters in SQL use SQLAlchemy `:name` syntax.
- Timing output uses `print_step(name, elapsed)` from `utilities.py`.
