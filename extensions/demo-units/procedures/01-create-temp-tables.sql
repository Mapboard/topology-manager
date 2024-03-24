CREATE TABLE tmp_linework_type
AS SELECT * FROM {data_schema}.linework_type
WITH NO DATA;

CREATE TABLE tmp_polygon_type
AS SELECT * FROM {data_schema}.polygon_type
WITH NO DATA;
