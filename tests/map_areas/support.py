"""Shared helpers for the map-area (face-based topogeometry) test suite.

The host-side pieces a map-area deployment supplies: the data tables (with the
`map_id` identity column) and a "direct" identity strategy in which each face
carries the identity of the covering `map_area`, disambiguated by `map_priority`
(a *lower* priority value wins; ties go to the newest map).
"""

from pathlib import Path

from geoalchemy2.shape import from_shape
from macrostrat.database import Database
from psycopg.sql import SQL, Identifier, Literal

from mapboard.topology_manager import IdentityStrategy, TopologyContext

FIXTURES = Path(__file__).parent / "fixtures"

DATA_SCHEMA = "map_bounds"
TOPO_SCHEMA = "map_bounds_topology"


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
    # The fixture defines `resolve_layer_identity`, so the dissolve caches
    # identities per layer instead of calling `faces_are_joinable` per edge. Set
    # here so the suites cover the cached path, which is what a host with a bulk
    # strategy runs; without it that path has no test at all.
    bulk_identity=True,
)


def drop_map_area_schemas(db: Database):
    """Remove everything a previous test class created, so each class starts
    from an empty topology (the fixtures hardcode the schema names)."""
    db.run_sql(
        """
        DO $$
        BEGIN
          IF to_regclass('topology.topology') IS NOT NULL AND EXISTS (
            SELECT 1 FROM topology.topology WHERE name = {topo_schema_lit}
          ) THEN
            PERFORM topology.DropTopology({topo_schema_lit});
          END IF;
        END $$;
        DROP SCHEMA IF EXISTS {topo_schema_ident} CASCADE;
        DROP SCHEMA IF EXISTS {data_schema_ident} CASCADE;
        """,
        dict(
            topo_schema_lit=Literal(TOPO_SCHEMA),
            topo_schema_ident=Identifier(TOPO_SCHEMA),
            data_schema_ident=Identifier(DATA_SCHEMA),
        ),
    )


def geom(_shape, srid=4326):
    return str(from_shape(_shape, srid, extended=True))


def row_count(db, table, schema=None):
    if schema is None:
        if "." in table:
            schema, table = table.split(".")
    tbl = Identifier(table)
    if schema is not None:
        tbl = Identifier(schema, table)
    return db.run_query("SELECT count(*) FROM {table}", dict(table=tbl)).scalar()


def add_map(
    db: Database, geometry: str, layer: str, *, srid: int = 4326, priority=0
) -> int:
    """Add a map area (a SQL geometry expression) to a layer, with a priority."""
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
    return map_id


def set_priority(db: Database, map_id: int, priority: int):
    db.run_query(
        "UPDATE map_bounds.map_priority SET priority = :priority WHERE map_id = :map_id",
        dict(map_id=map_id, priority=priority),
    )


def mark_dirty(db: Database, faces: list[int], map_layer: int):
    """What a host does to flag primitives whose identity went stale."""
    db.run_query(
        """
        INSERT INTO {topo_schema}.dirty_face (id, map_layer)
        SELECT unnest(:faces), :map_layer
        ON CONFLICT DO NOTHING
        """,
        dict(faces=faces, map_layer=map_layer),
    )


def map_faces(db: Database, map_layer: int) -> list:
    """`map_face` rows of a layer, oldest first."""
    return db.run_query(
        """
        SELECT id, map_id, ST_Area(geometry) area, geometry
        FROM {topo_schema}.map_face
        WHERE map_layer = :map_layer
        ORDER BY id
        """,
        dict(map_layer=map_layer),
    ).all()


def face_primitives(db: Database, map_face_id: int) -> set[int]:
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
