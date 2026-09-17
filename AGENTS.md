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
- `face_update_mode` — how the face loop persists a dissolved component onto
  `map_face` (`config.FaceUpdateMode`; default `move`, env `MAPBOARD_FACE_UPDATE_MODE`,
  CLI `--face-update-mode`, or per call via `update(..., face_update_mode=...)`).
  `move` moves topology primitives between existing faces (`map_face_absorb`), so
  untouched faces keep their ids and only what moved is re-resolved; `replace` is the
  historical delete-and-recreate behaviour (`map_face_replace`). Both must satisfy
  the same invariants (below) and both are exercised by CI.

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
export TOPO_TESTING_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/mapboard_topology_test
uv sync
uv run pytest            # or: make test
```

Tests require a running PostgreSQL + PostGIS database (PostGIS with the
`postgis_topology` extension). The connection URL is read from the
`TOPO_TESTING_DATABASE_URL` environment variable (a `.env` file at the repo root is
loaded too; the older `TOPO_TEST_DATABASE_URL` spelling is wrong). The test session
(re)creates that database, so point it at a throwaway name, never at real data. CI
(`.github/workflows/ci.yml`) runs the `postgis/postgis:16-3.4-alpine` container with
`POSTGRES_PASSWORD=postgres`; locally you can use the same image, or install the
PostGIS packages for a local PostgreSQL 16 (`apt-get install postgresql-16-postgis-3`
and `libpq-dev` for the `psycopg2` build) and start the cluster.

Two suites exercise the two boundary modes:
- `tests/core/` — linework (edge-based) topology with the default `search`
  strategy. One schema for the whole session; each test *class* runs inside a
  savepoint that is rolled back (`tests/core/conftest.py`), so classes are isolated
  but tests within a class are stateful and ordered.
- `tests/map_areas/` — map-area (face-based) topology with a host-supplied `direct`
  strategy, using its own fixtures under `tests/map_areas/fixtures/` (the
  `map_area`/`map_priority` tables and `map_id` identity functions). Each class gets a
  freshly created schema (`tests/map_areas/conftest.py`), and every class is
  parametrized over both `FaceUpdateMode`s. Shared helpers (`add_map`, `set_priority`,
  `mark_dirty`, ...) live in `tests/map_areas/support.py`.

Run both when changing shared `fixtures/` SQL. Useful invocations:

```bash
uv run pytest tests/map_areas -k move            # one mode of the map-area suite
uv run pytest tests/core/test_05_map_faces.py    # one file
uv run pytest -x --log-level=INFO -s              # stop on first failure, see SQL logs
MAPBOARD_FACE_UPDATE_MODE=replace uv run pytest tests/core   # core suite in replace mode
```

CI runs the whole suite once per face-update mode (`MAPBOARD_FACE_UPDATE_MODE`
matrix). The `tests/map_areas` suite always covers both modes regardless of the
variable.

### Validating a change

- **Fixture SQL errors do not fail `create_tables`** — they are logged and loading
  continues. If tests fail with "function/type ... does not exist", search the
  captured log for `ERROR` before debugging anything else. `check_topology_setup(ctx)`
  (run automatically at the end of `create_tables`) reports missing identity and
  face-update functions.
- **Invariants the face loop must keep** (asserted by `tests/map_areas/test_face_moves.py`
  via `TopologyInspector`): every identified primitive belongs to exactly one
  `map_face` in its layer (`unfaced_primitives`), one `map_face` row per connected
  same-identity component (`n_faces`), no orphaned map-face `relation` rows
  (`orphaned_relations`), cached `geometry` equals the resolved topogeometry
  (`faces_match_topology`), and `dirty_face` is empty afterwards. In `move` mode,
  faces that were not affected also keep their ids.
- `tests/core/test_04_merge_map_faces.py` and
  `tests/core/test_05_map_faces.py::test_erase_and_consolidate_faces` are the most
  sensitive to merge/split regressions in linework mode; the composite-layer tests
  (`test_07`, `test_08`) catch stale derived faces.
- Face-update SQL lives in `fixtures/07.1-map-face-elements.sql`; it can be exercised
  directly in `psql` (`SELECT * FROM <topo_schema>.map_face_absorb(ARRAY[...], layer)`),
  and `map_face_overlaps(faces, layer)` shows how a component intersects existing faces.
- There is no linter/formatter gate in CI; `black` and `isort` are in the dev group
  for Python (`uv run black mapboard tests`).

## Key architecture

**Two-schema design:**
- `map_data` (configurable) — editable linework, polygon identifiers, map layer hierarchy
- `map_topology` (configurable) — PostGIS topology primitives + solved `map_face` output

**Update pipeline** (`commands/update.py`):
1. `_update_contacts` — calls `toTopoGeom` per changed line; returns count of lines updated
2. `_clean_topology` (pre-faces) — only runs when contacts changed; removes empty topogeometries, calls `RemoveUnusedPrimitives`, heals degree-2 nodes
3. `update_faces` (package `commands/update_faces/`) — resolves dirty faces into `map_face` polygons. It first drains the deferred edge-relation cache (`rebuild_dirty_edge_relations`, needed for face-based boundaries), then runs a queue-driven loop (`loop.py`): pop a dirty seed, compute its component server-side (`dissolve.py` → `dissolve_component`, the joinable face graph walked from the seed), and persist batches of components through a `FacePersister` (`persist.py`) built on the primitive CRUD in `store.py` (`MapFaceStore` → the `map_face_*` SQL functions in `fixtures/07.1-map-face-elements.sql`). Persisting a component may *re-seed* primitives — the remainder of any existing face that lost primitives — which go back on the queue; that is what splits a face whose remainder is disconnected and rebuilds a face that would otherwise be left without one. Components containing the universal face (0) only *release* primitives. `--incremental`/`persist_interval` set the batch size (every statement commits anyway; each component is persisted atomically by a single PL/pgSQL call).
4. `_clean_topology` (post-faces)

**Performance-critical paths:**
- `toTopoGeom` (in `update_boundary_topo`) — most expensive per-line operation; modifies topology primitives
- Face dissolving (`fixtures/07-get-adjacent-faces.sql`). The joinable face graph comes from `joinable_face_edges(map_layer)`: an edge is crossable when `layers_are_joinable(...) OR faces_are_joinable(...)` — linework relies on the first term (a contact line blocks the join), map-area mode on the second (faces sharing a resolved identity join even across another map's footprint edge). The default `faces_are_joinable` (the `search` strategy, `fixtures/identity/search.sql`) returns **false** so linework reduces to `layers_are_joinable` alone; the `direct` strategy compares stored identities. Connected components are found **server-side** in `dissolve_groups(map_layer)`: it builds the joinable graph once into an indexed temp table and expands each dirty face's component with a recursive walk, returning each group's faces + the map_faces it replaces (so only O(V) groups cross the wire, not the O(E) edge list). `get_adjacent_faces_core` keeps the single-seed recursive traversal for callers that need one face's component. Checkpointing (`--incremental`) is safe because persisting a map_face does **not** change the dissolve graph — it only adds `relation` rows over existing primitives; joinability comes from `__edge_relation` + boundary identity, never from `map_face` contents. (A future strategy that fed persisted face identity back into `faces_are_joinable` would break that invariant — that's the deferred "reactive graph" case.)
- `RemoveUnusedPrimitives` — scans the whole topology; avoid calling when no contacts changed (already gated)
- Persisting faces (`fixtures/07.1-map-face-elements.sql`). In `move` mode `map_face_absorb` reuses the stored geometry of overlapping faces outside the run's *reshaped region* (the union of the primitives that were dirty when the run started, registered per layer by `set_reshaped_faces`) and resolves only moved/reshaped primitives with `ST_GetFaceGeometry`, so cost scales with the change. Resolving a whole topogeometry (`topo::geometry`, as `map_face_create` and `replace` mode do) is the expensive path — tens of seconds for faces with tens of thousands of primitives.
- Every delete path clears the topogeometry (`map_face_delete` → `clearTopoGeom`) so `relation` rows are never orphaned; `remove_empty_topogeometries` remains as a whole-layer safety net.

**`__edge_relation` table** — a materialized, trigger-maintained mapping of topology edges → boundary feature → map layers. It exists purely for query performance; the triggers in `fixtures/04-edge-relations-table.sql` keep it in sync, and the `__edge_relation_dynamic` view is the authoritative definition the table must match. The `__topogeom_edges()` helper normalizes both topogeometry types: edge-based boundaries contribute their edges directly, while face-based boundaries contribute only the **exterior** bounding edges of their faces (interior edges that merely subdivide one area are excluded). Edge-relation rows act as join barriers *only* for lineal boundaries — for map areas, dissolves are gated by identity instead (see `get_adjacent_faces_core` above).

**Dirty face tracking** — when a line's topogeometry changes, `mark_surrounding_faces()` inserts affected face IDs into `dirty_face`. The update pipeline drains this table.

## What's safe to change

- `procedures/` SQL files — query logic, not schema; changes take effect on next `topo create-tables` or test run
- Python command files under `commands/` — business logic wrappers. The face loop is the package `commands/update_faces/` (`models`, `dissolve`, `store`, `persist`, `loop`; `helpers` is a compatibility shim).
- `utilities.py` — shared helpers (console, `print_step`)

## What needs care

- `fixtures/` SQL files — define the schema, triggers, and stored functions. Changes require re-running `topo create-tables` and may require a migration for existing deployments.
- The `topology.layer` catalog — PostGIS topology metadata. Never delete or rename rows manually; use topology API functions.
- `__edge_relation` triggers — if disabled for bulk loads, remember to re-enable and rebuild the cache (`topo rebuild-edge-relations`, or `rebuild_edge_relations(ctx)` / `validate_edge_relations(ctx)`) before running the update pipeline.
- For face-based boundaries the `__edge_relation` cache is maintained *lazily*: relation-row triggers only queue the touched topogeometry in `__edge_relation_dirty`, and `rebuild_dirty_edge_relations()` recomputes those entries. The pipeline calls it after `update_contacts` and at the start of `update_faces`; anything that reads the joinable graph outside the pipeline (e.g. `get_adjacent_faces` right after inserting a map area) should call it first, or the graph may miss a barrier.
- Host identity functions must match relation rows on **both** `topogeo_id` and `layer_id` (topogeometry ids are only unique per topology layer); otherwise a `map_face` topogeometry can be mistaken for a boundary feature with the same id. See `identity_for_face` in `tests/map_areas/fixtures/03-identity-management.sql`.
- Topology tolerance (`__topo_precision()`) — set at schema creation time; changing it on an existing topology will produce inconsistent results.

## Conventions

- SQL files under `procedures/` are loaded by name via `sql("path/to/file")` in Python; no `.sql` extension in the call.
- Template variables like `{topo_schema}`, `{data_schema}`, `{topo_name_literal}` are substituted at load time by the database layer — they are not SQL parameters.
- Named parameters in SQL use SQLAlchemy `:name` syntax.
- Timing output uses `print_step(name, elapsed)` from `utilities.py`.
