from ..commands.update import _update
from .helpers import insert_line, insert_polygon, n_faces, point, square


class TestFillHoles:
    def test_fill_holes(self, db):
        """Create a linework dataset with holes"""
        insert_line(db, square(6, center=(3, 3)), type="bedrock", layer="bedrock")
        insert_line(db, square(2, center=(3, 3)), type="bedrock", layer="bedrock")
        _update(db)

        # Check that we have no map faces
        assert n_faces(db) == 2
        assert n_faces(db, identified=True) == 0

    def test_identify_faces(self, db):
        insert_polygon(
            db, square(1, center=(1, 1)), type="upper-omkyk", layer="bedrock"
        )
        _update(db)
        # Check that we have one identified map face
        assert n_faces(db, identified=True) == 1

    def test_add_irrelevant_unit_id(self, db):
        insert_polygon(db, square(1, center=(3, 3)), type="terrace", layer="surficial")
        _update(db)
        # Check that we still only have one map face
        assert n_faces(db, identified=True) == 1

    def test_add_relevant_unit_id(self, db):
        insert_polygon(
            db, square(0.5, center=(3, 3)), type="lower-omkyk", layer="bedrock"
        )
        _update(db)
        # Check that we now have two map faces
        assert n_faces(db, identified=True) == 2

    def test_face_non_overlapping(self, db):
        """Test that the map faces do not overlap"""
        n = db.run_query(
            "SELECT count(*) FROM test_topology.map_face WHERE ST_Intersects(topo, :geom)",
            {"geom": point(3, 3)},
        ).scalar()
        assert n == 1

    def test_remove_identifiers(self, db):
        db.run_query("DELETE FROM test_map_data.polygon WHERE type = 'lower-omkyk'")
        _update(db)
        assert n_faces(db, identified=True) == 1
        assert n_faces(db) == 2

    def test_remove_line(self, db):
        db.run_query(
            "DELETE FROM test_map_data.linework WHERE ST_Intersects(geometry, :geom)",
            {"geom": point(2, 2)},
        )
        # There should only be one line remaining
        n = db.run_query("SELECT count(*) FROM test_map_data.linework").scalar()
        assert n == 1

        _update(db)
        assert n_faces(db, identified=True) == 1
        assert n_faces(db) == 1

    def test_identifier(self, db):
        """The remaining map face should be identified by the largest identifying polygon"""
        res = db.run_query("SELECT unit_id FROM test_topology.map_face").one()
        assert res.unit_id == "upper-omkyk"
