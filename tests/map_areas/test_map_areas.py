from pytest import approx
from shapely.geometry import Point

from mapboard.topology_manager.commands import (
    rebuild_edge_relations,
    validate_edge_relations,
)
from mapboard.topology_manager.commands.update_topology import update
from mapboard.topology_manager.commands.update_faces.helpers import get_adjacent_faces
from mapboard.topology_manager import TopologyInspector

from .support import add_map, geom, map_faces, mark_dirty, row_count, set_priority


class TestMapTopology:
    def test_create_map_bounds(self, ctx):
        """Insert a few test maps into the database

        They have overlapping bounds so we can test the logic for merging them into
        a composite layer.
        """
        db = ctx.database

        # Insert two non-overlapping test sources
        add_map(db, "ST_MakeEnvelope(0, 0, 2, 2)", "large")
        add_map(db, "ST_MakeEnvelope(3, 0, 5, 2)", "large")

        update(ctx)
        # Check that we have two maps in the map_area table
        assert row_count(db, "map_bounds.map_area") == 2
        assert row_count(db, "map_bounds.map_priority") == 2

    def test_topology_is_valid(self, ctx):
        insp = TopologyInspector(ctx)
        assert insp.is_valid()

    def test_process_maps(self, ctx):
        # Check that we have the appropriate number of faces
        insp = TopologyInspector(ctx)
        assert insp.n_face_primitives() == 2

        # Update topology faces
        update(ctx)

        assert insp.n_faces() == 2

    def test_edge_relations(self, ctx):
        insp = TopologyInspector(ctx)
        assert insp.n_edges() == 2
        assert insp.n_edge_relations() == 2

    def test_rebuild_edge_relations(self, ctx):
        """The triggers keep __edge_relation in sync; rebuild can repair drift."""
        db = ctx.database

        # Triggers should have kept the cache in sync
        assert validate_edge_relations(ctx).in_sync

        # Simulate the triggers falling out of sync
        db.run_query("DELETE FROM {topo_schema}.__edge_relation WHERE true")
        drift = validate_edge_relations(ctx)
        assert not drift.in_sync
        assert drift.missing == 2

        # Rebuilding reports the prior drift and restores the cache
        report = rebuild_edge_relations(ctx)
        assert report.missing == 2
        assert validate_edge_relations(ctx).in_sync

    def test_add_overlapping_map(self, ctx):
        """Add a face that overlaps the other two"""
        db = ctx.database
        add_map(db, "ST_MakeEnvelope(1, 1, 4, 4)", "large")

        insp = TopologyInspector(ctx)

        update(ctx, composite_layers=False)
        assert insp.n_face_primitives() == 5

        # Get the face primitive in the center of the new face
        center = geom(Point(2.5, 2.5))
        face_id = insp.get_face_id(center)
        map_layer = insp.map_layer_id("Large")
        face_list = get_adjacent_faces(db, face_id, map_layer)

        assert len(face_list) == 3

        assert insp.n_faces() == 3

    def test_maps_are_separately_identified(self, ctx):
        """Check that the map faces have separate IDs"""
        db = ctx.database
        insp = TopologyInspector(ctx)
        id = insp.map_layer_id("Large")
        records = db.run_query(
            "SELECT * FROM map_bounds_topology.map_face WHERE map_layer = :map_layer",
            dict(map_layer=id),
        ).all()
        assert len(records) == 3
        assert len(set(record.map_id for record in records)) == 3

    ## TODO, we could add test isolation here with a template_database fixture...
    def test_add_another_layer_feature(self, ctx):
        """Add overlapping feature to the 'medium' layer to check that it is not merged into the 'large' layer.

        We use a large, circular feature to check whether we can also successfully work with maps that are subdivided
        on input.
        """
        db = ctx.database

        add_map(db, "ST_Buffer(ST_MakePoint(2, 2), 6)", "medium")
        update(ctx, composite_layers=False)

        insp = TopologyInspector(ctx)
        assert insp.n_faces() == 4
        assert insp.n_faces(map_layer="Medium") == 1
        assert insp.n_faces(map_layer="Large") == 3

    def test_composite_layers(self, ctx):

        update(ctx, composite_layers=True)
        insp = TopologyInspector(ctx)
        assert insp.n_faces(map_layer="Large") == 3
        assert insp.n_faces(map_layer="Medium") == 1
        assert insp.n_faces(map_layer="Carto large") == 4
        assert insp.n_faces(map_layer="Carto medium") == 1
        assert insp.n_faces(map_layer="Carto small") == 0
        assert insp.n_faces() == 4 + 4 + 1


class TestSplitBoundaryEdges:
    """A boundary edge split by another map is still registered as a barrier.

    `b` is added beside `a` with its left edge along part of `a`'s right edge.
    That splits `a`'s edge but not `a`'s face, so no relation row of `a` changes
    and nothing queues it for an edge-relation rebuild. Unregistered, the new
    pieces between `a` and the map `c` beneath it are crossable, and `a`'s face
    dissolves into `c`'s.
    """

    def test_split_edges_are_registered(self, ctx):
        db = ctx.database
        c = add_map(db, "ST_MakeEnvelope(-2, -2, 6, 4)", "large", priority=10)
        a = add_map(db, "ST_MakeEnvelope(0, 0, 2, 2)", "large")
        update(ctx)

        b = add_map(db, "ST_MakeEnvelope(2, 0.5, 4, 1.5)", "large")
        update(ctx)

        assert validate_edge_relations(ctx).in_sync
        layer = TopologyInspector(ctx).map_layer_id("Large")
        faces = map_faces(db, layer)
        assert sorted(f.map_id for f in faces) == sorted([a, b, c])
        areas = {f.map_id: f.area for f in faces}
        assert areas[a] == approx(4)
        assert areas[b] == approx(2)


class TestIdentityFromPrimitives:
    """A dissolved face takes the identity its primitives resolve to.

    The dissolve joins primitives by `identity_for_face` (cached through
    `resolve_layer_identity`), so a component's identity is already decided.
    Deriving it again from the face's geometry (`identity_for_area`) was slower
    and could disagree -- a host whose spatial lookup reads raw bounds rather
    than noded topogeometries got a different owner on slivers, which its
    stale-identity check then re-marked on every run. `identity_for_area` is
    replaced here with a decoy, so any face that consults it is unidentified.
    """

    def test_faces_ignore_area_identity(self, ctx):
        db = ctx.database
        insp = TopologyInspector(ctx)
        layer = insp.map_layer_id("Large")
        db.run_sql(
            """
            CREATE OR REPLACE FUNCTION {topo_schema}.identity_for_area(
              geom geometry, _map_layer integer
            ) RETURNS integer AS $$ SELECT NULL::integer $$ LANGUAGE sql;
            """
        )
        a = add_map(db, "ST_MakeEnvelope(0, 0, 3, 3)", "large", priority=0)
        b = add_map(db, "ST_MakeEnvelope(2, 0, 5, 3)", "large", priority=1)
        update(ctx, composite_layers=False)

        areas = {f.map_id: f.area for f in map_faces(db, layer)}
        assert areas == {a: approx(9), b: approx(6)}

        # The overlap flips to B: absorbed into B's face in move mode, a new face
        # in replace mode, and identified from its primitives either way.
        overlap = insp.get_face_id(geom(Point(2.5, 1.5)))
        set_priority(db, b, -1)
        mark_dirty(db, [overlap], layer)
        update(ctx, composite_layers=False)

        faces = map_faces(db, layer)
        assert None not in {f.map_id for f in faces}
        assert {f.map_id: f.area for f in faces if f.map_id == b} == {b: approx(9)}
