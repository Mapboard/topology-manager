"""Noding a boundary row from several geometry pieces into one topogeometry.

The contract is `docs/design/piecewise-noding.md`: the host cuts a row's geometry
into pieces and nodes each with `update_boundary_piece`; the library accumulates
them into the row's topogeometry under a stable id, records nothing per piece,
and marks the faces each piece touches dirty so the face update resumes from
`dirty_face` however the run was interrupted. Realized geometry is held to the
topology's precision, not bitwise.
"""

from pytest import fixture
from shapely.geometry import LineString, box

from mapboard.topology_manager import TopologyInspector
from mapboard.topology_manager.commands import (
    failed_boundaries,
    update_boundary_piece,
    update_contacts,
)
from mapboard.topology_manager.commands.update_topology import update

from .support import (
    add_map,
    boundary_primitives,
    boundary_topogeom_id,
    complete_boundary,
    dirty_set,
    install_noding_fault,
    remove_noding_fault,
    row_count,
)

# The reference row, and the pieces a host might cut it into
BOUNDS = "ST_MakeEnvelope(0, 0, 2, 2)"
QUADRANTS = [box(0, 0, 1, 1), box(1, 0, 2, 1), box(0, 1, 1, 2), box(1, 1, 2, 2)]


def _row(db, map_id):
    return db.run_query(
        """
        SELECT
          topo IS NULL AS no_topo,
          geometry_hash,
          topology_error,
          ST_Equals(topo::geometry, geometry) AS equals_geometry
        FROM map_bounds.map_area
        WHERE id = :id
        """,
        dict(id=map_id),
    ).one()


def _check_invariants(ctx, layer: str):
    insp = TopologyInspector(ctx)
    assert insp.n_dirty_faces() == 0
    assert insp.orphaned_relations() == 0
    assert insp.faces_match_topology()
    assert insp.unfaced_primitives(layer) == []
    # raises when the cached edge relations disagree with the dynamic view
    insp.n_edge_relations()


class TestPiecesEqualWhole:
    """A row noded from several pieces equals the same row noded whole."""

    @fixture(scope="class")
    def rows(self, ctx):
        db = ctx.database
        return dict(pieces=add_map(db, BOUNDS, "large"))

    def test_pieces_accumulate_under_one_id(self, ctx, rows):
        db = ctx.database
        assert _row(db, rows["pieces"]).no_topo

        ids = []
        for piece in QUADRANTS:
            assert update_boundary_piece(ctx, rows["pieces"], piece) is None
            ids.append(boundary_topogeom_id(db, rows["pieces"]))
            assert len(boundary_primitives(db, rows["pieces"])) == len(ids)
        # The first piece created the topogeometry; the rest accumulated into it
        assert len(set(ids)) == 1

        row = _row(db, rows["pieces"])
        assert row.equals_geometry
        # The library does not decide when a row is complete
        assert row.geometry_hash is None
        assert row.topology_error is None

    def test_completed_row_is_not_renoded(self, ctx, rows):
        db = ctx.database
        complete_boundary(db, rows["pieces"])
        before = boundary_primitives(db, rows["pieces"])
        assert update_contacts(ctx) == 0
        assert boundary_primitives(db, rows["pieces"]) == before

    def test_whole_row_has_the_same_primitives(self, ctx, rows):
        db = ctx.database
        rows["whole"] = add_map(db, BOUNDS, "medium")
        assert update_contacts(ctx) == 1
        whole = _row(db, rows["whole"])
        assert whole.geometry_hash is not None and whole.equals_geometry
        # same primitive set, same relation rows
        assert boundary_primitives(db, rows["whole"]) == boundary_primitives(
            db, rows["pieces"]
        )

    def test_faces_dissolve(self, ctx, rows):
        insp = TopologyInspector(ctx)
        update(ctx)
        assert insp.n_faces(map_layer="Large") == 1
        assert insp.n_faces(map_layer="Medium") == 1
        _check_invariants(ctx, "Large")
        _check_invariants(ctx, "Medium")


class TestFailingPiece:
    """A failing piece leaves the row's topogeometry and the other pieces intact."""

    @fixture(scope="class")
    def row(self, ctx):
        return add_map(ctx.database, BOUNDS, "large")

    def test_failure_is_returned_not_recorded(self, ctx, row):
        db = ctx.database
        for piece in QUADRANTS[:2]:
            assert update_boundary_piece(ctx, row, piece) is None
        before = boundary_primitives(db, row)
        topogeom = boundary_topogeom_id(db, row)

        # An areal layer cannot take a lineal piece
        err = update_boundary_piece(ctx, row, LineString([(0, 0), (2, 2)]))
        assert err is not None and "lineal" in err

        # A failure inside toTopoGeom itself, after the row has primitives
        install_noding_fault(db)
        try:
            err = update_boundary_piece(ctx, row, QUADRANTS[2])
        finally:
            remove_noding_fault(db)
        assert err is not None and "induced" in err

        assert boundary_primitives(db, row) == before
        assert boundary_topogeom_id(db, row) == topogeom
        assert _row(db, row).topology_error is None

    def test_later_pieces_still_accumulate(self, ctx, row):
        db = ctx.database
        for piece in QUADRANTS[2:]:
            assert update_boundary_piece(ctx, row, piece) is None
        assert len(boundary_primitives(db, row)) == 4
        assert _row(db, row).equals_geometry


class TestFailureCaptureAndRetry:
    """Whole-row noding records its failure on the row; the failed set is
    selectable and retried on request, and cleared on success."""

    @fixture(scope="class")
    def row(self, ctx):
        return add_map(ctx.database, BOUNDS, "large")

    def test_failure_is_recorded(self, ctx, row):
        db = ctx.database
        install_noding_fault(db)
        try:
            assert update_contacts(ctx) == 1
        finally:
            remove_noding_fault(db)
        state = _row(db, row)
        assert state.no_topo
        assert state.geometry_hash is None
        assert "induced" in state.topology_error
        assert [(r.id, r.topology_error) for r in failed_boundaries(ctx)] == [
            (row, state.topology_error)
        ]
        assert row_count(db, "map_bounds_topology.__boundary_failures") == 1

    def test_failed_rows_are_skipped_unless_selected(self, ctx, row):
        db = ctx.database
        assert update_contacts(ctx) == 0
        # Selected explicitly, the row is attempted once; the error is replaced
        install_noding_fault(db)
        try:
            assert update_contacts(ctx, include_failed=True) == 1
        finally:
            remove_noding_fault(db)
        assert "induced" in _row(db, row).topology_error
        # A row filter narrows the selection
        assert (
            update_contacts(
                ctx,
                include_failed=True,
                row_filter="l.id = :other",
                filter_params=dict(other=row + 1000),
            )
            == 0
        )

    def test_retry_clears_the_error(self, ctx, row):
        db = ctx.database
        assert update_contacts(ctx, fix_failed=True) == 1
        state = _row(db, row)
        assert not state.no_topo
        assert state.topology_error is None
        assert state.geometry_hash is not None and state.equals_geometry
        assert failed_boundaries(ctx) == []
        update(ctx)
        _check_invariants(ctx, "Large")


class TestGeometryChangeClears:
    """Re-noding after a geometry change clears the topogeometry first, keeping its id."""

    @fixture(scope="class")
    def row(self, ctx):
        return add_map(ctx.database, BOUNDS, "large")

    def test_noded_and_solved(self, ctx, row):
        db = ctx.database
        for piece in QUADRANTS:
            assert update_boundary_piece(ctx, row, piece) is None
        complete_boundary(db, row)
        update(ctx)
        assert TopologyInspector(ctx).n_faces(map_layer="Large") == 1
        _check_invariants(ctx, "Large")

    def test_geometry_change_empties_the_topogeometry(self, ctx, row):
        db = ctx.database
        topogeom = boundary_topogeom_id(db, row)
        db.run_query(
            """
            UPDATE map_bounds.map_area
            SET geometry = ST_Multi(ST_MakeEnvelope(3, 0, 5, 2, 4326))
            WHERE id = :id
            """,
            dict(id=row),
        )
        db.session.commit()
        assert boundary_primitives(db, row) == set()
        assert boundary_topogeom_id(db, row) == topogeom
        state = _row(db, row)
        assert state.geometry_hash is None
        assert not state.no_topo
        # The faces the old geometry covered are queued for release
        assert dirty_set(db) != set()

    def test_renoding_uses_the_new_geometry_only(self, ctx, row):
        db = ctx.database
        topogeom = boundary_topogeom_id(db, row)
        assert update_contacts(ctx) == 1
        assert boundary_topogeom_id(db, row) == topogeom
        state = _row(db, row)
        assert state.equals_geometry and state.geometry_hash is not None

        update(ctx)
        faces = db.run_query("""
            SELECT ST_Equals(geometry, ST_Multi(ST_MakeEnvelope(3, 0, 5, 2, 4326))) eq
            FROM {topo_schema}.map_face
            WHERE map_layer = map_bounds.layer_id('large')
            """).scalars()
        assert list(faces) == [True]
        _check_invariants(ctx, "Large")


class TestTJunction:
    """A piece whose edges cross a neighbour's diagonal edge splits that edge at
    points that are not exactly representable, so PostGIS inserts vertices into
    it. Realized geometry is kept to the topology's precision, so what must hold
    is that every face matches its topogeometry to that precision afterwards,
    and that the faces the piece touches were marked."""

    @fixture(scope="class")
    def rows(self, ctx):
        db = ctx.database
        rows = dict(
            lower=add_map(
                db, "ST_GeomFromText('POLYGON((0 0, 3 0, 0 3, 0 0))')", "large"
            ),
            upper=add_map(
                db, "ST_GeomFromText('POLYGON((3 0, 3 3, 0 3, 3 0))')", "large"
            ),
        )
        update(ctx)
        return rows

    def test_setup(self, ctx, rows):
        insp = TopologyInspector(ctx)
        assert insp.n_faces(map_layer="Large") == 2
        assert insp.n_edges() == 3
        assert dirty_set(ctx.database) == set()

    def test_piece_splits_the_shared_edge(self, ctx, rows):
        db = ctx.database
        lower_face = list(boundary_primitives(db, rows["lower"]))
        upper_face = list(boundary_primitives(db, rows["upper"]))
        assert len(lower_face) == 1 and len(upper_face) == 1

        piece = box(0.7, 0.7, 4, 4)  # crosses the diagonal at (2.3, 0.7) and (0.7, 2.3)
        rows["piece"] = add_map(db, BOUNDS, "large")
        assert update_boundary_piece(ctx, rows["piece"], piece) is None

        # The diagonal was split at the crossings: three edges now run along it
        diagonal = db.run_query("""
            WITH d AS (
              SELECT ST_SetSRID(ST_MakeLine(ST_MakePoint(3, 0), ST_MakePoint(0, 3)), 4326) AS geom
            )
            SELECT count(*) FROM {topo_schema}.edge_data e, d
            WHERE ST_Covers(ST_Buffer(d.geom, 1e-9), e.geom)
            """).scalar()
        assert diagonal == 3

        # Both triangles' remainders border the piece and are marked
        large = db.run_query("SELECT map_bounds.layer_id('large')").scalar()
        dirty = dirty_set(db)
        assert (lower_face[0], large) in dirty
        assert (upper_face[0], large) in dirty

    def test_update_resolves_every_face(self, ctx, rows):
        complete_boundary(ctx.database, rows["piece"])
        update(ctx)
        insp = TopologyInspector(ctx)
        # the piece, the lower triangle's remainder, and the two slivers the
        # piece leaves of the upper triangle
        assert insp.n_faces(map_layer="Large") == 4
        _check_invariants(ctx, "Large")


class TestInterruptedUpdateResumes:
    """Pieces noded after a face update, with no update following, leave their
    faces in the persistent `dirty_face` queue; the next update resumes from it
    and leaves no face with stale geometry."""

    @fixture(scope="class")
    def row(self, ctx):
        return add_map(ctx.database, BOUNDS, "large")

    def test_first_half(self, ctx, row):
        db = ctx.database
        for piece in QUADRANTS[:2]:
            assert update_boundary_piece(ctx, row, piece) is None
        # The row is not complete, so the whole-row pass must not see it: a host
        # mid-way through a row's pieces runs the face update alone (or filters
        # the row out of `update_contacts`).
        update(ctx, boundaries=False)
        insp = TopologyInspector(ctx)
        assert insp.n_faces(map_layer="Large") == 1
        assert insp.n_dirty_faces() == 0
        assert insp.faces_match_topology()

    def test_interrupted_after_more_pieces(self, ctx, row):
        db = ctx.database
        for piece in QUADRANTS[2:]:
            assert update_boundary_piece(ctx, row, piece) is None
        insp = TopologyInspector(ctx)
        # The queue holds the faces the new pieces touched, nothing is realized
        # for them yet, and the face already realized is still consistent.
        assert insp.n_dirty_faces() > 0
        assert insp.unfaced_primitives("Large") != []
        assert insp.faces_match_topology()

    def test_next_run_resumes(self, ctx, row):
        db = ctx.database
        complete_boundary(db, row)
        update(ctx)
        insp = TopologyInspector(ctx)
        assert insp.n_faces(map_layer="Large") == 1
        _check_invariants(ctx, "Large")
        # and there is nothing left to do
        update(ctx)
        assert insp.n_dirty_faces() == 0


class TestToleranceArgument:
    """The caller chooses the snapping tolerance per call; the library never does."""

    def test_piece_snaps_at_the_given_tolerance(self, ctx):
        db = ctx.database
        a = add_map(db, BOUNDS, "large")
        assert update_boundary_piece(ctx, a, box(0, 0, 2, 2)) is None
        # A neighbour 0.0005 away: beyond the topology's precision (0.0001)...
        b = add_map(db, "ST_MakeEnvelope(2.0005, 0, 4, 2)", "large")
        assert update_boundary_piece(ctx, b, box(2.0005, 0, 4, 2)) is None
        xmin = db.run_query(
            "SELECT ST_XMin(topo::geometry) FROM map_bounds.map_area WHERE id = :id",
            dict(id=b),
        ).scalar()
        assert xmin == 2.0005
        # ...but within a tolerance the caller asks for, a vertex snaps onto `a`
        c = add_map(db, "ST_MakeEnvelope(-2, 2.0005, 0, 4)", "large")
        assert (
            update_boundary_piece(ctx, c, box(-2, 2.0005, 0, 4), tolerance=0.001)
            is None
        )
        ymin = db.run_query(
            "SELECT ST_YMin(topo::geometry) FROM map_bounds.map_area WHERE id = :id",
            dict(id=c),
        ).scalar()
        assert ymin == 2
