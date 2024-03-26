from pathlib import Path

from psycopg2.sql import Identifier

from .fixtures import db, empty_db


def test_demo_units(db):
    """Test that demo units are created"""
    res = db.run_query("SELECT id FROM {data_schema}.polygon_type").fetchall()
    assert len(res) > 0
    ids = [r[0] for r in res]
    assert "upper-omkyk" in ids


proc = Path(__file__).parent / "fixtures" / "procedures"


def test_basic_insert(db):
    """Test that we can insert a record"""
    sql = proc / "basic-insert.sql"
    res = db.run_query(sql).one()
    assert res.type == "bedrock"


def test_linework_insert(db):
    """Test that we can insert a linework record"""
    sql = proc / "insert-feature.sql"
    res = db.run_query(
        sql,
        {
            "type": "bedrock",
            "table": Identifier("linework"),
            "geometry": "SRID=4326;LINESTRING(0 0, 1 1)",
        },
    ).one()
    assert res.type == "bedrock"
