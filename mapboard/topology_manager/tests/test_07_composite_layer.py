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
)
from ..commands.update import _update
from ..commands.update_contacts import _update_contacts
from ..commands.update_faces import n_dirty_faces

log = get_logger(__name__)

grid_count_on_each_axis = 7


@fixture(scope="class")
def layers(db):
    """Fixture to create a composite layer for testing."""
    # Create a parent layer
    grandparent_lyr = create_map_layer(db, "map-area")
    parent_lyr = create_map_layer(db, "tectonic-block", parent=grandparent_lyr)

    db.run_sql(
        """
        INSERT INTO {data_schema}.polygon_type (id)
        VALUES ('unit0'), ('none') ON CONFLICT DO NOTHING;
        """
    )

    _layers = Dict(
        {
            "map-area": grandparent_lyr,
            "tectonic-block": parent_lyr,
            "paleozoic": create_map_layer(db, "paleozoic", parent=parent_lyr),
            "cenozoic": create_map_layer(db, "cenozoic"),
            "surficial": create_map_layer(db, "surficial"),
        }
    )

    # Add a linework types and polygon types
    for lyr in [
        _layers["tectonic-block"],
        _layers.paleozoic,
        _layers.cenozoic,
        _layers.surficial,
    ]:
        add_linework_type_to_layer(db, lyr, "bedrock")
        add_polygon_type_to_layer(db, lyr, "none")
        add_polygon_type_to_layer(db, lyr, "unit0")

    # Create a composite layer placeholder
    _layers["composite"] = create_composite_layer(
        db,
        "composite",
        [_layers.paleozoic, _layers.cenozoic, _layers.surficial],
        parent=_layers["map-area"],
    )

    return _layers


class TestCompositeLayers:
    """We want to be able to create composite layers that build on top of each other, despite
    faces being internally unrelated. This is needed to support the creation of geological
    maps that have overlapping units, such as surficial and bedrock mapping.
    """

    def test_create_bedrock_grid(self, db, layers):
        """Create overlapping sets of lines to test face creation."""
        assert n_faces(db) == 0
        assert n_face_primitives(db) == 0

        create_grid(db, layers.paleozoic, cells_on_each_axis=grid_count_on_each_axis)

        # Solve the faces
        _update(db, composite_layers=False)

        # Check that we have 100 map faces
        assert n_faces(db) == grid_count_on_each_axis**2
        assert n_face_primitives(db) == grid_count_on_each_axis**2

    def test_add_parent_layer(self, db, layers):

        # Insert a line outside of the child layer that encompasses all child faces
        _max = grid_count_on_each_axis + 1

        coords = [
            (-1, -1),
            (_max, -1),
            (_max, _max),
            (-1, _max),
            (-1, -1),
        ]
        insert_line(db, coords, type="bedrock", map_layer=layers["tectonic-block"])

        # Solve the topology
        _update(db, composite_layers=False)

        # Check that we have 102 map faces and one fewer primitive.
        # - The child layer now has 101 faces including the ring outside the 10x10 grid
        # - The parent layer has 1 face that is 12x12 units and encompasses all child faces
        # - Primitives are shared between layers so there are 101

        assert n_face_primitives(db) == grid_count_on_each_axis**2 + 1
        assert n_faces(db) == grid_count_on_each_axis**2 + 2

    def test_composite_layers(self, db, layers):
        """Test the erasure and consolidation of faces."""

        # Delete lines that cover the bottom right corner of the child layer
        # while leaving other lines intact. This should remove 4 faces from the
        db.run_sql(
            """
            UPDATE {data_schema}.linework
            SET geometry = ST_Difference(geometry, ST_MakeEnvelope(0.1, 0.1, 1.98, 1.98, :srid))
            WHERE TYPE = 'bedrock'
              AND map_layer = :child_lyr
            """,
            dict(child_lyr=layers.paleozoic),
        )

        _update(db, composite_layers=False)

        n_child_faces = grid_count_on_each_axis**2 + 1 - 4 + 1

        assert n_faces(db, map_layer=layers.paleozoic) == n_child_faces
        assert n_faces(db, map_layer=layers["tectonic-block"]) == 1

        assert n_faces(db) == grid_count_on_each_axis**2 + 2 - 4 + 1

        expected_n_primitives = grid_count_on_each_axis**2 - 3 + 1

        assert n_face_primitives(db) == expected_n_primitives

        # Now, update the composite layer to reflect the changes

        _update(db)
        # Check that the composite layer has been updated correctly
        assert n_face_primitives(db) == expected_n_primitives
        assert n_faces(db, map_layer=layers.paleozoic) == n_child_faces

        # Composite layers should not have faces as they haven't been identified yet
        assert n_faces(db, map_layer=layers.composite) == 0

        # Identify faces in the unit layer
        for i in range(grid_count_on_each_axis):
            for j in range(grid_count_on_each_axis):
                insert_polygon(
                    db,
                    square(0.2, (i + 0.5, j + 0.5)),
                    type="unit0",
                    map_layer=layers.paleozoic,
                )

        insert_polygon(
            db,
            square(0.2, (-0.5, -0.5)),
            type="unit0",
            map_layer=layers.paleozoic,
        )

        _update(db)

        # identify_faces(
        #     db,
        #     layers.paleozoic,
        #     layers["tectonic-block"],
        #     unit_id="unit0",
        # )

        assert n_faces(db, map_layer=layers.composite) == n_child_faces

    def test_create_surficial_face(self, db, layers):
        """Create a surficial face that overlaps with the bedrock layer."""
        insert_line(
            db, square(4, (4.5, 4.5)), type="bedrock", map_layer=layers.surficial
        )

        # This square will overlap the bedrock layer. It should cover nine entire faces in the bedrock layer,
        # as well as part of 14 other faces.

        # The composite layer should have eight bedrock faces that have areas < 1.0

        # Solve the topology
        _update(db)

        _bedrock_count = grid_count_on_each_axis**2 + 1 - 4 + 1

        # Check that we have created a new face in the surficial layer
        assert n_faces(db, map_layer=layers.surficial) == 1
        assert n_faces(db, map_layer=layers.paleozoic) == _bedrock_count
        # The new surficial face should not be included in the composite layer yet
        assert n_faces(db, map_layer=layers.composite) == _bedrock_count

        insert_polygon(
            db, square(1, (4.5, 4.5)), type="unit0", map_layer=layers.surficial
        )

        _update(db)

        assert n_faces(db, map_layer=layers.composite) == _bedrock_count - 9 + 1

    def test_remove_surficial_face(self, db, layers):

        # Remove the identifier from the surficial face to ensure it is not included in the composite layer
        db.run_sql(
            "UPDATE {data_schema}.polygon SET type='none' WHERE map_layer = :lyr",
            dict(lyr=layers.surficial),
        )

        _update(db)

        _bedrock_count = grid_count_on_each_axis**2 + 1 - 4 + 1

        # Ensure that the face is not identified
        uid = db.run_query(
            "SELECT unit_id FROM {topo_schema}.map_face WHERE map_layer = :lyr",
            dict(lyr=layers.surficial),
        ).scalar()
        assert uid == "none"

        assert n_faces(db, map_layer=layers.composite) == _bedrock_count

    def test_remove_surficial_face_and_add_smaller_one(self, db, layers):
        """Remove the surficial face and add a smaller one."""

        # Delete the surficial face
        db.run_sql(
            """
                DELETE FROM {data_schema}.linework
                WHERE map_layer = :lyr;

                DELETE FROM {data_schema}.polygon
                WHERE map_layer = :lyr;
                """,
            dict(lyr=layers.surficial),
        )

        # Delete bedrock lines (the grid has gotten hard to parse)
        db.run_sql(
            """
            DELETE FROM {data_schema}.linework
            WHERE map_layer = :lyr;
            """,
            dict(lyr=layers.paleozoic),
        )
        ## Reform the grid
        create_grid(db, layers.paleozoic, cells_on_each_axis=grid_count_on_each_axis)

        _update(db)

        _bedrock_count = grid_count_on_each_axis**2 + 1

        assert n_faces(db, map_layer=layers.composite) == _bedrock_count
        assert n_faces(db, map_layer=layers.surficial) == 0

        assert n_dirty_faces(db) == 0

        # Add a smaller surficial face
        insert_line(
            db, square(5, (3.1, 3.1)), type="bedrock", map_layer=layers.surficial
        )

        _update_contacts(db)

        assert n_dirty_faces(db, map_layer=layers.surficial) > 0
        assert n_faces(db, map_layer=layers.surficial) == 0

        _update(db)

        assert n_dirty_faces(db) == 0
        assert n_faces(db, map_layer=layers.surficial) == 1
        # The surficial face does not have a unit_id, so it should not be included in the composite layer
        assert n_faces(db, map_layer=layers.composite) == _bedrock_count

        # Assign a unit_id to the surficial face

        insert_polygon(
            db, square(1, (4.1, 4.1)), type="unit0", map_layer=layers.surficial
        )

        _update(db)

        # We should essentially add the surficial face to the composite layer, removing the sixteen
        # bedrock faces by 16 (the number of faces that are fully covered by the surficial face)

        # Check that the type of the surficial face has been updated
        uid = db.run_query(
            """
            SELECT unit_id
            FROM {topo_schema}.map_face
            WHERE map_layer = :lyr
            """,
            dict(lyr=layers.surficial),
        ).scalar()
        assert uid == "unit0"

        assert n_faces(db, map_layer=layers.surficial) == 1
        assert n_faces(db, map_layer=layers.cenozoic) == 0
        assert n_faces(db, map_layer=layers["tectonic-block"]) == 1
        # Check that the composite layer has been updated correctly
        assert n_faces(db, map_layer=layers.paleozoic) == _bedrock_count

        layers_counts = {
            layers.paleozoic: _bedrock_count - 16,
            layers.surficial: 1,
            layers.cenozoic: 0,
            layers["tectonic-block"]: 0,
        }

        for layer, count in layers_counts.items():
            assert n_faces(db, map_layer=layers.composite, source_layer=layer) == count

        assert n_faces(db, map_layer=layers.composite) == _bedrock_count - 16 + 1


def identify_faces(db, *layers, unit_id="unit0"):
    """Identify all faces in the composite layer."""
    _update(db)
    db.run_sql(
        """
        UPDATE {topo_schema}.map_face
        SET unit_id = :unit_id
        WHERE map_layer = ANY(:layers)
        """,
        dict(
            layers=layers,
            unit_id=unit_id,
        ),
    )
    _update(db)


def test_add_surficial_face_standalone(db, layers):
    """Remove the surficial face and add a smaller one."""
    assert n_faces(db, map_layer=layers.surficial) == 0

    # Add a smaller surficial face
    insert_line(db, square(5, (3.1, 3.1)), type="bedrock", map_layer=layers.surficial)

    _update(db)

    assert n_faces(db, map_layer=layers.surficial) == 1


def _insert_identified(db, size, center, *, map_layer=None):
    """Insert a polygon with an identifier."""

    id = insert_line(db, square(size, center), type="bedrock", map_layer=map_layer)
    insert_polygon(
        db,
        square(0.2, center),
        type="unit0",
        map_layer=map_layer,
    )
    return id


def test_complex_operations(db, layers):
    """Test complex operations with composite layers."""

    insert_line(
        db, square(10, (5, 5)), type="bedrock", map_layer=layers["tectonic-block"]
    )
    insert_polygon(db, square(0.2, (5, 4)), type="unit0", map_layer=layers.paleozoic)

    _update(db)

    assert n_face_primitives(db) == 1
    assert n_faces(db, map_layer=layers.paleozoic) == 1
    assert n_faces(db, map_layer=layers.cenozoic) == 0
    assert n_faces(db, map_layer=layers.composite) == 1

    # Create a new cenozoic face that overlaps with the existing bedrock face
    _insert_identified(db, 2, (2, 2), map_layer=layers.cenozoic)

    _update(db)

    assert n_face_primitives(db) == 2
    assert n_faces(db, map_layer=layers.cenozoic) == 1
    assert n_faces(db, map_layer=layers.paleozoic) == 1
    assert n_faces(db, map_layer=layers.composite) == 2

    sq_ = _insert_identified(db, 2, (3, 3), map_layer=layers.paleozoic)

    _update(db)
    assert n_faces(db, map_layer=layers.paleozoic) == 2
    assert n_faces(db, map_layer=layers.cenozoic) == 1
    assert n_faces(db, map_layer=layers.composite) == 3
    assert n_face_primitives(db) == 4

    # Divide the paleozoic face into two parts by adding a line that overlaps with the existing face
    insert_line(db, ((0, 6), (10, 6)), type="bedrock", map_layer=layers.paleozoic)
    # Identify the other paleozoic face
    insert_polygon(db, square(0.2, (5, 7)), type="unit0", map_layer=layers.paleozoic)

    _update(db)
    assert n_faces(db, map_layer=layers.paleozoic) == 3
    assert n_faces(db, map_layer=layers.cenozoic) == 1
    assert n_faces(db, map_layer=layers.composite) == 4

    # Create a surfcial face that overlaps with the existing faces
    _insert_identified(db, 2, (4, 4), map_layer=layers.surficial)
    _update(db)

    assert n_faces(db, map_layer=layers.surficial) == 1
    assert n_faces(db, map_layer=layers.cenozoic) == 1
    assert n_faces(db, map_layer=layers.composite) == 5

    # Delete the square in the paleozoic layer
    db.run_sql(
        """
        DELETE FROM {data_schema}.linework
        WHERE map_layer = :lyr
          AND id = :id
        """,
        dict(lyr=layers.paleozoic, id=sq_),
    )

    _update(db)

    assert n_faces(db, map_layer=layers.paleozoic) == 2
