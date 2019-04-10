INSERT INTO ${topo_schema~}.subtopology (id)
VALUES
  ('surficial'),
  ('bedrock')
ON CONFLICT DO NOTHING;
