# Design note: identity strategies & retiring `in_macrostrat_mode`

**Status:** implemented (2026-06-20). `in_macrostrat_mode` is gone; the full
`tests/core` + `tests/map_areas` suites pass against the new API.
**Goal of this move:** make *face identity assignment* an explicit, pluggable seam,
and retire the `in_macrostrat_mode` flag that multiplexed several unrelated concerns.

## Background

The library solves a PostGIS topology and assigns an *identity* to each map face.
Two identity behaviours exist today:

- **`search`** (geologic mapping — linework + polygon units): the face has no identity of
  its own; it is *derived by searching another table* — the dominant `polygon_type` under
  the face, area-weighted — and assigned *after* faces dissolve freely. `faces_are_joinable`
  is a no-op (returns `false`); dissolves are gated only by contact lines. This is the
  library's **reference** strategy.
- **`direct`** (map footprints / compilations today; direct-identity linework later): the
  face/feature *carries its own identity* directly (today via the covering `map_area`,
  disambiguated by `map_priority` — but the priority column is incidental, not the defining
  trait). `faces_are_joinable` compares identities; dissolves are gated by identity.

The naming axis is **where identity lives**: searched from another table (`search`) vs. held
on the face/feature itself (`direct`). This is orthogonal to boundary geometry — so the
planned direct-identity *linework* mode (evolution #1) is just `direct` paired with a
linework `boundary_table`, **not** a new strategy.

These were selected by a single boolean, `in_macrostrat_mode`, which actually
controlled **three orthogonal things at once** (see mapping table below). Identity
is only one of them, and it is the axis that matters most for the roadmap: future
work adds *more* identity strategies (e.g. linework that maintains face identity
directly, rather than via polygon weighting), so identity must be a first-class,
open-ended extension point — not a binary.

## Decisions (locked)

1. **Default-plus-override model** (not library-owned-only, not a global registry).
   The library ships a reference strategy as the default (`config.SEARCH_STRATEGY`)
   and defines the contract; a host overrides it by constructing its own
   `IdentityStrategy` and passing it to `create_context`. The two current behaviours
   are examples, *not* the taxonomy. (An earlier draft used a key-string registry;
   removed as over-engineering — selection is just an object on the context.)
2. **`in_macrostrat_mode` is removed entirely** (no back-compat alias). It decomposes
   into three explicit signals with no residue.
3. **The identity column is part of the contract** (name + SQL type), with a known
   glide path: we expect to eventually consolidate on a single integer identity and
   drop the type (and possibly the per-strategy column entirely). So: do *not* build
   any per-type dispatch logic — the type is just a string passed into column DDL.
4. **The join combinator is reserved in the contract but stays hardcoded `OR`** this
   move. Both current strategies are correct under `OR`. Making it swappable is the
   next evolution's work (direct-identity linework will want `AND`).

## The `in_macrostrat_mode` decomposition

`in_macrostrat_mode` retires into exactly three signals:

| Current branch | Concern | Replacement |
|---|---|---|
| `boundary_table`/`face_identity_column` select (`config.py`) | identity column | **`identity_strategy`** (derives the column) |
| `boundary_table` = `linework` vs `map_area` | which table holds boundaries | **`boundary_table: str` config field** (name only; lineal-vs-areal is discoverable at runtime via `topology.layer.feature_type`, cf. `__boundary_is_lineal()`) |
| clean-topology layer (`clean_topology.py`) | which table holds boundaries | **derived from `boundary_table`** (no new signal) |
| skip `data-tables` + `polygon-triggers` (`create_tables.py`) | does the library own the feature tables | **`manage_data_tables: bool = True`** |
| `add_composite_layer_types` + `manage_boundaries` (`update_composite_layers.py`) | does the library own the feature tables | **`manage_data_tables`** (both are literally `not in_macrostrat_mode` today) |

Net new config: `identity_strategy`, `boundary_table` (name), and `create_data_tables`
(an optional host callable on the context; `manage_data_tables` is the derived
`create_data_tables is None`).

## The IdentityStrategy contract

A strategy owns the *resolution logic* and *declares* its storage; the library owns
the plumbing.

```
IdentityStrategy (dataclass)
├─ key: str                # descriptive label, e.g. "search", "direct"
├─ identity_column: str    # column NAME only; the column (type, FK) is created by
│                          #   data-table creation, since it references a data table
├─ install(ctx) -> None    # install the strategy's SQL functions into topo_schema
└─ combinator: "or" | "and" # reserved; hardcoded OR for now
```

`install(ctx)` must leave these four functions defined in `topo_schema` (every
existing call site already routes through these names, so nothing downstream changes):

- `identity_for_area(geom, map_layer) -> identity` — assign identity to a face from its geometry
- `identity_for_face(face_id, map_layer) -> identity` — resolve identity of a topology face
- `faces_are_joinable(f1, f2, map_layer) -> bool` — do two faces dissolve together on identity grounds
- `map_face_is_identified(map_face) -> bool` — does a face have an assigned identity

### Selection

- The library defines `config.SEARCH_STRATEGY` (the **reference**/default).
- `create_context(identity_strategy=...)` takes an `IdentityStrategy` instance and
  stores it on `TopologyContext`; when omitted it falls back to `SEARCH_STRATEGY`.
  `face_identity_column` is derived from the strategy, not from any mode flag.
- A host overrides by constructing and passing its own strategy — no registration
  step, no global state.
- This replaces today's implicit mechanism, where the identity fixture was skipped
  only because its filename matched the `data-tables` substring in `create_tables.py`.
  Identity selection becomes independent of data-table ownership.

## Concrete changes

1. **config.py** — add the `IdentityStrategy` dataclass + the default
   `SEARCH_STRATEGY`; add `identity_strategy`, `boundary_table`, `create_data_tables`
   (with `manage_data_tables` a derived property); remove `in_macrostrat_mode`. Derive
   `face_identity_column` from the strategy's column name.
2. **create_tables.py** — read `ctx.create_data_tables` (no longer an argument); at the
   data-table stage, call it (host) or run the library data-table fixture (default), then
   run `ctx.identity_strategy.install(ctx)`. The identity column is **not** added here —
   it is created by data-table creation. Skips `data-tables`/`polygon-triggers` when a
   host callable is supplied.
3. **clean_topology.py / update_composite_layers.py** — read `boundary_table` /
   `manage_data_tables` instead of `in_macrostrat_mode`.
4. **Fixtures** — the four functions live in the reference strategy's install SQL
   (`fixtures/identity/search.sql`); the **identity column DDL lives with data-table
   creation** (`unit_id` in `01.1-data-tables.sql`; a host adds its own, e.g. `map_id`
   in the test's `01-create-tables.sql`). The test's `03-identity-management.sql` is the
   install SQL of a **host-supplied strategy** (`direct`) passed via
   `create_context(create_data_tables=...)` — the live proof the override works.
5. **Cleanup** — fix the hardcoded `unit_id` alias in the shared view
   `04-topology-views.sql:111` → `{face_identity_column}`.

## Out of scope (this move)

- Enabling direct-identity *linework* (evolution #1). The `direct` strategy already covers
  the identity side, so this is not a new strategy — but pairing `direct` with a linework
  `boundary_table` will likely need the combinator made swappable (`AND`). That wiring is deferred.
- The import/seed entry point (bootstrap an existing imperfect topology into
  `map_topo`/`linework`) — a separate *entry-point* axis, orthogonal to strategy. It
  will *consume* this contract (ask the active strategy how to seed the identity column).
- A `boundary_geometry` enum or any strategy *class hierarchy* beyond the dataclass.

## Resolved

- **`install` granularity** — one `install(ctx)` blob. The protocol only requires the
  four functions exist in `topo_schema` afterward.
- **Strategy keys** — `search` (the library reference strategy; geologic mapping, identity
  derived by searching the typed-polygon table) and `direct` (footprints today, and the
  future direct-identity linework mode; identity held on the face/feature itself). Named by
  *where identity lives*, not by mechanism, column name, or geometry.
