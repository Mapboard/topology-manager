from geoalchemy2.shape import from_shape
from psycopg2.sql import Identifier
from shapely.geometry import LineString, Point, Polygon


def insert_feature(db, table, geometry, *, type=None, map_layer=None, srid=32612):
    db.run_query(
        "INSERT INTO {table} (type, map_layer, geometry) VALUES (:type, :map_layer, :geom)",
        {
            "type": type,
            "map_layer": map_layer,
            "table": Identifier("test_map_data", table),
            "geom": str(
                from_shape(
                    geometry,
                    srid=srid,
                    extended=True,
                )
            ),
        },
    )


def square(size, center=(0, 0)):
    x, y = center
    half = size / 2
    return [
        (x - half, y - half),
        (x + half, y - half),
        (x + half, y + half),
        (x - half, y + half),
        (x - half, y - half),
    ]


def insert_line(db, coords, **kwargs):
    insert_feature(db, "linework", LineString(coords), **kwargs)


def insert_polygon(db, coords, **kwargs):
    insert_feature(
        db,
        "polygon",
        Polygon((coords)),
        **kwargs,
    )


def point(x, y):
    return str(from_shape(Point(x, y), srid=32612, extended=True))


def n_faces(db, identified=False):
    sql = "SELECT count(*) FROM test_topology.map_face"
    if identified:
        sql += " WHERE unit_id IS NOT NULL"
    return db.run_query(sql).scalar()


def map_layer_id(db, name: str):
    return db.run_query(
        "SELECT id FROM {data_schema}.map_layer WHERE name = :name",
        {"name": name},
    ).scalar()


def intersecting_faces(db, geom):
    return db.run_query(
        "SELECT map_layer, ST_Area(geometry) area FROM test_topology.map_face WHERE ST_Intersects(geometry, :geom)",
        dict(geom=geom),
    ).fetchall()


def add_linework_type_to_layer(db, layer_id, linework_type):
    db.run_query(
        "INSERT INTO {data_schema}.map_layer_linework_type (map_layer, type) VALUES (:map_layer, :type)",
        dict(map_layer=layer_id, type=linework_type),
    )
