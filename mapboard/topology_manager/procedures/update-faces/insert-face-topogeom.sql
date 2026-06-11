WITH
    layer_info AS (
      SELECT
            layer_id
      FROM
            topology.layer
        WHERE
              schema_name = :topo_name
        AND table_name = 'map_face'
          AND feature_column = 'topo'

    ),
    p0 AS (SELECT :topo_element_array AS topo_elements),
    p1 AS (SELECT
               topology.createTopoGeom(:topo_name, 3, (SELECT layer_id FROM layer_info), p0.topo_elements) AS topo
           FROM
               p0),
    p2 AS (SELECT
               topo,
               st_setsrid(topo::geometry, :srid) AS geom
           FROM
               p1)
INSERT
INTO {topo_schema}.map_face (
    unit_id,
    topo,
    map_layer,
    geometry
)
SELECT
    {topo_schema}.unitForArea(p2.geom, :map_layer), p2.topo, :map_layer, p2.geom
FROM
    p2
