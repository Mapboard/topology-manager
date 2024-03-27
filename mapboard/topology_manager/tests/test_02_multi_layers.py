from pytest import mark

from ..commands.update import _update


def test_multi_layers(db):
    """Insert two overlapping squares."""

    # Insert a square
    db.run_query(
        "INSERT INTO test_map_data.linework (type, geometry) VALUES ('bedrock', 'SRID=32612;LINESTRING(0 0, 6 0, 6 6, 0 6, 0 0)')"
    )

    # Insert a smaller square with the surficial type
    db.run_query(
        "INSERT INTO test_map_data.linework (type, geometry) VALUES ('surficial', 'SRID=32612;LINESTRING(2 2, 4 2, 4 4, 2 4, 2 2)')"
    )

    # Add identifying units
    db.run_query(
        "INSERT INTO test_map_data.polygon (type, geometry) VALUES ('upper-omkyk', 'SRID=32612;POLYGON((3 3, 4 3, 4 4, 3 3))')"
    )

    db.run_query(
        "INSERT INTO test_map_data.polygon (type, geometry) VALUES ('terrace', 'SRID=32612;POLYGON((3 3, 4 3, 4 4, 3 3))')"
    )

    # Solve the topology
    _update(db)

    # Check that we have two map faces at the center
    res = db.run_query(
        "SELECT topology, ST_Area(geometry) area FROM test_topology.map_face WHERE ST_Intersects(geometry, 'SRID=32612;POINT(3.5 3.5)')"
    ).fetchall()
    assert len(res) == 2
    has_bedrock = False
    has_surficial = False
    for r in res:
        if r.topology == "bedrock":
            has_bedrock = True
            assert r.area == 36.0
        if r.topology == "surficial":
            has_surficial = True
            assert r.area == 4.0
    assert has_bedrock
    assert has_surficial


@mark.xfail(reason="Ordering issues")
def test_remove_surficial(db):
    db.run_query("DELETE FROM test_map_data.linework WHERE type = 'surficial'")
    _update(db, fill_holes=True)
    res = db.run_query(
        "SELECT topology, ST_Area(geometry) area FROM test_topology.map_face"
    ).fetchall()

    assert len(res) == 1
    assert res[0].topology == "bedrock"
