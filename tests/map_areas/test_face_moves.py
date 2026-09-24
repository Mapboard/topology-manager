"""Moving primitives between map faces (issue #27).

A host that drives this library with a `direct` identity strategy flags stale
identity by inserting primitives into `dirty_face` — e.g. when a region flips
from map A to map B because their priorities changed. These tests pin the
contract for that flow in `move` mode:

- every identified primitive belongs to exactly one map face (no holes),
- one map face per connected same-identity component (shedding can split),
- no orphaned `relation` rows, and cached geometry matches the topology.
- untouched faces keep their ids.

`replace` mode is the historical behaviour (bulk delete and recreate, no
re-marking) and is not held to these.
"""

from pytest import fixture
from shapely.geometry import Point

from mapboard.topology_manager import TopologyInspector
from mapboard.topology_manager.commands.update_faces import update_faces
from mapboard.topology_manager.commands.update_topology import update
from mapboard.topology_manager.config import FaceUpdateMode

from .support import (
    add_map,
    face_primitives,
    geom,
    map_faces,
    mark_dirty,
    set_priority,
)


@fixture(scope="class")
def face_update_mode():
    """Move mode only, overriding the suite's run over every mode. `replace` is
    the historical behaviour by design -- including leaving a partly-covered
    face's remainder without a face -- so these contracts do not apply to it,
    and generating replace-mode copies only to skip them reports nothing."""
    return FaceUpdateMode.MOVE


def _check_invariants(insp: TopologyInspector, layer: int):
    assert insp.orphaned_relations() == 0
    assert insp.unfaced_primitives(layer) == []
    assert insp.faces_match_topology(map_layer=layer)
    assert insp.n_dirty_faces(layer) == 0


class TestPartialReprioritization:
    """Two overlapping maps; the overlap flips from the first map to the second."""

    @fixture(scope="class")
    def maps(self, ctx):
        db = ctx.database
        insp = TopologyInspector(ctx)
        layer = insp.map_layer_id("Large")
        # A wins the overlap at first (a lower priority value wins)
        a = add_map(db, "ST_MakeEnvelope(0, 0, 3, 3)", "large", priority=0)
        b = add_map(db, "ST_MakeEnvelope(2, 0, 5, 3)", "large", priority=1)
        update(ctx, composite_layers=False)
        return dict(a=a, b=b, layer=layer)

    def test_initial_state(self, ctx, maps):
        db = ctx.database
        insp = TopologyInspector(ctx)
        layer = maps["layer"]
        assert insp.n_face_primitives() == 3
        faces = map_faces(db, layer)
        assert len(faces) == 2
        by_map = {f.map_id: f for f in faces}
        assert by_map[maps["a"]].area == 9  # A's whole footprint, overlap included
        assert by_map[maps["b"]].area == 6  # B minus the overlap
        _check_invariants(insp, layer)

    def test_flip_leaves_no_hole(self, ctx, maps):
        """After the flip every identified primitive is in exactly one face, and
        the loser's remainder is not left faceless."""
        db = ctx.database
        insp = TopologyInspector(ctx)
        layer = maps["layer"]

        before = {f.map_id: f for f in map_faces(db, layer)}
        overlap = insp.get_face_id(geom(Point(2.5, 1.5)))
        assert overlap in face_primitives(db, before[maps["a"]].id)

        # B now wins the overlap; the host flags the stale primitive
        set_priority(db, maps["b"], -1)
        mark_dirty(db, [overlap], layer)
        update(ctx, composite_layers=False)

        after = {f.map_id: f for f in map_faces(db, layer)}
        # Two connected same-identity components: B's whole footprint and A's remainder
        assert insp.n_faces(map_layer=layer) == 2
        assert set(after) == {maps["a"], maps["b"]}
        assert after[maps["b"]].area == 9
        assert after[maps["a"]].area == 6
        assert overlap in face_primitives(db, after[maps["b"]].id)
        _check_invariants(insp, layer)

        # Untouched faces keep their ids when primitives are moved
        assert after[maps["b"]].id == before[maps["b"]].id
        assert after[maps["a"]].id == before[maps["a"]].id

    def test_flip_back(self, ctx, maps):
        """Flipping back restores the original partition."""
        db = ctx.database
        insp = TopologyInspector(ctx)
        layer = maps["layer"]

        before = {f.map_id: f for f in map_faces(db, layer)}
        overlap = insp.get_face_id(geom(Point(2.5, 1.5)))
        set_priority(db, maps["b"], 1)
        mark_dirty(db, [overlap], layer)
        update(ctx, composite_layers=False)

        after = {f.map_id: f for f in map_faces(db, layer)}
        assert after[maps["a"]].area == 9
        assert after[maps["b"]].area == 6
        _check_invariants(insp, layer)
        assert after[maps["a"]].id == before[maps["a"]].id
        assert after[maps["b"]].id == before[maps["b"]].id


class TestSheddingCanSplit:
    """A bar-shaped map overlapped in the middle by a higher-priority map."""

    @fixture(scope="class")
    def maps(self, ctx):
        db = ctx.database
        insp = TopologyInspector(ctx)
        layer = insp.map_layer_id("Large")
        bar = add_map(db, "ST_MakeEnvelope(0, 0, 6, 2)", "large", priority=0)
        cross = add_map(db, "ST_MakeEnvelope(2, -1, 4, 3)", "large", priority=1)
        update(ctx, composite_layers=False)
        return dict(bar=bar, cross=cross, layer=layer)

    def test_initial_state(self, ctx, maps):
        db = ctx.database
        insp = TopologyInspector(ctx)
        layer = maps["layer"]
        # bar-left, bar-middle, bar-right, cross-top, cross-bottom
        assert insp.n_face_primitives() == 5
        faces = map_faces(db, layer)
        # The bar is one face; the cross's two stubs are disconnected → two faces
        assert len([f for f in faces if f.map_id == maps["bar"]]) == 1
        assert len([f for f in faces if f.map_id == maps["cross"]]) == 2
        _check_invariants(insp, layer)

    def test_flip_splits_the_bar(self, ctx, maps):
        db = ctx.database
        insp = TopologyInspector(ctx)
        layer = maps["layer"]

        before = {f.id: f for f in map_faces(db, layer)}
        middle = insp.get_face_id(geom(Point(3, 1)))

        set_priority(db, maps["cross"], -1)
        mark_dirty(db, [middle], layer)
        update(ctx, composite_layers=False)

        faces = map_faces(db, layer)
        bar_faces = [f for f in faces if f.map_id == maps["bar"]]
        cross_faces = [f for f in faces if f.map_id == maps["cross"]]
        # The bar's remainder is two disconnected pieces; the cross is now one component
        assert len(bar_faces) == 2
        assert sorted(f.area for f in bar_faces) == [4, 4]
        assert len(cross_faces) == 1
        assert cross_faces[0].area == 8
        assert insp.n_faces(map_layer=layer) == 3
        _check_invariants(insp, layer)

        # One of the bar's pieces keeps the old row; the other is new
        old_bar_ids = {f.id for f in before.values() if f.map_id == maps["bar"]}
        assert len(old_bar_ids & {f.id for f in bar_faces}) == 1
        # The cross survives in one of its old rows
        old_cross_ids = {f.id for f in before.values() if f.map_id == maps["cross"]}
        assert cross_faces[0].id in old_cross_ids


class TestInnerMapFlip:
    """A small map entirely inside a big one starts out losing, then wins."""

    @fixture(scope="class")
    def maps(self, ctx):
        db = ctx.database
        insp = TopologyInspector(ctx)
        layer = insp.map_layer_id("Large")
        big = add_map(db, "ST_MakeEnvelope(0, 0, 10, 10)", "large", priority=0)
        # subdivide the big map so its face has several primitives
        for i in range(5):
            add_map(db, f"ST_MakeEnvelope({2*i}, 0, {2*i+2}, 10)", "medium")
        inner = add_map(db, "ST_MakeEnvelope(0, 0, 2, 4)", "large", priority=1)
        update(ctx, composite_layers=False)
        return dict(big=big, inner=inner, layer=layer)

    def test_initial_state(self, ctx, maps):
        db = ctx.database
        insp = TopologyInspector(ctx)
        faces = map_faces(db, maps["layer"])
        assert [f.map_id for f in faces] == [maps["big"]]
        assert faces[0].area == 100
        _check_invariants(insp, maps["layer"])

    def test_inner_map_wins(self, ctx, maps):
        """The big face keeps its row (and most of its primitives); the inner
        map gets a new face."""
        db = ctx.database
        insp = TopologyInspector(ctx)
        layer = maps["layer"]
        (big_before,) = map_faces(db, layer)
        inner_face = insp.get_face_id(geom(Point(1, 1)))

        set_priority(db, maps["inner"], -1)
        mark_dirty(db, [inner_face], layer)
        update(ctx, composite_layers=False)

        after = {f.map_id: f for f in map_faces(db, layer)}
        assert set(after) == {maps["big"], maps["inner"]}
        assert after[maps["inner"]].area == 8
        assert after[maps["big"]].area == 92
        _check_invariants(insp, layer)
        assert after[maps["big"]].id == big_before.id


class TestNotchAndWall:
    """Shedding from a big face: a notch leaves one remainder, a wall splits it."""

    @fixture(scope="class")
    def maps(self, ctx):
        db = ctx.database
        insp = TopologyInspector(ctx)
        layer = insp.map_layer_id("Large")
        big = add_map(db, "ST_MakeEnvelope(0, 0, 10, 10)", "large", priority=0)
        for i in range(5):
            add_map(db, f"ST_MakeEnvelope({2*i}, 0, {2*i+2}, 10)", "medium")
        corner = add_map(db, "ST_MakeEnvelope(0, 0, 2, 4)", "large", priority=1)
        bar = add_map(db, "ST_MakeEnvelope(4, 3, 6, 7)", "large", priority=1)
        update(ctx, composite_layers=False)
        return dict(big=big, corner=corner, bar=bar, layer=layer)

    def _flip(self, ctx, maps, map_id, priority, point, mode):
        db = ctx.database
        insp = TopologyInspector(ctx)
        set_priority(db, map_id, priority)
        mark_dirty(db, [insp.get_face_id(geom(point))], maps["layer"])
        stats = update_faces(ctx, face_update_mode=mode, incremental=False)
        _check_invariants(insp, maps["layer"])
        return stats

    def test_corner_notch(self, ctx, maps, face_update_mode):
        db = ctx.database
        insp = TopologyInspector(ctx)
        (big_before,) = map_faces(db, maps["layer"])
        self._flip(ctx, maps, maps["corner"], -1, Point(1, 1), face_update_mode)
        assert insp.n_faces(map_layer=maps["layer"]) == 2
        big_faces = [f for f in map_faces(db, maps["layer"]) if f.map_id == maps["big"]]
        assert len(big_faces) == 1 and big_faces[0].area == 92
        assert big_faces[0].id == big_before.id

    def test_middle_notch(self, ctx, maps, face_update_mode):
        """A map that only notches the big map leaves one connected remainder."""
        db = ctx.database
        insp = TopologyInspector(ctx)
        self._flip(ctx, maps, maps["bar"], -1, Point(5, 5), face_update_mode)
        assert insp.n_faces(map_layer=maps["layer"]) == 3
        big_faces = [f for f in map_faces(db, maps["layer"]) if f.map_id == maps["big"]]
        assert len(big_faces) == 1
        assert big_faces[0].area == 100 - 8 - 8

    def test_wall_splits(self, ctx, maps, face_update_mode):
        """A map spanning the full height splits the big map's remainder."""
        db = ctx.database
        wall = add_map(db, "ST_MakeEnvelope(6, -1, 8, 11)", "large", priority=1)
        update(ctx, composite_layers=False)  # wall loses at first
        stats = self._flip(ctx, maps, wall, -1, Point(7, 5), face_update_mode)
        big_faces = [f for f in map_faces(db, maps["layer"]) if f.map_id == maps["big"]]
        assert len(big_faces) == 2
        assert stats.reseeded > 0


class TestAddingMaps:
    """The ordinary flow — adding maps — keeps the same invariants, and in move
    mode leaves faces that were not affected untouched."""

    def test_add_maps_incrementally(self, ctx):
        db = ctx.database
        insp = TopologyInspector(ctx)
        layer = insp.map_layer_id("Large")

        add_map(db, "ST_MakeEnvelope(0, 0, 2, 2)", "large")
        far = add_map(db, "ST_MakeEnvelope(10, 10, 12, 12)", "large")
        update(ctx, composite_layers=False)
        assert insp.n_faces(map_layer=layer) == 2
        _check_invariants(insp, layer)
        far_face = next(f for f in map_faces(db, layer) if f.map_id == far)

        # A newer map (same priority → newest wins) overlapping the first one
        add_map(db, "ST_MakeEnvelope(1, 1, 3, 3)", "large")
        update(ctx, composite_layers=False)
        assert insp.n_faces(map_layer=layer) == 3
        _check_invariants(insp, layer)
        assert (
            next(f for f in map_faces(db, layer) if f.map_id == far).id == far_face.id
        )

        # Composite layers derive from the (possibly moved) faces
        update(ctx, composite_layers=True)
        assert insp.n_faces(map_layer="Carto large") == 3
        assert insp.orphaned_relations() == 0
