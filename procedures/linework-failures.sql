INSERT INTO map_topology.__linework_failures (id)
VALUES (${id})
ON CONFLICT DO NOTHING;
