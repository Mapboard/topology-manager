--- CLEAN TOPOLOGY --
-- Remove stray edges
SELECT
  e.edge_id,
  map_topology.removeEdgeMaybe(e.edge_id) removed
FROM map_topology.edge_data e
LEFT JOIN map_topology.edge_contact ec
  ON ec.edge_id = e.edge_id
  WHERE ec.contact_id IS null;
-- Remove stray nodes
SELECT
  node_id,
  map_topology.removeNodeMaybe(node_id) removed
FROM map_topology.node;


