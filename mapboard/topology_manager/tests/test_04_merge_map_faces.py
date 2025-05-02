"""Tests to ensure efficient calculations of map faces."""

from macrostrat.utils import get_logger

from .helpers import insert_line, map_layer_id, add_linework_type_to_layer, n_faces, n_face_primitives, create_map_layer
from ..commands.update import _update

log = get_logger(__name__)


class TestMergeMapFaces:
    def test_create_nested_map_layers(self, db):
        """Create a parent and child map layer."""
        parent_lyr = create_map_layer(db, "parent")
        child_lyr = create_map_layer(db, "child", parent=parent_lyr)

        # add a linework type
        add_linework_type_to_layer(db, child_lyr, "bedrock")
        add_linework_type_to_layer(db, parent_lyr, "bedrock")

    def test_create_overlapping_faces(self, db):
        """Create overlapping sets of lines to test face creation."""
        child_lyr = map_layer_id(db, "child")
        parent_lyr = map_layer_id(db, "parent")

        # Insert a square in the parent layer
        coords = [
            (0, 0),
            (2, 0),
            (2, 2),
            (0, 2),
            (0, 0),
        ]
        insert_line(db, coords, type="bedrock", map_layer=parent_lyr)
        _update(db)
        assert n_faces(db) == 2
        assert n_faces(db, map_layer=child_lyr) == 1
        assert n_face_primitives(db) == 1

    def test_insert_child_line(self, db):
        # Insert crossing lines in the child layer
        child_lyr = map_layer_id(db, "child")

        insert_line(db, [(1, -1), (1, 3)], type="bedrock", map_layer=child_lyr)
        _update(db)

        assert n_face_primitives(db) == 2
        assert n_faces(db, map_layer=child_lyr) == 2
        assert n_faces(db) == 3

    def test_insert_another_line(self, db):
        """Insert another line in the child layer."""
        child_lyr = map_layer_id(db, "child")

        insert_line(db, [(-1, 1), (3, 1)], type="bedrock", map_layer=child_lyr)

        _update(db)

        assert n_face_primitives(db) == 4
        assert n_faces(db, map_layer=child_lyr) == 4
        assert n_faces(db) == 5

    def test_merge_faces(self, db):
        # Delete one of the lines from the child layer
        child_lyr = map_layer_id(db, "child")

        db.run_query(
            "DELETE FROM {data_schema}.linework WHERE map_layer = :map_layer AND ST_Touches(geometry, ST_SetSRID(ST_MakePoint(0,1), :srid))",
            {"map_layer": child_lyr}
        )
        _update(db)

        # Should be a single line in the child layer
        n_lines = db.run_query(
            "SELECT count(*) FROM {data_schema}.linework WHERE map_layer = :map_layer",
            {"map_layer": child_lyr}
        ).scalar()
        assert n_lines == 1

        # Check that we have the expected number of faces
        assert n_face_primitives(db) == 2
        assert n_faces(db) == 3

    def test_merge_faces_again(self, db):
        child_lyr = map_layer_id(db, "child")

        db.run_query(
            "DELETE FROM {data_schema}.linework WHERE map_layer = :map_layer",
            {"map_layer": child_lyr}
        )
        _update(db)

        assert n_face_primitives(db) == 1
        assert n_faces(db) == 2

    def test_move_line_to_child_layer(self, db):
        child_lyr = map_layer_id(db, "child")

        # Move the line to the child layer
        db.run_query(
            "UPDATE {data_schema}.linework SET map_layer = :map_layer WHERE map_layer = :parent_lyr",
            {"map_layer": child_lyr, "parent_lyr": map_layer_id(db, "parent")}
        )
        _update(db)

        # The parent layer should no longer have a face
        assert n_faces(db) == 1
