COPY ${tablename~} (id,name,color,topology)
FROM ${csvfile} DELIMITER ',' CSV HEADER;
