from pathlib import Path

from geoalchemy2.shape import from_shape
from macrostrat.database import Database
from psycopg.sql import SQL, Identifier
from pytest import fixture
from shapely.geometry import Point

from mapboard.topology_manager.commands import (
    create_tables,
    rebuild_edge_relations,
    validate_edge_relations,
)
from mapboard.topology_manager.commands.update_topology import update
from mapboard.topology_manager.commands.update_faces.helpers import get_adjacent_faces
from mapboard.topology_manager.config import (
    create_context,
    TopologyContext,
    IdentityStrategy,
)
from ..helpers import TopologyInspector

FIXTURES = Path(__file__).parent / "fixtures"


def create_data_tables(ctx: TopologyContext):
    # The host owns only the feature tables; identity is installed by the strategy.
    ctx.database.run_sql(FIXTURES / "01-create-tables.sql")


def _install_direct_strategy(ctx: TopologyContext):
    ctx.database.run_sql(FIXTURES / "03-identity-management.sql")


# A host-supplied identity strategy: each face carries its own identity (the
# covering map_area, disambiguated by priority). The host just constructs it and
# passes it to create_context — no global registration needed.
DIRECT_STRATEGY = IdentityStrategy(
    identity_column="map_id",
    install=_install_direct_strategy,
)


def geom(_shape, srid=4326):
    return str(from_shape(_shape, srid, extended=True))


@fixture(scope="class")
def ctx(empty_db):
    ctx = create_context(
        empty_db,
        data_schema="map_bounds",
        topo_schema="map_bounds_topology",
        srid=4326,
        tolerance=0.0001,
        identity_strategy=DIRECT_STRATEGY,
        boundary_table="map_area",
        create_data_tables=create_data_tables,
        notify_triggers=False,
    )
    create_tables(ctx)
    yield ctx


def row_count(db, table, schema=None):
    if schema is None:
        if "." in table:
            schema, table = table.split(".")
    tbl = Identifier(table)
    if schema is not None:
        tbl = Identifier(schema, table)
    return db.run_query("SELECT count(*) FROM {table}", dict(table=tbl)).scalar()


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


def add_map(
    db: Database, geometry: str, layer: str, *, srid: int = 4326, priority=0
) -> int:
    """Add a face that overlaps the other two"""
    map_id = db.run_query(
        """
        WITH geom AS (
            SELECT ST_SetSRID({geometry}, :srid) AS geometry
        )
        INSERT INTO map_bounds.map_area (geometry, area_km, map_layer)
        SELECT geometry, ST_Area(geometry::geography) / 1e6, map_bounds.layer_id(:layer)
        FROM geom
        RETURNING id
        """,
        dict(geometry=SQL(geometry), layer=layer, srid=srid),
    ).scalar()

    db.run_query(
        """
        INSERT INTO map_bounds.map_priority (
            map_layer,
            map_id,
            priority
        )
        VALUES (map_bounds.layer_id(:layer), :map_id, :priority)
        """,
        dict(layer=layer, map_id=map_id, priority=priority),
    )
