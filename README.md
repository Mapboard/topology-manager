# Mapboard topology manager

This project a set of PostgreSQL/PostGIS schema definitions and procedures that
enable the iterative solving of linework for a geologic map. These procedures
are wrapped in a high-level Python module that allows the topology to be managed
programmatically, using a command-line interface, or a "watcher" process.

This project, originally called `postgis-geologic-map`, was renamed to reflect
its close association with the [**Mapboard GIS**](https://mapboard-gis.app) iPad
app. This application drives the topology management in the app's
[tethered mapping mode](https://mapboard-gis.app/docs/tethered-mode) and is a
core part of the in-development
[**Mapboard Platform**](https://github.com/Mapboard/Mapboard-Platform) server
application. Version 4 was rewritten in Python to support easier integration
with other GIS applications, such as [Macrostrat's map platform](https://github.com/UW-Macrostrat/macrostrat).

The most important elements of this tool are its
[database models](mapboard/topology_manager/fixtures/) and
[procedural SQL](mapboard/topology_manager/procedures/). The Python module and
CLI largely wrap these elements.

This tool is similar to Luca Penasa's [Mappy](https://github.com/europlanet-gmap/mappy) QGIS plugin.
However, it relies heavily on the PostGIS spatial database system and focuses on iterative use and speed
with large datasets.

## Interfaces

### Command-line interface

The `topo` command-line interface (CLI) is the primary way to interact with the
topology manager tool.

### Topology watcher

The watcher process, invoked using `topo update --watch` waits for changes to
the underlying map data and runs a sequence of procedures to fill interstitial
polygons. It supports multiple topologies (e.g. overlapping bedrock and
surficial units) and line types.

### Python module

In version 4, we inagurated a new Python-based design, with a
`mapboard.topology_manager` module for library use. This module is in an early phase, but it
will eventually be released on PyPI. For now, it underpins the command-line
interface and the watcher process.

## Workflow

### Set up the database

This project relies on two PostgreSQL schemas, named `map_data` and
`map_topology` by default. The `map_data` schema holds the source data for the
map: linework and polygons (used to assign map units to the eventual
space-filling polygons), along with map units and line types. The `map_topology`
schema contains solved topological relationships, including polygonal
space-filling units.

Currently, environment variables are used to configure the database connection,
schema names, and SRID. See [`.env.example`](.env.example) for an example of the
required variables. The schemas for mapping and topology data can be configured,
but a fairly specific structure is assumed. The minimal schema can be created
using the `topo create-tables` command.

### Editing the map

Add geometries to the `map_data.linework` and `map_data.polygon` topologies
using the GIS platform of your choice. Units and line types are managed by
foreign keys to the `map_data.linework_type` and `map_data.polygon_type` tables.

After linework and polygons are added to the database, the topology can be
updated using the command `topo update [--watch]`. The output of topology
building can be found in the `map_topology.map_face` layer.

### Watch mode

The optional `--watch` flag enables the topology watcher daemon, to rebuild the
topology concurrently with modifications (using `--watch` mode).

In watch mode, modifications to the `map_data.linework` and `map_data.polygon`
tables are picked up automatically. In practice, this means that **any GIS
platform** that can connect to PostGIS can be used to propagate changes. QGIS
has been tested extensively, and ArcGIS support should be available depending on
the version and its support for native PostGIS feature layers.

### Removing the topology

The topology can be rebuilt from scratch by calling
`DROP SCHEMA map_topology CASCADE`, without destroying mapping data.

## Installation

The project can be installed as a Python package on recent versions of Python
(3.10+). It also requires a PostgreSQL database with PostGIS installed.
Notionally, all versions greater than PostgreSQL 10 and PostGIS 2.3 should work,
but the project is currently tested on PostgreSQL 14 and greater.

### Local installation

1. Install Poetry with `pip install poetry`.
2. Install Python dependencies with `poetry install`.
3. Create a new PostgreSQL database to hold the mapping data (or you can specify
   an existing one!).
4. Create an `.env` file to configure the application using the
   [`.env.example`](.env.example) file as a template. Make sure to change the
   database connection info to the right values for your PostgreSQL connection.
5. Run the application with `poetry run topo`. This will show a help page
   listing available commands.
6. Create tables: `topo create-tables`.
<!-- 7. Optionally, create demo units and topologies:
   `geologic-map create-demo-units`. -->

### Docker installation

**Note:** Docker installation is broken in Version 4. It will be fixed soon.

1. Make sure Docker and `docker-compose` are installed using the
   [instructions for your platform](https://docs.docker.com/install/).
2. Modify the `docker-assets/docker-map-config.json` configuration file to suit
   your needs (typically, this involves changing the `srid` and `tolerance`
   fields). A better way to configure the application in Docker is forthcoming.
3. Run `docker-compose up --build`. No need for a local PostgreSQL installation!
4. Connect to the `geologic_map` database on local port `54321`.

### "Hybrid" installation

Development with Docker tends to be slow unless heavily optimized, since the app
and its relatively heavy Python dependencies must be recompiled on each build.
One nice alternative is to run the database server in Docker while running the
rest of the app locally. This is the approach taken by the CI GitHub workflow.

## Contributing

Contributions in the form of raised issues or proposed changes are welcome. The
core database code is a strong foundation, and the quality of the rest of the
software around it needs much improvement.

## TODO

- [ ] Improve documentation and onboarding process.
- [ ] Improve configurability and stability of Docker version
- [x] ~~Move `map_topology.subtopology` table to `map_digitizer` schema (it
      currently breaks rule of no dependencies between the schemas).~~ This is now outmoded by the `mapboard.map_layer` construct.
- [x] ~~Stabilize and document vector-tile generation functionality.~~ Vector tile creation has been moved out of this library.
- [x] TESTS!
