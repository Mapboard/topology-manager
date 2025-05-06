from geoalchemy2.shape import from_shape
from psycopg2.sql import Identifier
from shapely.geometry import LineString, Point, Polygon
from macrostrat.database import Database


def insert_feature(db, table, geometry, *, type=None, map_layer=None, srid=32612):
    geom = geometry
    if not isinstance(geom, str):
        geom = str(from_shape(geometry, srid=srid, extended=True))

    if isinstance(map_layer, str):
        map_layer = map_layer_id(db, map_layer)

    return db.run_query(
        "INSERT INTO {table} (type, map_layer, geometry) VALUES (:type, :map_layer, :geom) RETURNING id",
        {
            "type": type,
            "map_layer": map_layer,
            "table": Identifier("test_map_data", table),
            "geom": geom
        },
    ).scalar()


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
    return insert_feature(db, "linework", LineString(coords), **kwargs)


def insert_polygon(db, coords, **kwargs):
    return insert_feature(
        db,
        "polygon",
        Polygon((coords)),
        **kwargs,
    )


def point(x, y):
    return str(from_shape(Point(x, y), srid=32612, extended=True))


def n_face_primitives(db, include_global=False):
    sql = "SELECT count(*) FROM {topo_schema}.face"
    if not include_global:
        sql += " WHERE face_id != 0"
    return db.run_query(sql).scalar()


def n_faces(db, *, identified=False, map_layer=None):
    sql = "SELECT count(*) FROM {topo_schema}.map_face"
    where = []
    params = {}
    if identified:
        where.append("unit_id IS NOT NULL")
    if map_layer is not None:
        where.append("map_layer = :map_layer")
        params["map_layer"] = map_layer
    if len(where) > 0:
        sql += " WHERE " + " AND ".join(where)
    return db.run_query(sql, params).scalar()


def n_edges(db):
    sql = "SELECT count(*) FROM {topo_schema}.edge"
    return db.run_query(sql).scalar()


def map_layer_id(db, name: str):
    return db.run_query(
        "SELECT id FROM {data_schema}.map_layer WHERE name = :name",
        {"name": name},
    ).scalar()


def get_face_id(db, _point):
    return db.run_query(
        "SELECT face_id FROM {topo_schema}.face_data WHERE ST_Intersects(ST_GetFaceGeometry(:topo_name, face_id), :point)",
        dict(point=_point)).scalar()


def intersecting_faces(db, geom):
    return db.run_query(
        "SELECT map_layer, st_area(geometry) area FROM {topo_schema}.map_face WHERE st_intersects(geometry, :geom)",
        dict(geom=geom),
    ).fetchall()


def add_linework_type_to_layer(db, layer_id, linework_type):
    db.run_query(
        """INSERT INTO {data_schema}.map_layer_linework_type (map_layer, "type") VALUES (:map_layer, :layer_type)""",
        dict(map_layer=layer_id, layer_type=linework_type),
    )


def add_polygon_type_to_layer(db, layer_id, polygon_type):
    db.run_query(
        """INSERT INTO {data_schema}.map_layer_polygon_type (map_layer, "type") VALUES (:map_layer, :layer_type)""",
        dict(map_layer=layer_id, layer_type=polygon_type),
    )


def create_map_layer(db: Database, name: str, parent: int = None):
    lyr = db.run_query(
        """
        INSERT INTO {data_schema}.map_layer (NAME, topological, parent)
        VALUES (:name, :topological, :parent)
        RETURNING id
        """,
        {"name": name, "topological": True, "parent": parent},
    ).scalar()
    return lyr
