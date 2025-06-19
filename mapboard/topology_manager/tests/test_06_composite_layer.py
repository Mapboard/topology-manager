"""Tests to ensure efficient calculations of map faces."""

from macrostrat.utils.timer import Timer
from macrostrat.utils import get_logger
from collections import defaultdict

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
from time import perf_counter
from ..commands.update_faces.helpers import (
    update_map_face_python,
    delete_map_faces,
    unmark_dirty_faces,
    create_map_face,
    FaceUpdateResult,
    containing_map_faces,
    get_face_primitives,
)
from ..database import get_database, sql

log = get_logger(__name__)

parent_layer_name = "tectonic-block"
child_layer_name = "rocks"

grid_count_on_each_axis = 7


class TestCompositeLayers:
    """We want to be able to create composite layers that build on top of each other, despite
    faces being internally unrelated. This is needed to support the creation of geological
    maps that have overlapping units, such as surficial and bedrock mapping.
    """

    def test_create_nested_map_layers(self, db):
        """Create a parent and child map layer."""
        grandparent_lyr = create_map_layer(db, "map-area")
        parent_lyr = create_map_layer(db, parent_layer_name, parent=grandparent_lyr)
        child_lyr = create_map_layer(db, child_layer_name, parent=parent_lyr)

        surficial_lyr = create_map_layer(db, "surficial", parent=grandparent_lyr)

        # add a linework type
        add_linework_type_to_layer(db, child_lyr, "bedrock")

    def test_create_bedrock_grid(self, db):
        """Create overlapping sets of lines to test face creation."""
        child_lyr = map_layer_id(db, child_layer_name)

        for val in range(grid_count_on_each_axis + 1):
            insert_line(
                db,
                ((val, 0), (val, grid_count_on_each_axis)),
                type="bedrock",
                map_layer=child_lyr,
            )
            insert_line(
                db,
                ((0, val), (grid_count_on_each_axis, val)),
                type="bedrock",
                map_layer=child_lyr,
            )

        # Solve the faces
        _update(db)

        # Check that we have 100 map faces
        assert n_faces(db) == grid_count_on_each_axis**2
        assert n_face_primitives(db) == grid_count_on_each_axis**2

    def test_add_parent_layer(self, db):
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
        insert_line(db, coords, type="bedrock", map_layer=parent_lyr)

        # Solve the topology
        _update(db)

        # Check that we have 102 map faces and one fewer primitive.
        # - The child layer now has 101 faces including the ring outside the 10x10 grid
        # - The parent layer has 1 face that is 12x12 units and encompasses all child faces
        # - Primitives are shared between layers so there are 101

        assert n_face_primitives(db) == grid_count_on_each_axis**2 + 1
        assert n_faces(db) == grid_count_on_each_axis**2 + 2

    def test_erase_and_consolidate_faces(self, db):
        """Test the erasure and consolidation of faces."""
        _child_layer = map_layer_id(db, child_layer_name)
        _parent_lyr = map_layer_id(db, parent_layer_name)

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

        _update(db)

        assert (
            n_faces(db, map_layer=_child_layer)
            == grid_count_on_each_axis**2 + 1 - 4 + 1
        )
        assert n_faces(db, map_layer=_parent_lyr) == 1

        assert n_faces(db) == grid_count_on_each_axis**2 + 2 - 4 + 1
        assert n_face_primitives(db) == grid_count_on_each_axis**2 - 3 + 1

    def test_create_surficial_face(self, db):
        """Create a surficial face that overlaps with the bedrock layer."""
        surficial_lyr = map_layer_id(db, "surficial")

        # Add a linework type
        add_linework_type_to_layer(db, surficial_lyr, "bedrock")

        insert_line(
            db, square(2, (3.5, 3.5)), type="surficial", map_layer=surficial_lyr
        )
        # This square will overlap the bedrock layer. It should cover one entire face in the bedrock layer,
        # as well as part of eight other faces.

        # The composite layer should have eight bedrock faces that have areas < 1.0

        # Solve the topology
        _update(db)

        # Check that we have created a new face in the surficial layer
        assert n_faces(db, map_layer=surficial_lyr) == 1

    def test_create_composite_layer(self, db):
        """Create a composite layer that includes the bedrock and surficial layers."""
        grandparent_lyr = map_layer_id(db, "map-area")
        parent_lyr = map_layer_id(db, parent_layer_name)
        child_lyr = map_layer_id(db, child_layer_name)
        surficial_lyr = map_layer_id(db, "surficial")

        # Create a composite layer placeholder
        composite_lyr = create_map_layer(
            db,
            "composite",
            parent=grandparent_lyr,
        )
        # This composite layer will be 'derived' from the bedrock and surficial layers.
        # It does not have geometries of its own. It's also not a 'parent' in the hierarchy,
        # but is its own special type of layer.

        # Solve the topology
        _update(db)

        # Check that we have created a new face in the composite layer
        assert n_faces(db, map_layer=composite_lyr) == 0

        update_composite_layer(db, composite_lyr, [child_lyr, surficial_lyr])

        assert n_faces(db, map_layer=composite_lyr) > 5


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

    reversed_layers = list(reversed(layers))

    # We can now trust that the composite layer is populated for each constituent layer.
    # For now we set all faces as dirty...
    all_faces = [
        int(face_id)
        for face_id in db.run_query(
            """
        SELECT face_id FROM {topo_schema}.face_data
        """,
            dict(map_layer=map_layer),
        ).scalars()
    ]

    # Delete faces in the composite layer that overlap any dirty face
    existing_map_faces = list(containing_map_faces(db, all_faces, map_layer))
    delete_map_faces(db, existing_map_faces)
    # We may need to add the entire geometry of any dirty face to the dirty faces for the composite layer.

    # Now we can update the composite layer with the faces from the constituent layers

    # start with the topmost layer - this face just goes in as-is
    topmost_layer = reversed_layers[0]

    topmost_map_faces = list(containing_map_faces(db, all_faces, topmost_layer))

    assert n_faces(db, map_layer=topmost_layer) == 1

    # Insert the topmost layer's faces into the composite layer

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
