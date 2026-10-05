"""`__add_polygon` chooses the faces a noded polygon covers by walking the topology.

It must choose what PostGIS's point test (`__faces_covered`) chooses wherever no
sliver within tolerance of a ring is involved, and stay within tolerance of the
polygon where one is.
"""

from shapely import wkt
from shapely.geometry import box

from mapboard.topology_manager.commands import update_boundary_piece

from .support import TOPO_SCHEMA, add_map, boundary_primitives

TOLERANCE = 0.0001

SHELL = box(0, 0, 4, 4)
HOLE = box(1, 1, 2, 2)


def _sql_geom(shape) -> str:
    return f"ST_GeomFromText('{shape.wkt}', 4326)"


def _topo_geometry(db, map_id):
    return wkt.loads(
        db.run_query(
            "SELECT ST_AsText(topo::geometry) FROM map_bounds.map_area WHERE id = :id",
            dict(id=map_id),
        ).scalar()
    )


def _face_geometry_calls(db) -> int:
    return db.run_query(
        "SELECT coalesce(sum(calls), 0) FROM pg_stat_xact_user_functions"
        " WHERE schemaname = 'topology' AND funcname = 'st_getfacegeometry'"
    ).scalar()


def _add_and_compare(db, shape) -> tuple[set[int], set[int]]:
    """Node `shape` with `__add_polygon`, then run PostGIS's test on the same state."""
    db.run_query("SET track_functions = 'all'")
    before = _face_geometry_calls(db)
    walked = set(
        db.run_query(
            f"SELECT {TOPO_SCHEMA}.__add_polygon({_sql_geom(shape)}, :tol)",
            dict(tol=TOLERANCE),
        ).scalars()
    )
    # The walk builds no face geometry; a fallback to PostGIS's test would
    assert _face_geometry_calls(db) == before
    covered = set(
        db.run_query(
            f"SELECT {TOPO_SCHEMA}.__faces_covered({_sql_geom(shape)}, :tol)",
            dict(tol=TOLERANCE),
        ).scalars()
    )
    # The counter works: PostGIS's test does build face geometry
    assert _face_geometry_calls(db) > before
    return walked, covered


class TestHoles:
    def test_polygon_with_a_hole(self, ctx):
        db = ctx.database
        shape = SHELL.difference(HOLE)
        map_id = add_map(db, _sql_geom(shape), "large")
        assert update_boundary_piece(ctx, map_id, shape) is None
        assert _topo_geometry(db, map_id).equals(shape)

    def test_hole_pressed_against_the_shell(self, ctx):
        db = ctx.database
        shape = box(10, 0, 14, 4).difference(
            box(10 + TOLERANCE / 2, 1, 11, 2)
        )
        map_id = add_map(db, _sql_geom(shape), "large")
        assert update_boundary_piece(ctx, map_id, shape) is None
        noded = _topo_geometry(db, map_id)
        # Snapping closes the gap between hole and shell; nothing else moves
        assert noded.symmetric_difference(shape).area < 1.5 * TOLERANCE
        # The hole stays out
        assert noded.intersection(box(10.1, 1.1, 10.9, 1.9)).area == 0

    def test_walk_handles_holes(self, ctx):
        db = ctx.database
        walked, covered = _add_and_compare(db, box(30, 0, 34, 4).difference(box(31, 1, 32, 2)))
        assert walked == covered
        pressed = box(40, 0, 44, 4).difference(box(40 + TOLERANCE / 2, 1, 41, 2))
        walked, covered = _add_and_compare(db, pressed)
        assert walked == covered


class TestRenodeOverExistingFaces:
    """A polygon added over faces already in the topology covers all of them."""

    def test_walk_matches_point_test(self, ctx):
        db = ctx.database
        outer = box(20, 0, 24, 4)
        # Interior linework from other maps splits the area into many faces
        for x in range(21, 24):
            strip = box(x - 0.5, 0.5, x + 0.25, 3.5)
            other = add_map(db, _sql_geom(strip), "large")
            assert update_boundary_piece(ctx, other, strip) is None

        walked, covered = _add_and_compare(db, outer)
        assert len(walked) > 1
        assert walked == covered

    def test_renoded_row_equals_its_geometry(self, ctx):
        db = ctx.database
        outer = box(20, 0, 24, 4)
        map_id = add_map(db, _sql_geom(outer), "large")
        assert update_boundary_piece(ctx, map_id, outer) is None
        assert len(boundary_primitives(db, map_id)) > 1
        assert _topo_geometry(db, map_id).equals(outer)

    def test_polygon_with_hole_over_existing_faces(self, ctx):
        db = ctx.database
        shape = box(20, 0, 24, 4).difference(box(21.6, 1.5, 22.6, 2.5))
        walked, covered = _add_and_compare(db, shape)
        assert walked == covered
