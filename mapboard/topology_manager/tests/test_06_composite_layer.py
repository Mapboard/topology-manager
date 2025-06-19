"""Tests to ensure efficient calculations of map faces."""

from macrostrat.utils import get_logger
from pytest import fixture
from addict import Dict

from .helpers import (
    insert_line,
    map_layer_id,
    add_linework_type_to_layer,
    n_faces,
    n_face_primitives,
    create_map_layer,
    square,
)
from ..commands.update import _update
from ..commands.update_faces.helpers import (
    FaceUpdateResult,
)
from ..database import get_database, sql

log = get_logger(__name__)

parent_layer_name = "tectonic-block"
overlay_layer_name = "overlay"
child_layer_name = "rocks"

grid_count_on_each_axis = 7


@fixture(scope="class")
def layers(db):
    """Fixture to create a composite layer for testing."""
    # Create a parent layer
    grandparent_lyr = create_map_layer(db, "map-area")
    parent_lyr = create_map_layer(db, parent_layer_name, parent=grandparent_lyr)
    child_lyr = create_map_layer(db, child_layer_name, parent=parent_lyr)

    # Create an overlay layer
    surficial_lyr = create_map_layer(db, overlay_layer_name, parent=grandparent_lyr)

    # Add a linework type to the child layer
    for lyr in [parent_lyr, child_lyr, surficial_lyr]:
        add_linework_type_to_layer(db, lyr, "bedrock")

    # Create a composite layer placeholder
    composite_lyr = create_map_layer(
        db,
        "composite",
        parent=grandparent_lyr,
    )

    return Dict(
        {
            "grandparent": grandparent_lyr,
            "parent": parent_lyr,
            "child": child_lyr,
            "overlay": surficial_lyr,
            "composite": composite_lyr,
        }
    )


class TestCompositeLayers:
    """We want to be able to create composite layers that build on top of each other, despite
    faces being internally unrelated. This is needed to support the creation of geological
    maps that have overlapping units, such as surficial and bedrock mapping.
    """

    def test_create_bedrock_grid(self, db, layers):
        """Create overlapping sets of lines to test face creation."""
        for val in range(grid_count_on_each_axis + 1):
            insert_line(
                db,
                ((val, 0), (val, grid_count_on_each_axis)),
                type="bedrock",
                map_layer=layers.child,
            )
            insert_line(
                db,
                ((0, val), (grid_count_on_each_axis, val)),
                type="bedrock",
                map_layer=layers.child,
            )

        # Solve the faces
        _update(db)

        # Check that we have 100 map faces
        assert n_faces(db) == grid_count_on_each_axis**2
        assert n_face_primitives(db) == grid_count_on_each_axis**2

    def test_add_parent_layer(self, db, layers):
        # Add a parent layer with encompassing faces
        parent_lyr = map_layer_id(db, parent_layer_name)
        add_linework_type_to_layer(db, parent_lyr, "bedrock")

        # Insert a line outside of the child layer that encompasses all child faces
        _max = grid_count_on_each_axis + 1

        coords = [
            (-1, -1),
            (_max, -1),
            (_max, _max),
            (-1, _max),
            (-1, -1),
        ]
        insert_line(db, coords, type="bedrock", map_layer=layers.parent)

        # Solve the topology
        _update(db)

        # Check that we have 102 map faces and one fewer primitive.
        # - The child layer now has 101 faces including the ring outside the 10x10 grid
        # - The parent layer has 1 face that is 12x12 units and encompasses all child faces
        # - Primitives are shared between layers so there are 101

        assert n_face_primitives(db) == grid_count_on_each_axis**2 + 1
        assert n_faces(db) == grid_count_on_each_axis**2 + 2

    def test_erase_and_consolidate_faces(self, db, layers):
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
            dict(child_lyr=layers.child),
        )

        _update(db)

        assert (
            n_faces(db, map_layer=layers.child)
            == grid_count_on_each_axis**2 + 1 - 4 + 1
        )
        assert n_faces(db, map_layer=layers.parent) == 1

        assert n_faces(db) == grid_count_on_each_axis**2 + 2 - 4 + 1
        assert n_face_primitives(db) == grid_count_on_each_axis**2 - 3 + 1

    def test_create_surficial_face(self, db, layers):
        """Create a surficial face that overlaps with the bedrock layer."""
        insert_line(db, square(4, (4.5, 4.5)), type="bedrock", map_layer=layers.overlay)
        # This square will overlap the bedrock layer. It should cover nine entire faces in the bedrock layer,
        # as well as part of 14 other faces.

        # The composite layer should have eight bedrock faces that have areas < 1.0

        # Solve the topology
        _update(db)

        # Check that we have created a new face in the surficial layer
        assert n_faces(db, map_layer=layers.overlay) == 1

    def test_create_composite_layer(self, db, layers):
        """Create a composite layer that includes the bedrock and surficial layers."""

        # This composite layer will be 'derived' from the bedrock and surficial layers.
        # It does not have geometries of its own. It's also not a 'parent' in the hierarchy,
        # but is its own special type of layer.

        # Solve the topology
        _update(db)

        # Check that we have created a new face in the composite layer
        assert n_faces(db, map_layer=layers.composite) == 0

        update_composite_layer(db, layers.composite, [layers.child, layers.overlay])

        _bedrock_count = grid_count_on_each_axis**2 + 1 - 4 + 1
        assert n_faces(db, map_layer=layers.child) == _bedrock_count

        assert n_faces(db, map_layer=layers.composite) == _bedrock_count - 9 + 1

    def test_remove_surficial_face_and_add_smaller_one(self, db, layers):
        """Remove the surficial face and add a smaller one."""
        db.run_sql(
            """
            DELETE FROM {data_schema}.linework
            WHERE map_layer = :lyr
            """,
            dict(lyr=layers.overlay),
        )

        update_composite_layer(
            db,
            map_layer=layers.composite,
            layers=[layers.child, layers.overlay],
        )

        _bedrock_count = grid_count_on_each_axis**2 - 4 + 1 + 1

        assert n_faces(db, map_layer=layers.composite) == _bedrock_count

        assert n_faces(db, map_layer=layers.overlay) == 0

        # Add a smaller surficial face
        insert_line(db, square(5, (3.5, 3.5)), type="bedrock", map_layer=layers.overlay)

        _update(db)

        assert n_faces(db, map_layer=layers.overlay) == 1

        update_composite_layer(
            db,
            map_layer=layers.composite,
            layers=[layers.child, layers.overlay],
        )

        # Check that the composite layer has been updated correctly
        assert n_faces(db, map_layer=layers.child) == _bedrock_count
        assert n_faces(db, map_layer=layers.overlay) == 1


def update_composite_layer(db, map_layer: int, layers: list[int]) -> FaceUpdateResult:
    """Update a composite layer by merging faces from the specified layers."""

    # Ensure that the composite layer has all the necessary linework/polygon types
    db.run_sql(
        """
    INSERT INTO {data_schema}.map_layer_linework_type (map_layer, "type")
    SELECT :map_layer, "type"
    FROM {data_schema}.map_layer_linework_type
    WHERE map_layer = ANY (:layers)
    ON CONFLICT DO NOTHING;

    INSERT INTO {data_schema}.map_layer_polygon_type (map_layer, "type")
    SELECT :map_layer, "type"
    FROM {data_schema}.map_layer_polygon_type
    WHERE map_layer = ANY (:layers)
    ON CONFLICT DO NOTHING;
    """,
        dict(map_layer=map_layer, layers=layers),
    )

    _update(db)

    # We can now trust that the composite layer is populated for each constituent layer.
    # For now we set all faces as dirty...

    db.run_sql(
        "DELETE FROM {topo_schema}.map_face WHERE map_layer = :map_layer",
        dict(map_layer=map_layer),
    )

    _update(db)

    # We may need to add the entire geometry of any dirty face to the dirty faces for the composite layer.

    # Insert the topmost layer's faces into the composite layer
    reversed_layers = list(reversed(layers))

    # Get intersecting with dirty map faces...
    overlay_layers = []
    for layer in reversed_layers:
        log.info("Updating composite layer with faces from layer %s", layer)
        ids = db.run_query(
            sql("procedures/update-faces/update-composite-face-elements"),
            dict(
                map_layer=layer,
                overlay_layers=overlay_layers,
                composite_layer=map_layer,
            ),
        ).scalars()
        _n_faces = len(list(ids))
        overlay_layers.append(layer)
        log.info("Inserted %s map faces from layer %s", _n_faces, layer)
