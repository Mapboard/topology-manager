from dataclasses import dataclass
from macrostrat.database import Database as BaseDatabase
import os
from psycopg.sql import SQL, Identifier, Literal
from sqlalchemy.sql.expression import TextClause
from contextvars import ContextVar
from sqlalchemy.dialects.postgresql import base as pg
from pathlib import Path


class Database(BaseDatabase):
    def proc(self, name, params=None, **kwargs):
        return super().run_sql(sql(name), params, **kwargs)


@dataclass
class TopologyContext:
    """Configuration for the Mapboard topology instance"""

    database: Database
    data_schema: str
    topo_schema: str
    srid: int = 4326
    tolerance: float = 0.0001
    create_extra_fields: bool = False
    composite_layers: bool = False


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
    }

    ctx = TopologyContext(
        database=_database,
        data_schema=data_schema,
        topo_schema=topo_schema,
        srid=srid,
        tolerance=tolerance,
        create_extra_fields=create_extra_fields,
        composite_layers=composite_layers,
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
