"""Tests to ensure efficient calculations of map faces with overlays.

There are two efficient ways to handle this:
1. Accumulate faces the 'naïve' way using overlay layers as barriers.
2. Composite already-existing topogeometries from other layers using set operations.

The second method is likely more efficient, but requires that constituent layers are
already populated.

We've not yet explored the 'naïve' approach but have integrated a _barrier_layers
parameter into the `get_adjacent_faces_core` PostGIS function to allow for this
in the future if desired.
"""

from macrostrat.utils import get_logger
from pytest import fixture, mark
from addict import Dict

from .helpers import (
    insert_line,
    add_linework_type_to_layer,
    n_faces,
    n_face_primitives,
    create_map_layer,
    create_composite_layer,
    create_grid,
    square,
    add_polygon_type_to_layer,
    insert_polygon,
    square,
)
from ..commands.update import _update
from ..commands.update_contacts import _update_contacts
from ..commands.update_faces import n_dirty_faces

log = get_logger(__name__)


@fixture(scope="class")
def layers(db):
    """Fixture to create a composite layer for testing."""
    # Create a parent layer
    db.run_sql(
        """
        INSERT INTO {data_schema}.polygon_type (id)
        VALUES ('unit0'), ('none') ON CONFLICT DO NOTHING;
        """
    )

    _layers = Dict(
        {
            "basement": create_map_layer(db, "basement"),
            "surficial": create_map_layer(db, "surficial"),
        }
    )

    # Add a linework types and polygon types
    for lyr in [
        _layers.basement,
        _layers.surficial,
    ]:
        add_linework_type_to_layer(db, lyr, "bedrock")
        add_polygon_type_to_layer(db, lyr, "none")
        add_polygon_type_to_layer(db, lyr, "unit0")

    # Create a composite layer placeholder
    _layers["composite"] = create_composite_layer(
        db,
        "composite",
        [_layers.basement, _layers.surficial],
    )

    return _layers


def test_lines_in_composite_layer(layers, db):
    """Test that lines in composite layer are updated correctly."""
    insert_line(
        db,
        square(2, (0, 0)),
        type="bedrock",
        map_layer=layers.surficial,
    )
    # Insert a polygon to identify the face
    insert_polygon(db, square(1, (0, 0)), map_layer=layers.surficial, type="unit0")

    # Create a slightly offset face in the basement layer
    insert_line(db, square(2, (1, 1)), map_layer=layers.basement, type="bedrock")
    insert_polygon(db, square(1, (1, 1)), map_layer=layers.basement, type="unit0")

    # Update faces
    _update(db, composite_layers=True)

    # Check that the composite layer has two faces
    assert n_face_primitives(db) == 3
    assert n_faces(db, map_layer=layers.basement) == 1

    assert (
        _get_area(db, map_layer=layers.composite, source_layer=layers.surficial) == 4.0
    )

    # Check the length of the lines in the composite layer
    assert (
        _get_length(db, map_layer=layers.composite, source_layer=layers.surficial)
        == 8.0
    )

    assert (
        _get_length(db, map_layer=layers.composite, source_layer=layers.basement) == 6.0
    )
    assert (
        _get_length(
            db, map_layer=layers.composite, source_layer=layers.basement, covered=True
        )
        == 2.0
    )

    assert (
        _get_area(db, map_layer=layers.composite, source_layer=layers.basement) == 3.0
    )


def _get_length(db, *, map_layer=None, source_layer=None, covered=False):
    """Get the total length of lines in a composite layer."""
    sql = """
    SELECT sum(ST_Length(geometry))
    FROM {data_schema}.linework
    WHERE map_layer = :map_layer
      AND source_layer = :source_layer
    """

    if covered:
        sql += " AND covered"
    else:
        sql += " AND NOT covered"

    return db.run_query(
        sql,
        dict(map_layer=map_layer, source_layer=source_layer),
    ).scalar()


def _get_area(db, *, map_layer, source_layer):
    """Get the total area of polygons in a composite layer."""
    return db.run_query(
        """
        SELECT sum(ST_Area(geometry))
        FROM {topo_schema}.map_face
        WHERE map_layer = :map_layer
          AND source_layer = :source_layer;
        """,
        dict(map_layer=map_layer, source_layer=source_layer),
    ).scalar()
