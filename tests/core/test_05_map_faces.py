"""Tests to ensure efficient calculations of map faces."""

from macrostrat.utils.timer import Timer
from macrostrat.utils import get_logger

from mapboard.topology_manager import update
from mapboard.topology_manager.test_helpers import (
    insert_line,
    map_layer_id,
    add_linework_type_to_layer,
    n_faces,
    n_face_primitives,
    create_map_layer,
    square,
    insert_polygon,
)
from pytest import mark

log = get_logger(__name__)


def test_isolation(db):
    """Check that we have an empty feature layer"""
    res = db.run_query("SELECT * FROM {data_schema}.linework").fetchall()
    assert len(res) == 0

    res = db.run_query("SELECT * FROM {topo_schema}.map_face").fetchall()
    assert len(res) == 0


class TestMapFaces:
    def test_create_nested_map_layers(self, db):
        """Create a parent and child map layer."""
        parent_lyr = create_map_layer(db, "parent")
        child_lyr = create_map_layer(db, "child", parent=parent_lyr)

        # add a linework type
        add_linework_type_to_layer(db, child_lyr, "bedrock")

    @mark.parametrize("count_on_each_axis", [1, 5, 10])
    def test_create_faces_with_overlapping_lines(self, mgr, db, count_on_each_axis):
        """Create overlapping sets of lines to test face creation."""
        child_lyr = map_layer_id(db, "child")
        parent_lyr = map_layer_id(db, "parent")

        timer = Timer()
        with timer.context():
            for x in range(count_on_each_axis + 1):
                insert_line(
                    db,
                    ((x, 0), (x, count_on_each_axis)),
                    type="bedrock",
                    map_layer=child_lyr,
                )
            for y in range(count_on_each_axis + 1):
                insert_line(
                    db,
                    ((0, y), (count_on_each_axis, y)),
                    type="bedrock",
                    map_layer=child_lyr,
                )

            Timer.add_step("insert-lines")

            # Solve the faces
            update()

            Timer.add_step("update")

            # Check that we have 100 map faces
            assert n_faces(db) == count_on_each_axis**2
            assert n_face_primitives(db) == count_on_each_axis**2

        log.info(timer.server_timings())

    def test_add_parent_layer(self, mgr, db):
        # Add a parent layer with encompassing faces
        parent_lyr = map_layer_id(db, "parent")
        add_linework_type_to_layer(db, parent_lyr, "bedrock")

        # Insert a line outside of the child layer that encompasses all child faces
        coords = [
            (-1, -1),
            (11, -1),
            (11, 11),
            (-1, 11),
            (-1, -1),
        ]
        insert_line(db, coords, type="bedrock", map_layer=parent_lyr)

        # Solve the topology
        update()

        # Check that we have 102 map faces and one fewer primitive.
        # - The child layer now has 101 faces including the ring outside the 10x10 grid
        # - The parent layer has 1 face that is 12x12 units and encompasses all child faces
        # - Primitives are shared between layers so there are 101
        assert n_face_primitives(db) == 101
        assert n_faces(db) == 102

    def test_erase_and_consolidate_faces(self, mgr, db):
        """Test the erasure and consolidation of faces."""
        _child_layer = map_layer_id(db, "child")
        _parent_lyr = map_layer_id(db, "parent")

        # Delete lines that cover the bottom right corner of the child layer
        # while leaving other lines intact. This should remove 4 faces from the
        db.run_sql(
            """
            UPDATE {data_schema}.linework
            SET geometry = ST_Difference(geometry, ST_MakeEnvelope(0.1, 0.1, 1.98, 1.98, :srid))
            WHERE TYPE = 'bedrock'
              AND map_layer = :child_lyr
            """,
            dict(child_lyr=_child_layer),
        )

        update()

        # We should have merged 4 faces into 1 in the child layer
        # - 101-4+1=98 faces in child layer
        # - one face in parent layer
        # - 99 total faces

        assert n_faces(db, map_layer=_child_layer) == 98
        assert n_faces(db, map_layer=_parent_lyr) == 1

        assert n_faces(db) == 99
        assert n_face_primitives(db) == 98


def test_change_map_face_type(mgr, db):
    """Test changing the type of a map face."""

    # Create a face in the 'bedrock' layer
    bedrock_layer = map_layer_id(db, "bedrock")

    insert_line(
        db,
        square(2, center=(0, 0)),
        type="bedrock",
        map_layer=bedrock_layer,
    )
    update()

    # Check that we have one face in the bedrock layer
    assert n_faces(db, map_layer=bedrock_layer) == 1

    # Change the type of the face to 'sedimentary'
    insert_polygon(
        db,
        square(1, center=(0, 0)),
        type="sedimentary",
        map_layer=bedrock_layer,
    )

    update()

    # Check that the face type has changed
    assert n_faces(db, map_layer=bedrock_layer) == 1

    _check_face_type(db, "sedimentary")

    # Change to a different type
    db.run_sql(
        "UPDATE {data_schema}.polygon SET type = 'basement' WHERE map_layer = :layer RETURNING type",
        {"layer": bedrock_layer},
    )
    update()
    _check_face_type(db, "basement")


def _check_face_type(db, expected_type):
    """Check that the face type has changed to the expected type."""
    bedrock_layer = map_layer_id(db, "bedrock")
    res = db.run_query(
        "SELECT unit_id FROM {topo_schema}.map_face WHERE map_layer = :layer",
        {"layer": bedrock_layer},
    ).scalar()
    assert res == expected_type
