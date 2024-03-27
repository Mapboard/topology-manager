from pathlib import Path

from psycopg2.sql import Identifier

from ..commands.update import _update

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


def insert_line(db, geometry, type="bedrock"):
    """Insert a line"""
    sql = proc / "insert-feature.sql"
    return db.run_query(
        sql,
        {
            "type": "bedrock",
            "table": Identifier("linework"),
            "layer": "bedrock",
            "geometry": geometry,
        },
    ).one()


class TestTopology:
    def test_basic_insert(self, db):
        """Test that we can insert a record"""
        sql = proc / "basic-insert.sql"
        res = db.run_query(sql).one()
        assert res.type == "bedrock"

    def test_linework_insert(self, db):
        """Test that we can insert a linework record"""
        res = insert_line(db, "SRID=32612;LINESTRING(0 0, 5 0)")
        assert res.type == "bedrock"

    def test_insert_triangle(self, db):
        """Insert a connecting line, creating a triangle"""
        res = insert_line(db, "SRID=32612;LINESTRING(5 0, 3 4, 0 0)")
        assert res.type == "bedrock"

    def test_insert_polygon(self, db):
        """Insert a polygon identifying unit within the triangle"""
        res = db.run_query(
            """INSERT INTO {data_schema}.polygon (type, layer, geometry)
            VALUES ('upper-omkyk', 'bedrock', 'SRID=32612;POLYGON((2 0.5, 3 0.5, 3 1, 2 0.5))')
            RETURNING id, type"""
        ).one()
        assert res.type == "upper-omkyk"

    def test_solve_topology(self, db):
        """Solve topology and check that we have a map face"""
        _update(db)
        res = db.run_query("SELECT * FROM {topo_schema}.map_face").fetchall()
        assert len(res) == 1

    def test_change_line_type(self, db):
        """Change a line type to a non-topological type"""

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
        res = db.run_query("SELECT * FROM {topo_schema}.map_face").fetchall()
        assert len(res) == 0


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
