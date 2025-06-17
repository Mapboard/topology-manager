"""Tests to ensure efficient calculations of map faces."""

from macrostrat.utils.timer import Timer
from macrostrat.utils import get_logger

from .helpers import insert_line, map_layer_id, add_linework_type_to_layer, n_faces, n_face_primitives, create_map_layer
from ..commands.update import _update
from pytest import mark

log = get_logger(__name__)

parent_layer_name = ("tectonic-block")
child_layer_name = "rocks"

grid_count_on_each_axis = 7

class TestCompositeLayers:
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
        count_on_each_axis = 5
        child_lyr = map_layer_id(db, child_layer_name)

        timer = Timer()
        with timer.context():
            for x in range(grid_count_on_each_axis + 1):
                insert_line(
                    db,
                    ((x, 0), (x, grid_count_on_each_axis)),
                    type="bedrock",
                    map_layer=child_lyr,
                )
            for y in range(grid_count_on_each_axis + 1):
                insert_line(
                    db,
                    ((0, y), (grid_count_on_each_axis, y)),
                    type="bedrock",
                    map_layer=child_lyr,
                )

            Timer.add_step("insert-lines")

            # Solve the faces
            _update(db)

            Timer.add_step("update")

            # Check that we have 100 map faces
            assert n_faces(db) == grid_count_on_each_axis ** 2
            assert n_face_primitives(db) == grid_count_on_each_axis ** 2

        log.info(timer.server_timings())

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

        assert n_faces(db, map_layer=_child_layer) == grid_count_on_each_axis**2 + 1 - 4 + 1
        assert n_faces(db, map_layer=_parent_lyr) == 1

        assert n_faces(db) == grid_count_on_each_axis**2 + 2 - 4 + 1
        assert n_face_primitives(db) == grid_count_on_each_axis**2 - 3 + 1
