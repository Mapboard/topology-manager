# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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
