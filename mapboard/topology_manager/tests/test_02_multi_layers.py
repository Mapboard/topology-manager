from geoalchemy2.shape import from_shape
from pytest import mark

# Encode shapely geometries as WKB for Postgres inserts
from shapely.geometry import LineString, Point, Polygon

from ..commands.update import _update


def insert_line(db, coords, type, srid=32612):
    db.run_query(
        "INSERT INTO test_map_data.linework (type, geometry) VALUES (:type, :geom)",
        {
            "type": type,
            "geom": str(
                from_shape(
                    LineString(coords),
                    srid=srid,
                    extended=True,
                )
            ),
        },
    )


def insert_polygon(db, coords, type, srid=32612):
    db.run_query(
        "INSERT INTO test_map_data.polygon (type, geometry) VALUES (:type, :geom)",
        {
            "type": type,
            "geom": str(
                from_shape(
                    Polygon((coords)),
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


def point(x, y):
    return str(from_shape(Point(x, y), srid=32612, extended=True))


def n_faces(db):
    return db.run_query("SELECT count(*) FROM test_topology.map_face").scalar()


class TestMultiLayers:
    def test_multi_layers(self, db):
        """Insert two overlapping squares that belong to different sub-topologies"""

        # Insert a square
        insert_line(db, square(6, center=(3, 3)), "bedrock")

        # Insert a smaller square with the surficial type
        insert_line(db, square(2, center=(3, 3)), "surficial")

        # Add identifying units
        insert_polygon(db, square(1, center=(3, 3)), "upper-omkyk")

        insert_polygon(db, square(1, center=(3, 3)), "terrace")

        # Solve the topology
        _update(db)

        # Check that we have two map faces at the center
        res = db.run_query(
            "SELECT topology, ST_Area(geometry) area FROM test_topology.map_face WHERE ST_Intersects(geometry, :geom)",
            dict(geom=point(3, 3)),
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
    def test_remove_surficial(self, db):
        assert n_faces(db) == 2
        with db.savepoint(rollback=True):
            db.run_query("DELETE FROM test_map_data.linework WHERE type = 'surficial'")
            _update(db)
            res = db.run_query(
                "SELECT topology, ST_Area(geometry) area FROM test_topology.map_face"
            ).fetchall()

            assert len(res) == 1
            assert res[0].topology == "bedrock"

    def test_remove_bedrock(self, db):
        assert n_faces(db) == 2

        # This works with savepoints but not nested transactions
        with db.savepoint(rollback=True):
            db.run_query("DELETE FROM test_map_data.linework WHERE type = 'bedrock'")
            _update(db)
            res = db.run_query(
                "SELECT topology, ST_Area(geometry) area FROM test_topology.map_face"
            ).fetchall()

            assert len(res) == 1
            assert res[0].topology == "surficial"

    def test_remove_bedrock_no_nested_transaction(self, db):
        assert n_faces(db) == 2
        db.run_query("DELETE FROM test_map_data.linework WHERE type = 'bedrock'")
        _update(db)
        res = db.run_query(
            "SELECT topology, ST_Area(geometry) area FROM test_topology.map_face"
        ).fetchall()

        assert len(res) == 1
        assert res[0].topology == "surficial"
