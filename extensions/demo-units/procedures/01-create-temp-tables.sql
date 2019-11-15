CREATE TABLE tmp_linework_type
AS SELECT * FROM map_digitizer.linework_type
WITH NO DATA;

CREATE TABLE tmp_polygon_type
AS SELECT * FROM map_digitizer.polygon_type
WITH NO DATA;
