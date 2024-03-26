from .fixtures import db, empty_db


def test_demo_units(db):
    """Test that demo units are created"""
    res = db.run_query("SELECT id FROM {data_schema}.polygon_type").fetchall()
    assert len(res) > 0
    ids = [r[0] for r in res]
    assert "upper-omkyk" in ids
