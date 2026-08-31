from geoalchemy2.shape import from_shape
from psycopg.sql import Identifier
from shapely.geometry import LineString, Point, Polygon
from macrostrat.database import Database

from .config import TopologyContext
from .commands.update_faces.helpers import get_adjacent_faces


class TopologyInspector:
    ctx: TopologyContext
    db: Database

    def __init__(self, ctx: TopologyContext):
        self.ctx = ctx
        self.db = ctx.database

    def n_faces(self, **kwargs):
        return n_faces(self.db, **kwargs)

    def n_lines(self, **kwargs):
        return n_lines(self.db, **kwargs)

    def n_edges(self):
        return n_edges(self.db)

    def n_face_primitives(self, include_global=False):
        return n_face_primitives(self.db, include_global=include_global)

    def n_edge_relations(self):
        return n_edge_relations(self.db)

    def get_face_id(self, _point):
        return get_face_id(self.db, _point)

    def intersecting_faces(self, geom):
        return intersecting_faces(self.db, geom)

    def map_layer_id(self, name: str):
        return map_layer_id(self.db, name)

    def is_valid(self):
        return (
            self.db.run_query(
                "SELECT count(*) FROM topology.ValidateTopology(:topo_name);"
            ).scalar()
            == 0
        )

    def get_adjacent_faces(self, face_id: int, map_layer: int):
        return get_adjacent_faces(self.db, face_id, map_layer)


def insert_feature(db, table, geometry, *, type=None, map_layer=None, srid=32612):
    if isinstance(map_layer, str):
        map_layer = map_layer_id(db, map_layer)

    return db.run_query(
        "INSERT INTO {table} (type, map_layer, geometry) VALUES (:type, :map_layer, :geom) RETURNING id",
        {
            "type": type,
            "map_layer": map_layer,
            "table": Identifier("test_map_data", table),
            "geom": prepare_geometry(geometry, srid=srid),
        },
    ).scalar()


def prepare_geometry(geom, srid=32612):
    if not isinstance(geom, str):
        geom = str(from_shape(geom, srid=srid, extended=True))
    return geom


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


def n_faces(db, *, identified=False, map_layer=None, source_layer=None):
    sql = "SELECT count(*) FROM {topo_schema}.map_face"
    where = []
    params = {}
    if identified:
        where.append("{face_identity_column} IS NOT NULL")
    if map_layer is not None:
        if isinstance(map_layer, str):
            map_layer = map_layer_id(db, map_layer)
        where.append("map_layer = :map_layer")
        params["map_layer"] = map_layer
    if source_layer is not None:
        where.append("source_layer = :source_layer")
        params["source_layer"] = source_layer
    if len(where) > 0:
        sql += " WHERE " + " AND ".join(where)
    return db.run_query(sql, params).scalar()


def n_lines(db, *, map_layer=None):
    sql = "SELECT count(*) FROM {boundary_table}"
    params = dict()
    if map_layer is not None:
        sql += " WHERE map_layer = :map_layer"
        params["map_layer"] = map_layer
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
        dict(point=_point),
    ).scalar()


def intersecting_faces(db, geom):
    return db.run_query(
        "SELECT map_layer, st_area(geometry) area FROM {topo_schema}.map_face WHERE st_intersects(geometry, :geom)",
        dict(geom=geom),
    ).fetchall()


def add_linework_type_to_layer(db, layer_id, linework_type):
    db.run_query(
        """INSERT INTO {data_schema}.map_layer_linework_type (map_layer, "type") VALUES (:map_layer, :layer_type) ON CONFLICT DO NOTHING""",
        dict(map_layer=layer_id, layer_type=linework_type),
    )


def add_polygon_type_to_layer(db, layer_id, polygon_type):
    db.run_query(
        """INSERT INTO {data_schema}.map_layer_polygon_type (map_layer, "type") VALUES (:map_layer, :layer_type) ON CONFLICT DO NOTHING""",
        dict(map_layer=layer_id, layer_type=polygon_type),
    )


def create_composite_layer(
    db: Database, name: str, layers: list[int], *, parent: int = None
):
    lyr = db.run_query(
        """
        INSERT INTO {data_schema}.map_layer (
            "name",
            parent,
            topological,
            editable
        )
        VALUES (:name, :parent, :topological, :editable)
        RETURNING id
        """,
        {
            "name": name,
            "topological": True,
            "editable": False,
            "parent": parent,
        },
    ).scalar()
    # Members are bottom-to-top, matching the order the former `composited_from`
    # array held; priority is the 1-based position, so the last member wins.
    for priority, member in enumerate(layers, start=1):
        db.run_query(
            """
            INSERT INTO {data_schema}.map_layer_composition (parent_id, member_id, priority)
            VALUES (:parent_id, :member_id, :priority)
            """,
            {"parent_id": lyr, "member_id": member, "priority": priority},
        )
    return lyr


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


def n_edge_relations(db):
    r1 = db.run_query(
        "SELECT count(*) FROM {topo_schema}.__edge_relation_dynamic",
    ).scalar()

    r2 = db.run_query(
        "SELECT count(*) FROM {topo_schema}.__edge_relation",
    ).scalar()

    if r1 != r2:
        raise ValueError(
            f"Number of cached edge relations ({r2}) is not correct ({r1})"
        )
    return r1


def create_grid(
    db,
    layer,
    cells_on_each_axis=10,
):
    for val in range(cells_on_each_axis + 1):
        insert_line(
            db,
            ((val, 0), (val, cells_on_each_axis)),
            type="bedrock",
            map_layer=layer,
        )
        insert_line(
            db,
            ((0, val), (cells_on_each_axis, val)),
            type="bedrock",
            map_layer=layer,
        )
