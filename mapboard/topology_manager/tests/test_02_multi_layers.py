from pytest import mark

from ..commands.update import _update
from .helpers import (
    insert_line,
    insert_polygon,
    intersecting_faces,
    map_layer_id,
    n_faces,
    point,
    square,
)


def test_topo_face_no_identifier(db):
    """Test that a face with no identifier is created"""
    insert_line(
        db,
        square(1, center=(1, 1)),
        type="bedrock",
        map_layer=map_layer_id(db, "bedrock"),
    )
    _update(db)
    assert n_faces(db) == 1


class TestMultiLayers:
    def test_multi_layers(self, db):
        """Insert two overlapping squares that belong to different sub-topologies"""
        # Check if map layer is integer
        bedrock_id = map_layer_id(db, "bedrock")
        surficial_id = map_layer_id(db, "surficial")

        # Insert a square
        insert_line(db, square(6, center=(3, 3)), type="bedrock", map_layer=bedrock_id)

        # Insert a smaller square with the surficial type
        insert_line(
            db, square(2, center=(3, 3)), type="surficial", map_layer=surficial_id
        )

        # Add identifying units
        insert_polygon(
            db, square(1, center=(3, 3)), type="upper-omkyk", map_layer=bedrock_id
        )

        insert_polygon(
            db, square(1, center=(3, 3)), type="terrace", map_layer=surficial_id
        )

        # Solve the topology
        _update(db)

        # Check that we have two map faces at the center
        res = intersecting_faces(
            db,
            point(3, 3),
        )
        assert len(res) == 2
        has_bedrock = False
        has_surficial = False
        for r in res:
            if r.map_layer == bedrock_id:
                has_bedrock = True
                assert r.area == 36.0
            if r.map_layer == surficial_id:
                has_surficial = True
                assert r.area == 4.0
        assert has_bedrock
        assert has_surficial

    @mark.xfail(reason="Ordering issues")
    def test_remove_surficial(self, db):
        assert n_faces(db) == 2
        with db.savepoint(rollback="always"):
            db.run_query("DELETE FROM test_map_data.linework WHERE type = 'surficial'")
            _update(db)
            res = db.run_query(
                "SELECT map_layer, ST_Area(geometry) area FROM test_topology.map_face"
            ).fetchall()

            assert len(res) == 1
            assert res[0].layer == "bedrock"

    def test_remove_bedrock(self, db):
        assert n_faces(db) == 2

        # This works with savepoints but not nested transactions
        with db.savepoint(rollback="always"):
            db.run_query("DELETE FROM test_map_data.linework WHERE type = 'bedrock'")
            _update(db)
            res = db.run_query(
                "SELECT map_layer, ST_Area(geometry) area FROM test_topology.map_face"
            ).fetchall()

            assert len(res) == 1
            assert res[0].map_layer == map_layer_id(db, "surficial")

    def test_remove_bedrock_no_nested_transaction(self, db):
        assert n_faces(db) == 2
        db.run_query("DELETE FROM {data_schema}.linework WHERE type = 'bedrock'")
        _update(db)
        res = db.run_query(
            "SELECT map_layer, ST_Area(geometry) area FROM test_topology.map_face"
        ).fetchall()

        assert len(res) == 1
        assert res[0].map_layer == map_layer_id(db, "surficial")
