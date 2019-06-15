# Way this works

1. Mapbox Vector Tiles are generated on request and stored in the database.
2. Server recalculates tiles and updates features
3. Server notifies client on feature change via a websocket port (this
   part is optional, because if the client is itself making the changes, it can probably calculate where new tiles need to be loaded)
4. Client requests new tiles

This loop could be shortened if the server proactively sent tiles to the
client, but this could lead to a lot of extra/untimely work.

