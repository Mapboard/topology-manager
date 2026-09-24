"""Stress cases, deselected unless pytest is given `--pathological`.

    uv run pytest tests/map_areas/test_pathological.py --pathological
    TOPO_PATHOLOGICAL_SIZE=24 uv run pytest tests/map_areas/test_pathological.py --pathological -s
"""

import os
from time import perf_counter

from pytest import approx, mark

from mapboard.topology_manager import TopologyInspector
from mapboard.topology_manager.commands import validate_edge_relations
from mapboard.topology_manager.commands.update_topology import update

from .support import add_map, map_faces, mark_dirty

SIZE = int(os.getenv("TOPO_PATHOLOGICAL_SIZE", "12"))


@mark.pathological
class TestBrickWall:
    """Every edge split by a later map, and no face split by one.

    Rows of 1x1 maps are laid over a lower-priority underlay one row at a time,
    alternate rows offset by half a brick, with a solve after each row. Each new
    row's corners land on the top edges of the row below -- T-junctions that split
    those edges without splitting any face -- so every brick below the top row has
    edges split after its boundary was registered. An unregistered piece between a
    brick and the underlay dissolves the brick into it.
    """

    def test_brick_wall(self, ctx):
        db = ctx.database
        underlay = add_map(
            db, f"ST_MakeEnvelope(-1, -1, {SIZE + 1}, {SIZE + 1})", "large", priority=10
        )
        update(ctx)

        bricks = []
        timings = []
        for row in range(SIZE):
            offset = 0.5 * (row % 2)
            n = SIZE - (row % 2)
            for i in range(n):
                x = offset + i
                bricks.append(
                    add_map(db, f"ST_MakeEnvelope({x}, {row}, {x + 1}, {row + 1})", "large")
                )
            t0 = perf_counter()
            update(ctx)
            timings.append(perf_counter() - t0)

        print(
            f"\n{len(bricks)} bricks in {SIZE} rows: {sum(timings):.1f} s of updates,"
            f" slowest row {max(timings):.2f} s"
        )

        assert validate_edge_relations(ctx).in_sync

        insp = TopologyInspector(ctx)
        layer = insp.map_layer_id("Large")
        faces = map_faces(db, layer)
        areas = {}
        for f in faces:
            assert f.map_id not in areas, f"map {f.map_id} holds more than one face"
            areas[f.map_id] = f.area

        assert set(areas) == {underlay, *bricks}
        for brick in bricks:
            assert areas[brick] == approx(1)
        assert areas[underlay] == approx((SIZE + 2) ** 2 - len(bricks))

        assert insp.unfaced_primitives(layer) == []
        assert insp.faces_match_topology(layer)
        assert insp.n_dirty_faces() == 0


#: Overlapping underlays beneath the wall. Each primitive face carries one
#: relation row per map covering it, so the refresh's owner join grows with this.
DEPTH = int(os.getenv("TOPO_PATHOLOGICAL_DEPTH", "8"))


@mark.pathological
class TestRefreshCost:
    """What re-deriving edge relations around dirty faces adds to an update.

    The worst case for the refresh: the whole layer dirty, over a brick wall with
    a stack of overlapping underlays, so every edge is visited and every face has
    `DEPTH + 1` candidate owners. Timed beside the full update over the same dirty
    set, and beside the whole-map rebuild it replaces.
    """

    def test_refresh_cost(self, ctx):
        db = ctx.database
        for k in range(DEPTH):
            m = 1 + 0.25 * k
            add_map(
                db,
                f"ST_MakeEnvelope({-m}, {-m}, {SIZE + m}, {SIZE + m})",
                "large",
                priority=10 + k,
            )
        for row in range(SIZE):
            offset = 0.5 * (row % 2)
            for i in range(SIZE - (row % 2)):
                x = offset + i
                add_map(db, f"ST_MakeEnvelope({x}, {row}, {x + 1}, {row + 1})", "large")
        update(ctx)

        insp = TopologyInspector(ctx)
        layer = insp.map_layer_id("Large")
        faces = list(
            db.run_query(
                "SELECT face_id FROM {topo_schema}.face WHERE face_id <> 0"
            ).scalars()
        )
        n_edges = db.run_query("SELECT count(*) FROM {topo_schema}.edge_data").scalar()

        # The whole-map rebuild the refresh replaced: every boundary's edges, derived
        # from all of its faces. Read-only, so it can be timed in place.
        t0 = perf_counter()
        db.run_query(
            """
            SELECT count(*)
            FROM map_bounds.map_area l
            CROSS JOIN LATERAL {topo_schema}.__topogeom_edges((l.topo).id, (l.topo).layer_id) e
            WHERE l.topo IS NOT NULL
            """
        ).scalar()
        t_whole = perf_counter() - t0

        mark_dirty(db, faces, layer)
        t0 = perf_counter()
        db.run_query("SELECT {topo_schema}.refresh_dirty_face_edge_relations()").scalar()
        t_refresh = perf_counter() - t0
        assert validate_edge_relations(ctx).in_sync

        t0 = perf_counter()
        update(ctx)
        t_update = perf_counter() - t0

        print(
            f"\n{len(faces)} faces, {n_edges} edges, {DEPTH} underlays:"
            f" refresh {t_refresh:.3f} s, whole-map rebuild {t_whole:.3f} s,"
            f" update of the whole layer {t_update:.2f} s"
            f" (refresh {100 * t_refresh / t_update:.1f}%)"
        )
        assert insp.n_dirty_faces() == 0
        assert validate_edge_relations(ctx).in_sync
        # Linear in the dirty set: about 0.1 ms a face, 1-2% of a whole-layer
        # update, and falling as the layer grows. An owner join that loses its
        # index is quadratic and passes 5% by the default size.
        assert t_refresh < 0.05 * t_update
