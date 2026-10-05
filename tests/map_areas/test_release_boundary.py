"""A boundary whose topogeometry is emptied releases what only it needed.

Map faces solved against the old geometry hold its faces, and so its edges,
until they are solved again. The release takes those faces out of the map faces
without deleting any `map_face` row, so stale geometry serves until the update
rebuilds the area, and `remove_released_primitives` clears the old edges before
anything is noded over them.
"""

from pytest import approx, fixture
from shapely.geometry import box

from mapboard.topology_manager import TopologyInspector
from mapboard.topology_manager.commands import remove_released_primitives
from mapboard.topology_manager.commands.update_topology import update

from .support import add_map, row_count

OUTER = box(0, 0, 6, 6)
INNER = box(1, 1, 5, 5)
# An unmapped channel splits the inner map's first geometry in two
CHANNEL = box(2.95, 0, 3.05, 6)
INNER_INTERIOR = INNER.buffer(-0.01)


def _sql_geom(shape) -> str:
    return f"ST_GeomFromText('{shape.wkt}', 4326)"


def _edges_inside(db, shape) -> int:
    return db.run_query(
        "SELECT count(*) FROM {topo_schema}.edge_data"
        " WHERE ST_Intersects(geom, ST_GeomFromText(:wkt, 4326))",
        dict(wkt=shape.wkt),
    ).scalar()


def _map_face_state(db):
    return db.run_query(
        "SELECT count(*) n, sum(ST_Area(geometry)) area FROM {topo_schema}.map_face"
    ).one()


def _emptied_map_faces(db) -> int:
    return db.run_query(
        """
        SELECT count(*) FROM {topo_schema}.map_face mf
        WHERE mf.topo IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM {topo_schema}.relation r
          WHERE r.topogeo_id = (mf.topo).id AND r.layer_id = (mf.topo).layer_id
        )
        """
    ).scalar()


def _map_area(db, map_id, layer) -> float:
    return db.run_query(
        """
        SELECT coalesce(sum(ST_Area(geometry)), 0) FROM {topo_schema}.map_face
        WHERE map_id = :map_id AND map_layer = map_bounds.layer_id(:layer)
        """,
        dict(map_id=map_id, layer=layer),
    ).scalar()


def _check_invariants(ctx, layer: str):
    insp = TopologyInspector(ctx)
    assert insp.n_dirty_faces() == 0
    assert insp.orphaned_relations() == 0
    assert insp.faces_match_topology()
    assert insp.unfaced_primitives(layer) == []
    insp.n_edge_relations()
    assert _emptied_map_faces(ctx.database) == 0


class TestGeometryChange:
    @fixture(scope="class")
    def maps(self, ctx):
        db = ctx.database
        outer = add_map(db, _sql_geom(OUTER), "large")
        inner = add_map(db, _sql_geom(INNER.difference(CHANNEL)), "large")
        update(ctx)
        return dict(outer=outer, inner=inner)

    def test_channel_edges_are_held_by_the_solve(self, ctx, maps):
        db = ctx.database
        assert _edges_inside(db, INNER_INTERIOR) > 0
        assert _map_area(db, maps["inner"], "large") == approx(
            INNER.difference(CHANNEL).area
        )

    def test_geometry_change_keeps_serving_stale_faces(self, ctx, maps):
        db = ctx.database
        before = _map_face_state(db)
        db.run_query(
            "UPDATE map_bounds.map_area SET geometry = ST_GeomFromText(:wkt, 4326)"
            " WHERE id = :id",
            dict(wkt=INNER.wkt, id=maps["inner"]),
        )
        db.session.commit()
        after = _map_face_state(db)
        assert after.n == before.n
        assert after.area == approx(before.area)
        assert row_count(db, "__released_extent", schema=ctx.topo_schema) == 1

    def test_released_edges_are_removed_before_noding(self, ctx, maps):
        db = ctx.database
        assert remove_released_primitives(ctx) > 0
        assert _edges_inside(db, INNER_INTERIOR) == 0
        assert row_count(db, "__released_extent", schema=ctx.topo_schema) == 0

    def test_renode_and_solve(self, ctx, maps):
        db = ctx.database
        update(ctx)
        _check_invariants(ctx, "large")
        assert _map_area(db, maps["inner"], "large") == approx(INNER.area)
        assert _map_area(db, maps["outer"], "large") == approx(
            OUTER.area - INNER.area
        )


class TestRetiredBoundary:
    """A row giving up its topogeometry releases the same way."""

    @fixture(scope="class")
    def maps(self, ctx):
        db = ctx.database
        outer = add_map(db, _sql_geom(OUTER), "large")
        inner = add_map(db, _sql_geom(INNER.difference(CHANNEL)), "large")
        update(ctx)
        return dict(outer=outer, inner=inner)

    def test_retire_and_solve(self, ctx, maps):
        db = ctx.database
        db.run_query(
            "UPDATE map_bounds.map_area SET topo = NULL, topology_error = 'retired'"
            " WHERE id = :id",
            dict(id=maps["inner"]),
        )
        db.session.commit()
        assert remove_released_primitives(ctx) > 0
        assert _edges_inside(db, INNER_INTERIOR) == 0
        update(ctx)
        _check_invariants(ctx, "large")
        assert _map_area(db, maps["outer"], "large") == approx(OUTER.area)
