# PostGIS geologic map

This project a set of PostgreSQL/PostGIS schema definitions and procedures that
enable the iterative solving of linework for a geologic map.
The watcher process (written in Coffeescript and running on Node.js)
waits for changes to the underlying map data and runs a sequence
of procedures to fill interstitial polygons. It supports multiple topologies
(e.g. overlapping bedrock and surficial units) and line types.

It is designed to work with the **Mapboard GIS** app, a beta streaming digitization
app for the Apple iPad platform. More info on **Mapboard GIS** is coming soon.

# Dependencies

The project requires NodeJS and PostgreSQL/PostGIS
to be installed. This project has been used on PostgreSQL > 10 and PostGIS ~> 2.3.
Currently, testing is mostly occurring on PostgreSQL 11.5 and PostGIS 2.5.3.
Any recent Node version (v8, v10, and v12 tested) should work fine.

Right now, this project relies on two PostgreSQL schemas: `map_digitizer` and
`map_topology`. The `map_digitizer` schema holds the source data for the map:
linework and polygons (used to assign map units to the eventual space-filling
polygons), along with map units and line types. The `map_topology` schema
contains solved topological relationships, including polygonal space-filling
units. It can be rebuilt from scratch by simply calling `DROP SCHEMA
map_topology CASCADE`, without destroying data.

## Structure of the code

The most important part of this tool are the [database artifacts](fixtures/)
it generates and [procedures](procedures/) it runs. The NodeJS executable
(housed in [the `src/` directory](src/) mostly wraps this functionality.

## Client requirements

Modifications to the `map_digitizer.linework` and `map_digitizer.polygon` tables
will be picked up automatically. In practice, this means that any GIS platform
can be used to propagate changes. QGIS has been tested extensively, and ArcGIS
support should be available depending on the version and its support for native
PostGIS feature layers.

An [http server extension](https://github.com/davenquinn/map-digitizer-server)
is bundled that allows communication with networked digitizing platforms, in
particular the Mapboard GIS iPad application.

## Installation

For now, installation from source is required. Installation using
Docker and `docker-compose` is being tested, as is encapsulation
of the watcher executable with [**zeit/pkg**](https://github.com/zeit/pkg).
However, these processes are in development and aren't yet fully supported.

#. Clone this repository: `git clone https://github.com/davenquinn/postgis-geologic-map.git`
#. Update Git submodules: `git submodule update --init`.
#. Install node dependencies with `npm install`.
#. Create a new PostgreSQL database to hold the mapping data (or you can specify an existing one!).
#. Create a configuration JSON file using [`geologic-map-config.example.json`](geologic-map-config.example.json)
   as a template. Make sure to change
   the database connection info to the right values for your PostgreSQL connection,
   using [`the semantics of `pg-promise`](https://github.com/vitaly-t/pg-promise/wiki/Connection-Syntax).
   Optionally, export the full path to your config file to the `GEOLOGIC_MAP_CONFIG` environment variable.
#. Run the application with `bin/geologic-map`. This will show a help page listing
   the commands available. This will use the configuration file
   defined by the `GEOLOGIC_MAP_CONFIG` environment variable, or passed in by the `-c`
   flag at runtime. You can optionally add the `bin` directory to your path.
#. Create tables: `geologic-map create-tables --all`.





## Contributing

Contributions in the form of raised issues or proposed changes are welcome.
The core database code is a strong foundation, and the quality of the rest
of the software around it needs to be improved.

## TODO

- [ ] Improve documentation
- [ ] Improve onboarding process.
