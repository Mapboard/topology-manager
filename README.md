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

## Client requirements

Modifications to the `map_digitizer.linework` and `map_digitizer.polygon` tables
will be picked up automatically. In practice, this means that any GIS platform
can be used to propagate changes.

## Installation

#. Create a configuration JSON file using [`geologic-map-config.json`](geologic-map-config.json
#. Install node dependencies with `npm install`.
#. Run the application with `bin/geologic-map`. This will show a help page listing
   the commands installed by the process. This will use the configuration file defined by the `GEOLOGIC_MAP_CONFIG` environment variable.
#. Add topology and 

Installation using Docker and `docker-compose` is being tested, as is encapsulation
of the watcher executable with [**zeit/pkg**](https://github.com/zeit/pkg).



## Contributing

Contributions in the form of raised issues or proposed changes are welcome.
The core database code is a strong foundation, and the quality of the rest
of the software around it needs to be improved.

## TODO

- [ ] Improve documentation
- [ ] Improve onboarding process.
