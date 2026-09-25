INSERT INTO {topo_schema}.map_face (
  {face_identity_column},
  topo,
  map_layer,
  geometry
)
SELECT
    {topo_schema}.__component_identity(:faces, :map_layer, geom, :use_identity_cache),
    topo,
    :map_layer,
    geom
FROM (
    SELECT
        topology.createTopoGeom(
            :topo_name,
            3,
            {topo_schema}.__map_face_layer_id(),
            :topo_element_array
        ) AS topo
) t,
LATERAL (SELECT st_setsrid(t.topo::geometry, :srid)) g(geom)
