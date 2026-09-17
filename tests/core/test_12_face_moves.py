"""Moving primitives between map faces in linework mode (issue #27).

A parent-layer face spans every primitive that child-layer lines carve out of it.
Historically each child edit deleted and recreated the parent face; in `move`
mode the parent face keeps its row and only the changed primitives are
re-resolved. Both modes must keep the geometry consistent with the topology and
leave no orphaned relation rows.
"""

from pytest import fixture

from mapboard.topology_manager import update
from mapboard.topology_manager.config import FaceUpdateMode
from mapboard.topology_manager.test_helpers import (
    add_linework_type_to_layer,
    create_map_layer,
    faces_mismatching_topology,
    insert_line,
    n_face_primitives,
    n_faces,
    orphaned_relations,
    square,
)


@fixture(scope="class")
def layers(db):
    parent = create_map_layer(db, "moves-parent")
    child = create_map_layer(db, "moves-child", parent=parent)
    for lyr in (parent, child):
        add_linework_type_to_layer(db, lyr, "bedrock")
    return {"parent": parent, "child": child}


def _face_ids(db, layer):
    return set(
        db.run_query(
            "SELECT id FROM {topo_schema}.map_face WHERE map_layer = :layer",
            dict(layer=layer),
        ).scalars()
    )


def _primitives(db, map_face_id):
    return set(
        db.run_query(
            """
            SELECT r.element_id
            FROM {topo_schema}.map_face mf
            JOIN {topo_schema}.relation r
              ON r.topogeo_id = (mf.topo).id
             AND r.layer_id = (mf.topo).layer_id
             AND r.element_type = 3
            WHERE mf.id = :id
            """,
            dict(id=map_face_id),
        ).scalars()
    )


def _check_invariants(db):
    assert orphaned_relations(db) == 0
    assert faces_mismatching_topology(db) == []


class TestSplitAndMergeUnderParent:
    def test_parent_square(self, mgr, db, layers):
        insert_line(db, square(4, (2, 2)), type="bedrock", map_layer=layers["parent"])
        update()
        assert n_face_primitives(db) == 1
        assert n_faces(db, map_layer=layers["parent"]) == 1
        assert n_faces(db, map_layer=layers["child"]) == 1
        _check_invariants(db)

    def test_child_line_splits_primitive(self, mgr, db, layers):
        """A child line splits the primitive; the parent face spans both halves."""
        mode = mgr.ctx.face_update_mode
        (parent_before,) = _face_ids(db, layers["parent"])

        insert_line(db, [(2, -1), (2, 5)], type="bedrock", map_layer=layers["child"])
        update()

        assert n_face_primitives(db) == 2
        assert n_faces(db, map_layer=layers["child"]) == 2
        assert n_faces(db, map_layer=layers["parent"]) == 1
        (parent_after,) = _face_ids(db, layers["parent"])
        assert len(_primitives(db, parent_after)) == 2
        _check_invariants(db)

        if mode == FaceUpdateMode.MOVE:
            # The parent face gained a primitive instead of being recreated
            assert parent_after == parent_before

    def test_second_child_line(self, mgr, db, layers):
        mode = mgr.ctx.face_update_mode
        (parent_before,) = _face_ids(db, layers["parent"])
        child_before = _face_ids(db, layers["child"])

        insert_line(db, [(-1, 2), (5, 2)], type="bedrock", map_layer=layers["child"])
        update()

        assert n_face_primitives(db) == 4
        assert n_faces(db, map_layer=layers["child"]) == 4
        assert n_faces(db, map_layer=layers["parent"]) == 1
        _check_invariants(db)

        if mode == FaceUpdateMode.MOVE:
            (parent_after,) = _face_ids(db, layers["parent"])
            assert parent_after == parent_before
            # Each split child face keeps its row for one half of itself
            assert child_before <= _face_ids(db, layers["child"])

    def test_remove_child_lines(self, mgr, db, layers):
        """Removing the child lines merges the primitives back together."""
        mode = mgr.ctx.face_update_mode
        (parent_before,) = _face_ids(db, layers["parent"])

        db.run_query(
            "DELETE FROM {data_schema}.linework WHERE map_layer = :layer",
            dict(layer=layers["child"]),
        )
        update()

        assert n_face_primitives(db) == 1
        assert n_faces(db, map_layer=layers["child"]) == 1
        assert n_faces(db, map_layer=layers["parent"]) == 1
        _check_invariants(db)

        if mode == FaceUpdateMode.MOVE:
            (parent_after,) = _face_ids(db, layers["parent"])
            assert parent_after == parent_before

    def test_remove_parent_line(self, mgr, db, layers):
        """Removing the square releases everything to the universal face."""
        db.run_query(
            "DELETE FROM {data_schema}.linework WHERE map_layer = :layer",
            dict(layer=layers["parent"]),
        )
        update()
        assert n_faces(db, map_layer=layers["parent"]) == 0
        assert n_faces(db, map_layer=layers["child"]) == 0
        _check_invariants(db)
