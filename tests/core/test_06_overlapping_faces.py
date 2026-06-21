"""Tests for map faces that share edges between layers."""

from macrostrat.utils import get_logger
from pytest import fixture, mark
from addict import Dict

from mapboard.topology_manager import update
from mapboard.topology_manager.test_helpers import (
    insert_line,
    add_linework_type_to_layer,
    n_faces,
    create_map_layer,
    square,
    create_grid,
    n_face_primitives,
)
from mapboard.topology_manager.commands.update_faces import n_dirty_faces

log = get_logger(__name__)

parent_layer_name = "tectonic-block"
overlay_layer_name = "overlay"
child_layer_name = "rocks"

grid_count_on_each_axis = 7

###
# Note: there are two possible ways to handle


@fixture(scope="class")
def layers(db):
    """Fixture to create a composite layer for testing."""
    # Create a parent layer
    child_lyr = create_map_layer(db, child_layer_name)

    # Create an overlay layer
    surficial_lyr = create_map_layer(db, overlay_layer_name)

    # Add a linework type to the child layer
    for lyr in [child_lyr, surficial_lyr]:
        add_linework_type_to_layer(db, lyr, "bedrock")

    return Dict(
        {
            "child": child_lyr,
            "overlay": surficial_lyr,
        }
    )


def test_faces_sharing_common_edge(mgr, db, layers):
    """Test that faces sharing an edge are still treated independently."""
    # Create two square faces

    insert_line(db, square(1, (0.5, 0.5)), type="bedrock", map_layer=layers.child)
    insert_line(db, square(1, (1.5, 0.5)), type="bedrock", map_layer=layers.child)

    update()

    assert n_faces(db, map_layer=layers.child) == 2


def test_faces_sharing_common_edge_multilayer(mgr, db, layers):
    """Test that faces sharing an edge are still treated independently."""
    # Create two square faces

    insert_line(db, square(1, (0.5, 0.5)), type="bedrock", map_layer=layers.child)
    insert_line(db, square(1, (1.5, 0.5)), type="bedrock", map_layer=layers.overlay)
    insert_line(db, square(1, (2.5, 0.5)), type="bedrock", map_layer=layers.child)

    mgr.update_contacts()

    assert n_face_primitives(db) == 3
    assert n_dirty_faces(db, map_layer=layers.child) > 0
    assert n_dirty_faces(db, map_layer=layers.overlay) > 0
    assert n_faces(db, map_layer=layers.child) == 0
    assert n_faces(db, map_layer=layers.overlay) == 0

    update()

    assert n_faces(db, map_layer=layers.child) == 2
    assert n_faces(db, map_layer=layers.overlay) == 1


# Parameterize for grids either offset from grid squares or aligned with them
@mark.parametrize("square_center", [(3.1, 3.1), (3.5, 3.5)])
def test_multistage_face_management(mgr, db, layers, square_center):
    """Remove the surficial face and add a smaller one."""
    create_grid(db, layers.child, cells_on_each_axis=grid_count_on_each_axis)
    update()

    assert n_face_primitives(db) == grid_count_on_each_axis**2

    insert_line(db, square(5, square_center), type="bedrock", map_layer=layers.overlay)

    mgr.update_contacts()

    assert n_dirty_faces(db, map_layer=layers.overlay) > 1

    update()

    assert n_faces(db, map_layer=layers.overlay) == 1
    assert n_faces(db, map_layer=layers.child) == grid_count_on_each_axis**2

    # db.run_sql(
    #     """
    #     DELETE FROM {data_schema}.linework
    #     WHERE map_layer = :lyr
    #     """,
    #     dict(lyr=layers.overlay),
    # )
    #
    # _update(ctx)
    #
    # assert n_faces(db, map_layer=layers.overlay) == 0
    #
    # assert n_dirty_faces(db) == 0
    #
    # # Add a smaller surficial face
    # insert_line(db, square(5, square_center), type="bedrock", map_layer=layers.overlay)
    #
    # _update_contacts(db)
    #
    # assert n_dirty_faces(db, map_layer=layers.overlay) > 0
    #
    # assert n_faces(db, map_layer=layers.overlay) == 0
    #
    # _update(ctx)
    #
    # assert n_dirty_faces(db) == 0
    # assert n_faces(db, map_layer=layers.overlay) == 1
