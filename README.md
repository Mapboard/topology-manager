# Mapboard topology manager

This project a set of PostgreSQL/PostGIS schema definitions and procedures to iteratively solve the linework for a geologic map. These procedures
are wrapped in a high-level Python module that allows the topology to be managed
programmatically, using a command-line interface, or a "watcher" process.

This project, originally called `postgis-geologic-map`, was renamed to reflect
its close association with the [**Mapboard GIS**](https://mapboard-gis.app) iPad
app. This application drives the topology management in the app's
[tethered mapping mode](https://mapboard-gis.app/docs/tethered-mode) and is a
core part of the in-development
[**Mapboard Platform**](https://github.com/Mapboard/Mapboard-Platform) server
application. It was rewritten in Python to support easier integration
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

A `mapboard.topology_manager` Python module is available for library use, and
underpins the command-line interface and watcher process.

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

1. [Install UV](https://docs.astral.sh/uv/getting-started/installation/) using the instructions for your platform.
2. Install Python dependencies with `uv sync`.
3. Create a new PostgreSQL database to hold the mapping data (or you can specify
   an existing one!).
4. Create an `.env` file to configure the application using the
   [`.env.example`](.env.example) file as a template. Make sure to change the
   database connection info to the right values for your PostgreSQL connection.
5. Run the application with `uv run topo`. This will show a help page
   listing available commands.
6. Create tables: `topo create-tables`.
<!-- 7. Optionally, create demo units and topologies:
   `geologic-map create-demo-units`. -->

### Testing

Using the `TOPO_TEST_DATABASE_URL` environment variable, you can run tests against a local database.

Run `uv run pytest` to run the tests.

### "Hybrid" installation

A convenient development setup is to run the PostgreSQL/PostGIS database in
Docker while running the Python app locally. This avoids slow container rebuilds
and is the approach used by the CI GitHub workflow.

## Contributing

Contributions in the form of raised issues or proposed changes are welcome. The
core database code is a strong foundation, and the quality of the rest of the
software around it needs much improvement.

## TODO

- [ ] Improve documentation and onboarding process.
- [x] ~~Move `map_topology.subtopology` table to `map_digitizer` schema (it
      currently breaks rule of no dependencies between the schemas).~~ This is now outmoded by the `mapboard.map_layer` construct.
- [x] ~~Stabilize and document vector-tile generation functionality.~~ Vector tile creation has been moved out of this library.
- [x] ~~TESTS!~~ 83 tests covering single/multi/nested/composite layer scenarios.
