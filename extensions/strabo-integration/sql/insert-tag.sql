INSERT INTO strabo.tags (id, data)
VALUES (${id}, ${data})
ON CONFLICT (id) DO UPDATE
SET data=EXCLUDED.data;