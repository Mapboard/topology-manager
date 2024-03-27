COPY ${tablename~} (id,name,color,topology)
FROM STDIN DELIMITER ',' CSV HEADER;
