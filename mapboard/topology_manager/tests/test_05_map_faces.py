"""Tests to ensure efficient calculations of map faces."""

from macrostrat.database import Database
from macrostrat.utils.timer import Timer
from macrostrat.utils import get_logger

from .helpers import insert_line, map_layer_id, add_linework_type_to_layer, n_faces, n_face_primitives
from ..commands.update import _update
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
    def test_create_faces_with_overlapping_lines(self, db, count_on_each_axis):
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
            _update(db)

            Timer.add_step("update")

            # Check that we have 100 map faces
            assert n_faces(db) == count_on_each_axis ** 2
            assert n_face_primitives(db) == count_on_each_axis ** 2

        log.info(timer.server_timings())

    def test_add_parent_layer(self, db):
        # Add a parent layer with encompassing faces
        parent_lyr = map_layer_id(db, "parent")
        add_linework_type_to_layer(db, parent_lyr, "bedrock")

        # Insert a line outside of the child layer
        coords = [
            (-1, -1),
            (11, -1),
            (11, 11),
            (-1, 11),
            (-1, -1),
        ]
        insert_line(db, coords, type="bedrock", map_layer=parent_lyr)

        # Solve the topology
        _update(db)

        # Check that we have 102 map faces and one fewer primitive
        assert n_faces(db) == 102
        assert n_face_primitives(db) == 101

    def test_erase_and_consolidate_faces(self, db):
        """Test the erasure and consolidation of faces."""
        _child_layer = map_layer_id(db, "child")

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

        # We should have merged 4 faces into 1
        # - one face in parent layer
        # - 100-4+1=97 faces in child layer
        assert n_faces(db) == 99
        assert n_face_primitives(db) == 98


def create_map_layer(db: Database, name: str, parent: int = None):
    lyr = db.run_query(
        """
        INSERT INTO {data_schema}.map_layer (NAME, topological, parent)
        VALUES (:name, :topological, :parent)
        RETURNING id
        """,
        {"name": name, "topological": True, "parent": parent},
    ).scalar()
    return lyr
