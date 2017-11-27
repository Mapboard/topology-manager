Right now, this relies on two schemas: `map_digitizer` and `map_topology`. It
might be advisable to fold `map_digitizer` entirely into `map_topology` but
this would reduce ease of restarting: right now, the entire topology can be
rebuilt from scratch by simply calling `DROP SCHEMA map_topology CASCADE`,
without destroying data. It does increase complexity, though.
