"""Piecewise noding of lineal boundaries (`docs/design/piecewise-noding.md`).

The shared noding SQL must hold for edge-based topogeometries too: a line noded
from several pieces has the edges of the line noded whole, and a piece that
ends on another line's edge leaves every face consistent with its topogeometry.
"""

from pytest import fixture
from shapely.geometry import LineString

from mapboard.topology_manager import update
from mapboard.topology_manager.commands import update_boundary_piece, update_contacts
from mapboard.topology_manager.test_helpers import (
    add_linework_type_to_layer,
    create_map_layer,
    faces_mismatching_topology,
    insert_line,
    n_faces,
    orphaned_relations,
    square,
)


def _edges(db, line_id) -> set[int]:
    return set(
        db.run_query(
            """
            SELECT abs(r.element_id)
            FROM {data_schema}.linework l
            JOIN {topo_schema}.relation r
              ON r.topogeo_id = (l.topo).id
             AND r.layer_id = (l.topo).layer_id
             AND r.element_type = 2
            WHERE l.id = :id
            """,
            dict(id=line_id),
        ).scalars()
    )


def _topogeom_id(db, line_id):
    return db.run_query(
        "SELECT (topo).id FROM {data_schema}.linework WHERE id = :id", dict(id=line_id)
    ).scalar()


def _dirty(db) -> set[tuple[int, int]]:
    return set(
        (r.id, r.map_layer)
        for r in db.run_query(
            "SELECT id, map_layer FROM {topo_schema}.dirty_face"
        ).all()
    )


def _face_at(db, x, y):
    return db.run_query(
        """
        SELECT face_id FROM {topo_schema}.face
        WHERE face_id <> 0
          AND ST_Contains(ST_GetFaceGeometry(:topo_name, face_id), ST_SetSRID(ST_MakePoint(:x, :y), :srid))
        """,
        dict(x=x, y=y),
    ).scalar()


@fixture(scope="class")
def layer(db):
    lyr = create_map_layer(db, "pieces")
    add_linework_type_to_layer(db, lyr, "bedrock")
    return lyr


class TestLineFromPieces:
    def test_pieces_equal_whole(self, mgr, db, layer):
        ctx = mgr.ctx
        # Two rows with the same geometry: one noded from pieces, one whole
        coords = [(0, 0), (4, 0), (4, 4)]
        pieces = insert_line(db, coords, type="bedrock", map_layer=layer)
        whole = insert_line(db, coords, type="bedrock", map_layer=layer)

        assert update_boundary_piece(ctx, pieces, LineString(coords[:2])) is None
        first = _topogeom_id(db, pieces)
        assert update_boundary_piece(ctx, pieces, LineString(coords[1:])) is None
        assert _topogeom_id(db, pieces) == first
        assert len(_edges(db, pieces)) == 2

        assert (
            update_contacts(ctx, row_filter="l.id = :id", filter_params=dict(id=whole))
            == 1
        )
        assert _edges(db, whole) == _edges(db, pieces)

        db.run_query(
            """
            UPDATE {data_schema}.linework
            SET geometry_hash = {topo_schema}.hash_geometry(geometry)
            WHERE id = :id
            """,
            dict(id=pieces),
        )
        update()
        assert orphaned_relations(db) == 0
        assert faces_mismatching_topology(db) == []


class TestTJunction:
    """A line piece ending on a diagonal edge splits that edge at a point that
    is not exactly on it; PostGIS bends the edge to meet it by a float-noise
    distance. Realized geometry is held to the topology's precision, so the
    face across the diagonal need not be re-marked; the faces the piece runs
    through must be, and every face must match its topogeometry afterwards."""

    def test_setup(self, mgr, db, layer):
        insert_line(db, square(6, center=(3, 3)), type="bedrock", map_layer=layer)
        insert_line(db, [(6, 0), (0, 6)], type="bedrock", map_layer=layer)
        update()
        assert n_faces(db, map_layer=layer) == 2
        assert _dirty(db) == set()

    def test_piece_marks_the_faces_it_touches(self, mgr, db, layer):
        lower = _face_at(db, 1, 1)
        upper = _face_at(db, 5, 5)
        assert lower != upper

        line = insert_line(db, [(1, 1), (4.3, 1.7)], type="bedrock", map_layer=layer)
        n_edges_before = db.run_query(
            "SELECT count(*) FROM {topo_schema}.edge_data"
        ).scalar()
        assert (
            update_boundary_piece(mgr.ctx, line, LineString([(1, 1), (4.3, 1.7)]))
            is None
        )
        n_edges_after = db.run_query(
            "SELECT count(*) FROM {topo_schema}.edge_data"
        ).scalar()
        # the new edge, plus the diagonal split in two
        assert n_edges_after == n_edges_before + 2

        assert (lower, layer) in _dirty(db)

    def test_update_leaves_faces_consistent(self, mgr, db, layer):
        update()
        assert n_faces(db, map_layer=layer) == 2
        assert orphaned_relations(db) == 0
        assert faces_mismatching_topology(db) == []
        assert _dirty(db) == set()
