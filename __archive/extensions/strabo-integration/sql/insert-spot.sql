INSERT INTO strabo.spots (id, data)
VALUES (${id}, ${data})
ON CONFLICT DO NOTHING;
--ON CONFLICT (id) DO UPDATE (data=EXCLUDED.data;