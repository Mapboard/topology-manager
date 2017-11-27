TRUNCATE TABLE map_topology.__linework_failures;

INSERT INTO map_topology.__linework_failures (id)
SELECT id
FROM UNNEST(CAST(:values AS integer[])) id;
