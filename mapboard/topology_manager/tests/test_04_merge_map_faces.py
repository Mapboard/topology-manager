"""Tests to ensure efficient calculations of map faces."""

from macrostrat.utils import get_logger

from .helpers import insert_line, map_layer_id, add_linework_type_to_layer, n_faces, n_face_primitives, \
    create_map_layer, n_edges, square, point
from .test_03_fill_holes import get_face_info
from ..commands.update import _update, _update_contacts
from ..update_faces import get_adjacent_faces
from pytest import fixture

log = get_logger(__name__)


def test_simple_edge_relationships(db):
    lyr = create_map_layer(db, "base")
    add_linework_type_to_layer(db, lyr, "bedrock")

    # Insert a line
    insert_line(db, [(0, 0), (3, 0)], type="bedrock", map_layer=lyr)
    _update(db)

    # Check that we have the expected number of edges
    assert n_edges(db) == 1

    # Divide the line into two segments
    insert_line(db, [(1, -1), (1, 1)], type="bedrock", map_layer=lyr)
    _update(db)
    assert n_edges(db) == 4

    _id = insert_line(db, [(2, -1), (2, 1)], type="bedrock", map_layer=lyr)
    _update(db)
    assert n_edges(db) == 7

    # Delete the last edge
    db.run_query("DELETE FROM {data_schema}.linework WHERE id = :id", {"id": _id})
    _update(db)
    assert n_edges(db) == 4


@fixture
def layers(db):
    """Create a set of layers for testing."""
    # Create a base layer
    base_lyr = create_map_layer(db, "parent")
    add_linework_type_to_layer(db, base_lyr, "bedrock")

    # Create a child layer
    child_lyr = create_map_layer(db, "child", parent=base_lyr)
    add_linework_type_to_layer(db, child_lyr, "bedrock")

    return {
        "parent": base_lyr,
        "child": child_lyr,
    }


def test_find_adjacent_faces(db, layers):
    # There should only be the global face
    assert db.run_query("SELECT face_id FROM {topo_schema}.face").scalar() == 0
    # Insert a square into the child layer
    insert_line(db, square(2, center=(0, 0)), type="bedrock", map_layer=layers["child"])
    _update(db)
    assert n_faces(db) == 1
    # Get the face that intersects 0,0
    face_id = db.run_query(
        "SELECT face_id FROM {topo_schema}.face WHERE ST_Intersects(mbr, ST_SetSRID(ST_MakePoint(0, 0), :srid))",
    ).scalar()
    assert face_id is not None

    faces = get_adjacent_faces(db, face_id, layers["child"])
    assert len(faces) == 1
    assert faces[0] == face_id

    f1 = get_adjacent_faces(db, face_id, layers["parent"])
    assert len(f1) == 2
    assert face_id in f1
    assert 0 in f1


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
        insert_line(db, square(2, (1, 1)), type="bedrock", map_layer=parent_lyr)
        _update(db)
        assert n_edges(db) == 1
        assert n_face_primitives(db) == 1

        face_info = get_face_info(db, point(1, 1), map_layer=parent_lyr)
        assert face_info.face_id != 0
        assert 0 not in get_adjacent_faces(db, face_info.face_id, map_layer=child_lyr)
        assert 0 not in get_adjacent_faces(db, face_info.face_id, map_layer=parent_lyr)

        assert n_faces(db, map_layer=parent_lyr) == 1
        assert n_faces(db, map_layer=child_lyr) == 1
        assert n_faces(db) == 2

    def test_insert_child_line(self, db):
        # Insert crossing lines in the child layer
        child_lyr = map_layer_id(db, "child")

        insert_line(db, [(1, -1), (1, 3)], type="bedrock", map_layer=child_lyr)

        _update(db)

        assert n_edges(db) == 5
        assert n_face_primitives(db) == 2
        assert n_faces(db, map_layer=child_lyr) == 2
        assert n_faces(db) == 3

    def test_insert_another_line(self, db):
        """Insert another line in the child layer."""
        child_lyr = map_layer_id(db, "child")

        insert_line(db, [(-1, 1), (3, 1)], type="bedrock", map_layer=child_lyr)

        _update(db)

        assert n_face_primitives(db) == 4
        assert n_edges(db) == 12
        assert n_faces(db, map_layer=child_lyr) == 4
        assert n_faces(db) == 5

    def test_merge_faces(self, db):
        # Delete one of the lines from the child layer
        child_lyr = map_layer_id(db, "child")
        parent_lyr = map_layer_id(db, "parent")

        db.run_query(
            "DELETE FROM {data_schema}.linework WHERE map_layer = :map_layer AND ST_Touches(geometry, ST_SetSRID(ST_MakePoint(-1,1), :srid))",
            {"map_layer": child_lyr}
        )
        _update(db)

        # Should be a single line in the child layer
        n_lines = db.run_query(
            "SELECT count(*) FROM {data_schema}.linework WHERE map_layer = :map_layer",
            {"map_layer": child_lyr}
        ).scalar()
        assert n_lines == 1

        # But we still have the square in the parent layer, so there should be a face there
        face_info = get_face_info(db, point(1, 1), map_layer=parent_lyr)
        assert face_info.face_id != 0
        assert 0 in get_adjacent_faces(db, face_info.face_id, map_layer=child_lyr)
        assert 0 not in get_adjacent_faces(db, face_info.face_id, map_layer=parent_lyr)

        # Check that we have the expected number of faces
        assert n_face_primitives(db) == 2
        assert n_faces(db, map_layer=child_lyr) == 2
        assert n_faces(db, map_layer=parent_lyr) == 1
        assert n_faces(db) == 3

    def test_merge_faces_again(self, db):
        child_lyr = map_layer_id(db, "child")

        db.run_query(
            "DELETE FROM {data_schema}.linework WHERE map_layer = :map_layer",
            {"map_layer": child_lyr}
        )
        _update(db)

        assert n_edges(db) == 1
        assert n_face_primitives(db) == 1
        assert n_faces(db) == 1

    def test_move_line_to_child_layer(self, db):
        child_lyr = map_layer_id(db, "child")

        # Move the line to the child layer
        db.run_query(
            "UPDATE {data_schema}.linework SET map_layer = :map_layer WHERE map_layer = :parent_lyr",
            {"map_layer": child_lyr, "parent_lyr": map_layer_id(db, "parent")}
        )
        _update(db)

        # The parent layer should no longer have a face
        assert n_face_primitives(db) == 1
        assert n_faces(db) == 1
