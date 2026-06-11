from pathlib import Path

from psycopg2.sql import Identifier

from ..commands.update import _update
from .helpers import n_faces, square, map_layer_id, insert_line, prepare_geometry, n_edge_relations
from shapely.geometry import LineString

proc = Path(__file__).parent / "fixtures" / "procedures"


def table_exists(db, schema, table):
    sql = proc / "table-exists.sql"
    return bool(db.run_query(sql, {"schema": schema, "table": table}).scalar())


def test_tables_exist(db):
    """Check that tables have been created in the correct schema"""
    assert not table_exists(db, "map_digitizer", "linework")
    assert table_exists(db, "test_map_data", "linework")


def test_demo_units(db):
    """Test that demo units are created"""
    res = db.run_query("SELECT id FROM {data_schema}.polygon_type").fetchall()
    assert len(res) > 0
    ids = [r[0] for r in res]
    assert "upper-omkyk" in ids


class TestTopology:
    def test_basic_insert(self, db):
        """Test that we can insert a record"""
        sql = proc / "basic-insert.sql"
        res = db.run_query(sql).one()
        assert res.type == "bedrock"

    def test_linework_insert(self, db):
        """Test that we can insert a linework record"""
        insert_line(db, ((0, 0), (5, 0)), type="bedrock", map_layer="bedrock")

    def test_insert_triangle(self, db):
        """Insert a connecting line, creating a triangle"""
        insert_line(db, ((5, 0), (3, 4), (0, 0)), type="bedrock", map_layer="bedrock")

    def test_insert_polygon(self, db):
        """Insert a polygon identifying unit within the triangle"""
        bedrock_id = db.run_query(
            "SELECT id FROM {data_schema}.map_layer WHERE name = 'bedrock'"
        ).scalar()

        res = db.run_query(
            """INSERT INTO {data_schema}.polygon (type, map_layer, geometry)
            VALUES ('upper-omkyk', :map_layer, 'SRID=32612;POLYGON((2 0.5, 3 0.5, 3 1, 2 0.5))')
            RETURNING id, type""",
            dict(map_layer=bedrock_id),
        ).one()
        assert res.type == "upper-omkyk"

    def test_solve_topology(self, db):
        """Solve topology and check that we have a map face"""
        _update(db)
        assert n_faces(db) == 1

        assert n_edge_relations(db) > 0

    def test_change_line_type(self, db):
        """Change a line type and check that the map face is NOT removed
        NOTE: No longer works because topology is now controlled by map layers.
        """
        # Get the ID of the last inserted line
        id = db.run_query(
            "SELECT id FROM {data_schema}.linework ORDER BY id DESC LIMIT 1"
        ).scalar()

        res = db.run_query(
            "UPDATE {data_schema}.linework SET type = 'anticline-hinge' WHERE id = :line_id RETURNING id",
            {"line_id": id},
        ).fetchall()
        assert len(res) == 1

        _update(db)
        assert n_faces(db) == 1

    def test_change_line_layer(self, db):
        """Change a line type and check that the map face is NOT removed
        NOTE: No longer works because topology is now controlled by map layers.
        """
        # Get the ID of the last inserted line
        id = db.run_query(
            "SELECT id FROM {data_schema}.linework ORDER BY id DESC LIMIT 1"
        ).scalar()

        ml = db.run_query(
            "SELECT id FROM {data_schema}.map_layer WHERE name = 'other'"
        ).scalar()

        res = db.run_query(
            "UPDATE {data_schema}.linework SET type = 'anticline-hinge', map_layer = :map_layer WHERE id = :line_id RETURNING id",
            {"line_id": id, "map_layer": ml},
        ).fetchall()
        assert len(res) == 1

        _update(db)
        assert n_faces(db) == 0


def test_isolation(db):
    """Check that we have an empty feature layer"""
    res = db.run_query("SELECT * FROM {data_schema}.linework").fetchall()
    assert len(res) == 0

    res = db.run_query("SELECT * FROM {topo_schema}.map_face").fetchall()
    assert len(res) == 0


# def test_remove_all_data(db):
#     db.run_sql(
#         "TRUNCATE {data_schema}.linework CASCADE; TRUNCATE {data_schema}.polygon CASCADE"
#     )
#     _update(db)
#     res = db.run_query("SELECT * FROM {topo_schema}.map_face").fetchall()
#     assert len(res) == 0

def test_create_and_delete_line(db):
    """Test that the topology returns to a clean state after deleting a line"""
    bedrock_id = map_layer_id(db, "bedrock")
    line_id = insert_line(db, square(1, (0, 0)), type="bedrock", map_layer=bedrock_id)

    _update(db)

    assert n_faces(db) == 1

    # Delete the line
    db.run_query(
        "DELETE FROM {data_schema}.linework WHERE id = :id",
        {"id": line_id},
    )

    assert db.run_query("SELECT count(*) FROM {data_schema}.linework").scalar() == 0

    _update(db)
    assert n_faces(db) == 0


def test_update_line_geometry(db):
    # We want to make sure that line changes are recorded automatically
    bedrock_id = map_layer_id(db, "bedrock")
    line_id = insert_line(db, square(1, (0, 0)), type="bedrock", map_layer=bedrock_id)

    _update(db)
    assert n_faces(db) == 1

    assert get_geometry_hash(db, line_id) is not None

    _update(db)

    # Update the geometry
    db.run_query(
        "UPDATE {data_schema}.linework SET geometry = :geom WHERE id = :id",
        {"id": line_id, "geom": prepare_geometry(LineString(square(2, (0, 0), )), srid=32612)},
    )

    assert get_geometry_hash(db, line_id) is None

    _update(db)

    assert n_faces(db) == 1

    assert get_geometry_hash(db, line_id) is not None

    # Delete the line
    db.run_query(
        "DELETE FROM {data_schema}.linework WHERE id = :id",
        {"id": line_id},
    )

    _update(db)
    assert n_faces(db) == 0


def get_geometry_hash(db, line_id):
    # Check that the geometry_hash is updated
    return db.run_query(
        "SELECT geometry_hash FROM {data_schema}.linework WHERE id = :id",
        {"id": line_id},
    ).scalar()
