from dataclasses import dataclass
from macrostrat.database import Database as BaseDatabase
import os
from psycopg.sql import SQL, Identifier, Literal
from sqlalchemy.sql.expression import TextClause
from contextvars import ContextVar
from sqlalchemy.dialects.postgresql import base as pg
from pathlib import Path
from typing import Callable, Optional


class Database(BaseDatabase):
    def proc(self, name, params=None, **kwargs):
        return super().run_sql(sql(name), params, **kwargs)


@dataclass
class IdentityStrategy:
    """Defines how a map face acquires its identity.

    A strategy owns the *resolution logic* (a set of SQL functions). It only
    *names* the identity column — the column itself (type, constraints) is created
    as part of data-table creation, since the column references a data table. The
    two axes — identity source and boundary geometry — are independent.
    See ``docs/design/identity-strategy.md``.
    """

    # Selection key (e.g. "search", "direct").
    key: str
    # The identity column name on map_face / face_identity. The column is defined
    # by data-table creation (default or host); this is just its name, used to
    # build the {face_identity_column} template variable.
    identity_column: str
    # Install the strategy's SQL functions into a context's topo schema. Must
    # leave identity_for_area / identity_for_face / faces_are_joinable /
    # map_face_is_identified defined afterward.
    install: Callable[["TopologyContext"], None]
    # How identity combines with the contact barrier in get_adjacent_faces_core.
    # Reserved: the SQL currently hardcodes "or"; "and" is for the future
    # direct-identity linework mode.
    combinator: str = "or"


# ---------------------------------------------------------------------------
# Reference identity strategy: "search" (the default)
#
# Geologic mapping — a face has no identity of its own; it is derived by
# searching the typed-polygon table (area-weighted dominant polygon_type).
# Hosts override it simply by passing their own IdentityStrategy to
# create_context (e.g. a "direct" strategy for footprints).
# ---------------------------------------------------------------------------
_fixtures_dir = Path(__file__).parent / "fixtures"


def _install_search_strategy(ctx: "TopologyContext") -> None:
    ctx.database.run_sql(_fixtures_dir / "identity" / "search.sql")


SEARCH_STRATEGY = IdentityStrategy(
    key="search",
    identity_column="unit_id",
    install=_install_search_strategy,
)


@dataclass
class TopologyContext:
    """Configuration for the Mapboard topology instance"""

    database: Database
    data_schema: str
    topo_schema: str
    identity_strategy: IdentityStrategy
    srid: int = 4326
    tolerance: float = 0.0001
    create_extra_fields: bool = False
    composite_layers: bool = False
    # The table holding boundary features (lines or polygons) that drive the topology.
    boundary_table: str = "linework"
    # Optional host-supplied callable that creates the data tables (and the identity
    # column, which references them). When None, the library creates its default data
    # tables; when set, the library's data-table / polygon-trigger fixtures are skipped.
    create_data_tables: Optional[Callable[["TopologyContext"], None]] = None
    # Whether to include listen/notify triggers for layer updates
    notify_triggers: bool = True

    @property
    def manage_data_tables(self) -> bool:
        """True when the library owns the data tables (no host callable supplied)."""
        return self.create_data_tables is None


# Context vars to store the current TopologyContext
_topo_ctx: ContextVar[TopologyContext | None] = ContextVar("topo_ctx", default=None)
_statement_cache: ContextVar[dict[str, TextClause]] = ContextVar(
    "_statement_cache", default={}
)


def get_context() -> TopologyContext:
    ctx = _topo_ctx.get()
    if ctx is None:
        raise RuntimeError("Topology context not initialized")
    return ctx


def get_database() -> Database:
    return get_context().database


def create_context(
    database: BaseDatabase,
    *,
    create_extra_fields: bool = True,
    composite_layers: bool = True,
    identity_strategy: IdentityStrategy = None,
    boundary_table: str = None,
    create_data_tables: Optional[Callable[["TopologyContext"], None]] = None,
    notify_triggers: bool = True,
    **kwargs,
) -> TopologyContext:
    """Create a new TopologyContext instance to configure the topology manager application"""

    env = kwargs.get("env", os.environ)

    data_schema = kwargs.get("data_schema", env.get("MAPBOARD_DATA_SCHEMA"))
    topo_schema = kwargs.get("topo_schema", env.get("MAPBOARD_TOPO_SCHEMA"))
    srid = kwargs.get("srid", int(env.get("MAPBOARD_SRID", 4326)))
    tolerance = kwargs.get(
        "tolerance", float(env.get("MAPBOARD_TOPO_TOLERANCE", 0.00001))
    )

    if data_schema is None or topo_schema is None:
        raise RuntimeError("Database schema not set")
    data_schema = str(data_schema)
    topo_schema = str(topo_schema)

    if boundary_table is None:
        boundary_table = env.get("MAPBOARD_BOUNDARY_TABLE", "linework")

    strategy = identity_strategy or SEARCH_STRATEGY
    face_identity_column = strategy.identity_column

    _database = Database(database.engine)
    _database.instance_params = {
        "data_schema": Identifier(data_schema),
        "topo_schema": Identifier(topo_schema),
        "index_prefix": SQL(f"{data_schema}_"),
        "topo_prefix": SQL(f"{topo_schema}_"),
        "topo_name": topo_schema,
        "topo_name_literal": Literal(topo_schema),
        "data_schema_name": data_schema,
        "data_schema_name_literal": Literal(data_schema),
        "srid": srid,
        "srid_literal": Literal(srid),
        "tolerance": tolerance,
        "boundary_table": Identifier(data_schema, boundary_table),
        "boundary_table_literal": Literal(boundary_table),
        "face_identity_column": Identifier(face_identity_column),
    }

    ctx = TopologyContext(
        database=_database,
        data_schema=data_schema,
        topo_schema=topo_schema,
        identity_strategy=strategy,
        srid=srid,
        tolerance=tolerance,
        create_extra_fields=create_extra_fields,
        composite_layers=composite_layers,
        boundary_table=boundary_table,
        create_data_tables=create_data_tables,
        notify_triggers=notify_triggers,
    )

    _side_effects(ctx)
    return ctx


def _side_effects(ctx):
    # This quiets a warning about an unknown topogeometry type
    pg.ischema_names["topogeometry"] = pg.ischema_names["geometry"]
    _topo_ctx.set(ctx)


def sql(key_path: str) -> TextClause:
    if key_path in _statement_cache.get():
        return _statement_cache.get()[key_path]

    _path = Path(__file__).parent / f"{key_path}.sql"
    with open(_path) as f:
        stmt = f.read()
        _statement_cache.get()[key_path] = stmt
        return stmt
