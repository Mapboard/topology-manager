INSERT INTO strabo.spot_tags (spot_id, tag_id)
VALUES (${spot_id}, ${tag_id})
ON CONFLICT (spot_id, tag_id) DO NOTHING;