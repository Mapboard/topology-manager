INSERT INTO {topo_schema}.__linework_failures (id)
VALUES (${id})
ON CONFLICT DO NOTHING;
