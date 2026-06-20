from .helpers import (
    insert_line,
    insert_polygon,
    map_layer_id,
    n_faces,
    point,
    square,
    get_face_id,
)
from mapboard.topology_manager.commands.update_faces.helpers import (
    containing_map_faces,
    get_adjacent_faces,
)
from pydantic import BaseModel
from typing import Optional


class MapFaceInfo(BaseModel):
    face_id: int
    map_face_id: Optional[int]
    map_layer: int


def get_face_info(db, _point, map_layer):
    face_id = get_face_id(db, _point)
    if face_id is None:
        face_id = 0  # No face found, return the global face id
    # Check that we find a single containing map face
    mf0 = containing_map_faces(db, [face_id], map_layer)
    assert len(mf0) <= 1
    _id = None
    if len(mf0) == 1:
        _id = mf0[0]
    return MapFaceInfo(face_id=face_id, map_face_id=_id, map_layer=map_layer)


def _test_points(db, lyr):
    points = [point(3, 3), point(5, 5)]
    return [get_face_info(db, p, lyr) for p in points]


class TestFillHoles:
    def test_fill_holes(self, mgr, db):
        """Create a linework dataset with holes"""
        lyr = map_layer_id(db, "bedrock")
        insert_line(db, square(6, center=(3, 3)), type="bedrock", map_layer=lyr)
        insert_line(db, square(2, center=(3, 3)), type="bedrock", map_layer=lyr)
        mgr.update()

        # Check that we have no identified map faces
        assert n_faces(db) == 2
        assert n_faces(db, identified=True) == 0

        points = _test_points(db, lyr)
        assert points[0].face_id != points[1].face_id
        assert points[0].map_face_id != points[1].map_face_id

    def test_identify_faces(self, mgr, db):
        insert_polygon(
            db,
            square(1, center=(1, 1)),
            type="upper-omkyk",
            map_layer=map_layer_id(db, "bedrock"),
        )
        mgr.update()
        # Check that we have one identified map face
        assert n_faces(db, identified=True) == 1

    def test_add_irrelevant_unit_id(self, db, mgr):
        insert_polygon(
            db,
            square(1, center=(3, 3)),
            type="terrace",
            map_layer=map_layer_id(db, "surficial"),
        )
        mgr.update()
        # Check that we still only have one map face
        assert n_faces(db, identified=True) == 1

    def test_add_relevant_unit_id(self, mgr, db):
        insert_polygon(
            db,
            square(0.5, center=(3, 3)),
            type="lower-omkyk",
            map_layer=map_layer_id(db, "bedrock"),
        )
        mgr.update()
        # Check that we now have two map faces
        assert n_faces(db, identified=True) == 2

    def test_face_non_overlapping(self, db):
        """Test that the map faces do not overlap"""
        n = db.run_query(
            "SELECT count(*) FROM test_topology.map_face WHERE ST_Intersects(topo, :geom)",
            {"geom": point(3, 3)},
        ).scalar()
        assert n == 1

    def test_remove_identifiers(self, mgr, db):
        db.run_query("DELETE FROM test_map_data.polygon WHERE type = 'lower-omkyk'")
        mgr.update()
        assert n_faces(db, identified=True) == 1
        assert n_faces(db) == 2

    def test_remove_line(self, mgr, db):
        _bedrock = map_layer_id(db, "bedrock")
        db.run_query(
            "DELETE FROM test_map_data.linework WHERE ST_Intersects(geometry, :geom)",
            {"geom": point(2, 2)},
        )
        # There should only be one line remaining, in the bedrock layer
        n = db.run_query("SELECT count(*) FROM test_map_data.linework").scalar()
        assert n == 1

        mgr.update()

        points = _test_points(db, _bedrock)
        expanded = get_adjacent_faces(db, points[0].face_id, _bedrock)

        assert points[1].face_id in expanded

        assert points[0].face_id == points[1].face_id
        assert points[0].map_face_id == points[1].map_face_id

        assert n_faces(db, identified=True, map_layer=_bedrock) == 1
        assert n_faces(db) == 1

    def test_identifier(self, db):
        """The remaining map face should be identified by the largest identifying polygon"""
        res = db.run_query("SELECT unit_id FROM test_topology.map_face").one()
        assert res.unit_id == "upper-omkyk"
