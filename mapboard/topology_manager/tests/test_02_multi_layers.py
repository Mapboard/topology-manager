from pytest import mark

from ..commands.update import _update
from .helpers import insert_line, insert_polygon, n_faces, point, square


class TestMultiLayers:
    def test_multi_layers(self, db):
        """Insert two overlapping squares that belong to different sub-topologies"""

        # Insert a square
        insert_line(db, square(6, center=(3, 3)), type="bedrock", layer="bedrock")

        # Insert a smaller square with the surficial type
        insert_line(db, square(2, center=(3, 3)), type="surficial", layer="surficial")

        # Add identifying units
        insert_polygon(
            db, square(1, center=(3, 3)), type="upper-omkyk", layer="bedrock"
        )

        insert_polygon(db, square(1, center=(3, 3)), type="terrace", layer="surficial")

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
            if r.layer == "bedrock":
                has_bedrock = True
                assert r.area == 36.0
            if r.layer == "surficial":
                has_surficial = True
                assert r.area == 4.0
        assert has_bedrock
        assert has_surficial

    @mark.xfail(reason="Ordering issues")
    def test_remove_surficial(self, db):
        assert n_faces(db) == 2
        with db.savepoint(rollback=True):
            db.run_query("DELETE FROM test_map_data.linework WHERE type = 'surficial'")
            _update(db)
            res = db.run_query(
                "SELECT layer, ST_Area(geometry) area FROM test_topology.map_face"
            ).fetchall()

            assert len(res) == 1
            assert res[0].layer == "bedrock"

    def test_remove_bedrock(self, db):
        assert n_faces(db) == 2

        # This works with savepoints but not nested transactions
        with db.savepoint(rollback=True):
            db.run_query("DELETE FROM test_map_data.linework WHERE type = 'bedrock'")
            _update(db)
            res = db.run_query(
                "SELECT layer, ST_Area(geometry) area FROM test_topology.map_face"
            ).fetchall()

            assert len(res) == 1
            assert res[0].layer == "surficial"

    def test_remove_bedrock_no_nested_transaction(self, db):
        assert n_faces(db) == 2
        db.run_query("DELETE FROM test_map_data.linework WHERE type = 'bedrock'")
        _update(db)
        res = db.run_query(
            "SELECT layer, ST_Area(geometry) area FROM test_topology.map_face"
        ).fetchall()

        assert len(res) == 1
        assert res[0].layer == "surficial"


def intersecting_faces(db, geom):
    return db.run_query(
        "SELECT layer, ST_Area(geometry) area FROM test_topology.map_face WHERE ST_Intersects(geometry, :geom)",
        dict(geom=geom),
    ).fetchall()
