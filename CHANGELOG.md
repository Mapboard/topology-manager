# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

- Update map faces by moving topology primitives between existing faces instead
  of deleting and recreating them (#27). New `FaceUpdateMode` setting
  (`create_context(face_update_mode=...)`, `MAPBOARD_FACE_UPDATE_MODE`,
  `--face-update-mode`): `move` (default) or the legacy `replace`. In both modes
  the remainder of any face that loses primitives is re-seeded, so a
  reprioritization no longer leaves a region without a face, disconnected
  remainders are split into one face per component, and every delete clears the
  topogeometry (no orphaned `relation` rows).
- Two short-circuits keep small changes cheap against large faces: a shed face
  whose remainder is still connected (checked locally) is settled in place
  rather than re-walked, and the dissolve absorbs settled map faces whole.
- `--engine plpgsql` (`TOPO_ENGINE`) runs the face loop server-side in chunks
  (`update_dirty_faces`), one round trip per chunk instead of two per component.
- `commands/update_faces` is now a package: `dissolve` (components), `store`
  (primitive-level CRUD over `map_face`, backed by the new
  `fixtures/07.1-map-face-elements.sql` functions), `persist` (the two modes),
  `loop` (the dirty-face queue). `helpers` re-exports the old names.
- The update pipeline now drains the deferred `__edge_relation` cache
  (`rebuild_dirty_edge_relations`) before dissolving faces, so face-based
  boundaries added since the last update act as barriers.
- `TopologyInspector` gains `orphaned_relations`, `faces_match_topology`,
  `unfaced_primitives` and `n_dirty_faces`; `check_topology_setup` verifies the
  face-update functions compiled.
- Fix the `update-faces` CLI command's signature and the test/README spelling of
  `TOPO_TESTING_DATABASE_URL`.

## `[5.0.0]` - 2026-06-11

- Switch to UV
- Incorporate composite map layers
- Support managing topology for sets of identified polygons (map areas) using
  face-based topogeometries, alongside the existing linework mode
- Make face identity a pluggable strategy: `create_context` now takes an
  `identity_strategy` (default `SEARCH_STRATEGY`), `boundary_table`, and
  `manage_data_tables`, replacing the `in_macrostrat_mode` flag
- Fix `__edge_relation` maintenance for face-based topogeometries (record the
  exterior bounding edges of each area)
- Add `rebuild-edge-relations` (and a `validate_edge_relations` API) to repair the
  `__edge_relation` cache if its triggers fall out of sync
- Speed up face dissolving: connected components are computed server-side
  (PL/pgSQL `dissolve_groups`) over a joinable face graph built once per layer,
  replacing the per-dirty-face graph rebuild.
- `incremental` face updates now mean *checkpointed persistence* (commit per
  dissolve group), decoupling persistence from the adjacency join graph
- Add a post-installation setup check (`check_topology_setup` /
  `assert_topology_setup`, run by `create_tables`) that verifies the identity
  column, identity functions, and boundary table/topogeometry exist — surfacing a
  misconfigured host strategy or `create_data_tables` callable immediately

## `[4.0.0]` - 2024-03

This is a major rewrite of the application to refocus on the core task of
maintaining map topology.

### Removed components

Map styling and layer management code has been moved to the
[Mapboard Platform](https://github.com/Mapboard/Mapboard-Platform) repository,
and the `mapboard-server` application has been removed (its replacement, which
focuses only on serving an advanced feature editing API for the
[Mapboard GIS app](https://mapboard-gis.app/), is now closed source). Other
extensions, such as the StraboSpot integration, are currently unused but will be
shifted to other projects in the future.

### Major changes

- Shift orchestration code to Python from Typescript
- Remove the `mapboard-server` application

## Version 3 series - 2022-2024

This release adds prototypes and previews of technical features, but it is a
stopgap for a more serious pending reorganization and refocusing.

The last legacy version, with orchestration code in TypeScript, can be found at
the [`v3-legacy`](https://github.com/Mapboard/topology-manager/tree/v3-legacy)
tag.

- Add live tiles support for more map types
- Add prototype extension for StraboSpot integration
- Fixes to Docker container
- Reorganize codebase
- Add tile Gzipping, fix protobuf errors
- NPM -> Yarn
- Add QGIS-specific notify channel in watcher
- Remove web frontend from this repository
- Allow config JSON to be loaded from hex-encoded JSON

## `[2.0.0]` = 2021-04-25

- Shift from Coffeescript to Typescript
- Added a standalone web frontend with more advanced visualization options
- Fixed snapping behavior
- Improved vector tiling server

## `[2.0.0-beta]` - 2020-12-29

### Changed

- The bundled `mapboard-server` application was updated to version 2, which
  includes support for higher-quality streaming topology to the Mapboard client
- Added a hybrid database-in-Docker/local development for quicker iteration on
  containerized app. This can be accessed using `make dev`.
- Added a basic test suite using a Docker-containerized database. This can be
  accessed by running `make test`.
- Move to `npm@7` package manager (including "workspaces"). This will break on
  npm v6.

## [Unreleased] - 2020-08-31

### Changed

- Added a slightly more aggressive function to prune unused map faces during
  map_topology updates.

## [1.0.0] - 2017-2018

The 1.0 series of **PostGIS Geologic Map** was not formally versioned, but it
provided the basis for quite a lot of PhD mapping when paired with the
**Mapboard GIS** app.
