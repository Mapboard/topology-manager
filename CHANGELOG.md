# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## `[4.0.0]` - 2024-03

- Shift orchestration code to Python from Typescript
- Remove the `mapboard-server` application

## `[3.0.0]` - 2022

- Create testing integration with StraboSpot
- Move to yarn package manager

## `[2.0.0]` = 2021-04-25

- Shift from Coffeescript to Typescript
- Added a standalone web frontend with more advanced visualization options
- Fixed snapping behavior
- Improved vector tiling server

## `[2.0.0-beta]` - 2020-12-29

### Changed

- The bundled `mapboard-server` application was updated to version 2, which includes
  support for higher-quality streaming topology to the Mapboard client
- Added a hybrid database-in-Docker/local development for quicker iteration
  on containerized app. This can be accessed using `make dev`.
- Added a basic test suite using a Docker-containerized database. This can be accessed by
  running `make test`.
- Move to `npm@7` package manager (including "workspaces"). This will break on npm v6.

## [Unreleased] - 2020-08-31

### Changed

- Added a slightly more aggressive function to prune unused map faces during map_topology
  updates.

## [1.0.0] - 2017-2018

The 1.0 series of **PostGIS Geologic Map** was not formally versioned, but it provided the
basis for quite a lot of PhD mapping when paired with the **Mapboard GIS** app.
