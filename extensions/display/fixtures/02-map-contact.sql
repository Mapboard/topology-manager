CREATE OR REPLACE VIEW mapping.contact AS
SELECT
  er.edge_id id,
  line_id,
  er.type,
  0 as map_width,
  et.color,
  er.topology,
  f.unit_id left_face,
  f1.unit_id right_face,
  e.geom geometry,
  false AS hidden,
  coalesce(uc.commonality, 6) commonality
FROM map_topology.__edge_relation er
JOIN map_topology.edge_data e
  ON er.edge_id = e.edge_id
JOIN map_topology.relation r
  ON (r.element_id = e.left_face AND r.element_type = 3)
JOIN map_topology.relation r1
  ON (r1.element_id = e.right_face AND r1.element_type = 3)
JOIN map_topology.map_face f
  ON (f.topo).id = r.topogeo_id
JOIN map_topology.map_face f1
  ON (f1.topo).id = r1.topogeo_id
LEFT JOIN mapping.__unit_commonality uc
  ON uc.u1 = f.unit_id
 AND uc.u2 = f1.unit_id
 AND uc.topology = er.topology
JOIN map_digitizer.linework_type et
  ON et.id = er.type
WHERE type NOT IN ('arbitrary-bedrock', 'arbitrary-surficial-contact')
  AND f.unit_id IS NOT null
  AND f1.unit_id IS NOT null
  AND f1.topology = er.topology
  AND f.topology = er.topology
  AND f1.unit_id != 'surficial-none'
  AND f.unit_id != 'surficial-none';

CREATE INDEX mapping_contact_gix ON mapping.contact USING GIST (geometry);


