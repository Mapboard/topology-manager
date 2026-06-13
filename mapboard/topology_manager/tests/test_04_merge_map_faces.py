"""Tests to ensure efficient calculations of map faces."""

from macrostrat.utils import get_logger

from .helpers import (
    insert_line,
    map_layer_id,
    add_linework_type_to_layer,
    n_faces,
    n_face_primitives,
    create_map_layer,
    n_edges,
    square,
    point,
)
from .test_03_fill_holes import get_face_info
from ..commands.update import _update, _update_contacts, _clean_topology
from ..commands.update_faces.helpers import get_adjacent_faces
from pytest import fixture

log = get_logger(__name__)


def test_simple_edge_relationships(ctx, db):
    lyr = create_map_layer(db, "base")
    add_linework_type_to_layer(db, lyr, "bedrock")

    # Insert a line
    insert_line(db, [(0, 0), (3, 0)], type="bedrock", map_layer=lyr)
    _update(ctx)

    # Check that we have the expected number of edges
    assert n_edges(db) == 1

    # Divide the line into two segments
    insert_line(db, [(1, -1), (1, 1)], type="bedrock", map_layer=lyr)
    _update(ctx)
    assert n_edges(db) == 4

    _id = insert_line(db, [(2, -1), (2, 1)], type="bedrock", map_layer=lyr)
    _update(ctx)
    assert n_edges(db) == 7

    # Delete the last edge
    db.run_query("DELETE FROM {data_schema}.linework WHERE id = :id", {"id": _id})
    _update(ctx)
    assert n_edges(db) == 4


@fixture(scope="class")
def layers(db):
    """Create a set of layers for testing."""
    # Create a base layer

    grandparent = create_map_layer(db, "grandparent")
    add_linework_type_to_layer(db, grandparent, "bedrock")

    base_lyr = create_map_layer(db, "parent", parent=grandparent)
    add_linework_type_to_layer(db, base_lyr, "bedrock")

    # Create a child layer
    child_lyr = create_map_layer(db, "child", parent=base_lyr)
    add_linework_type_to_layer(db, child_lyr, "bedrock")

    return {
        "grandparent": grandparent,
        "parent": base_lyr,
        "child": child_lyr,
    }


def test_find_adjacent_faces(ctx, db, layers):
    # There should only be the global face
    assert db.run_query("SELECT face_id FROM {topo_schema}.face").scalar() == 0
    # Insert a square into the child layer
    insert_line(db, square(2, center=(0, 0)), type="bedrock", map_layer=layers["child"])
    _update(ctx)
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
    def test_create_overlapping_faces(self, ctx, db, layers):
        """Create overlapping sets of lines to test face creation."""
        child_lyr = layers["child"]
        parent_lyr = layers["parent"]

        # Insert a square in the parent layer
        insert_line(db, square(2, (1, 1)), type="bedrock", map_layer=parent_lyr)
        _update(ctx)
        assert n_edges(db) == 1
        assert n_face_primitives(db) == 1

        face_info = get_face_info(db, point(1, 1), map_layer=parent_lyr)
        assert face_info.face_id != 0
        assert 0 not in get_adjacent_faces(db, face_info.face_id, map_layer=child_lyr)
        assert 0 not in get_adjacent_faces(db, face_info.face_id, map_layer=parent_lyr)

        assert n_faces(db, map_layer=parent_lyr) == 1
        assert n_faces(db, map_layer=child_lyr) == 1
        assert n_faces(db) == 2

    def test_insert_child_line(self, ctx, db, layers):
        # Insert crossing lines in the child layer
        child_lyr = layers["child"]

        insert_line(db, [(1, -1), (1, 3)], type="bedrock", map_layer=child_lyr)
        db.session.commit()

        _update_contacts(ctx)
        _clean_topology(ctx)
        assert n_edges(db) == 5

        _update(ctx)

        assert (
            n_edges(db) == 5
        )  # The new line makes 3 edges, combining with the square split in two
        assert n_face_primitives(db) == 2
        assert n_faces(db, map_layer=child_lyr) == 2
        assert n_faces(db) == 3

    def test_insert_another_line(self, ctx, db, layers):
        """Insert another line in the child layer."""
        child_lyr = layers["child"]

        insert_line(db, [(-1, 1), (3, 1)], type="bedrock", map_layer=child_lyr)

        _update(ctx)

        assert n_face_primitives(db) == 4
        assert n_edges(db) == 12
        assert n_faces(db, map_layer=child_lyr) == 4
        assert n_faces(db) == 5

    def test_merge_faces(self, ctx, db, layers):
        # Delete one of the lines from the child layer
        child_lyr = layers["child"]
        parent_lyr = layers["parent"]

        db.run_query(
            "DELETE FROM {data_schema}.linework WHERE map_layer = :map_layer AND ST_Touches(geometry, ST_SetSRID(ST_MakePoint(-1,1), :srid))",
            {"map_layer": child_lyr},
        )
        _update(ctx)

        # Should be a single line in the child layer
        n_lines = db.run_query(
            "SELECT count(*) FROM {data_schema}.linework WHERE map_layer = :map_layer",
            {"map_layer": child_lyr},
        ).scalar()
        assert n_lines == 1

        # But we still have the square in the parent layer, so there should be a face there
        face_info = get_face_info(db, point(0.9, 1), map_layer=parent_lyr)
        assert face_info.face_id != 0
        assert 0 not in get_adjacent_faces(db, face_info.face_id, map_layer=child_lyr)
        assert 0 not in get_adjacent_faces(db, face_info.face_id, map_layer=parent_lyr)

        # Check that we have the expected number of faces
        assert n_face_primitives(db) == 2
        assert n_faces(db, map_layer=child_lyr) == 2
        assert n_faces(db, map_layer=parent_lyr) == 1
        assert n_faces(db) == 3

    def test_merge_faces_again(self, ctx, db, layers):
        child_lyr = layers["child"]

        db.run_query(
            "DELETE FROM {data_schema}.linework WHERE map_layer = :map_layer",
            {"map_layer": child_lyr},
        )
        _update(ctx)

        assert n_edges(db) == 1
        assert n_face_primitives(db) == 1
        assert n_faces(db) == 2

    def test_move_line_to_child_layer(self, ctx, db, layers):
        child_lyr = layers["child"]

        # Move the line to the child layer
        db.run_query(
            "UPDATE {data_schema}.linework SET map_layer = :map_layer WHERE map_layer = :parent_lyr",
            {"map_layer": child_lyr, "parent_lyr": map_layer_id(db, "parent")},
        )
        _update(ctx)

        # The parent layer should no longer have a face
        assert n_face_primitives(db) == 1
        assert n_faces(db) == 1

    def test_grandparent_layer(self, ctx, db, layers):
        grandparent_lyr = layers["grandparent"]

        # Check that the grandparent layer has no faces
        face_info = get_face_info(db, point(0.9, 1), map_layer=grandparent_lyr)
        assert face_info.face_id != 0
        assert 0 in get_adjacent_faces(db, face_info.face_id, map_layer=grandparent_lyr)

        # Insert a square in the grandparent layer
        insert_line(db, square(4, (1, 1)), type="bedrock", map_layer=grandparent_lyr)
        _update(ctx)

        # Check that we have the expected number of edges
        assert n_edges(db) == 2

        # Check that we have the expected number of faces
        assert n_face_primitives(db) == 2
        assert n_faces(db) == (2 + 1 + 1)
