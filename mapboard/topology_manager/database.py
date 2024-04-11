import os
from contextlib import contextmanager
from contextvars import ContextVar
from pathlib import Path

from dotenv import load_dotenv
from macrostrat.database import Database as _Database
from psycopg2.sql import SQL, Identifier
from sqlalchemy import event
from sqlalchemy.orm import Session
from sqlalchemy.sql.expression import TextClause, text

load_dotenv()


class Database(_Database):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.set_params()

    def set_params(self, **kwargs):
        env = kwargs.pop("env", None)
        if env is None:
            env = os.environ

        data_schema = kwargs.get("data_schema", env.get("MAPBOARD_DATA_SCHEMA"))
        topo_schema = kwargs.get("topo_schema", env.get("MAPBOARD_TOPO_SCHEMA"))
        srid = kwargs.get("srid", int(env.get("MAPBOARD_SRID", 4326)))
        if data_schema is None or topo_schema is None:
            raise RuntimeError("Database schema not set")

        tolerance = kwargs.get(
            "tolerance", float(env.get("MAPBOARD_TOPO_TOLERANCE", 0.00001))
        )

        self.instance_params = {
            "data_schema": Identifier(data_schema),
            "topo_schema": Identifier(topo_schema),
            "index_prefix": SQL(f"{data_schema}_"),
            "topo_prefix": SQL(f"{topo_schema}_"),
            "topo_name": topo_schema,
            "data_schema_name": data_schema,
            "srid": srid,
            "tolerance": tolerance,
        }

    def proc(self, name, params=None, **kwargs):
        return super().run_sql(sql(name), params, **kwargs)

    def set_active(self):
        _db_ctx.set(self)


_db_ctx: ContextVar[Database | None] = ContextVar("db_ctx", default=None)
_statement_cache: ContextVar[dict[str, TextClause]] = ContextVar(
    "_statement_cache", default={}
)


def get_database() -> Database:
    db = _db_ctx.get()
    if db is None:
        raise RuntimeError("Database not initialized")
    return db


def set_database(database: str):
    if _db_ctx.get() is not None:
        return
    _db_ctx.set(Database(database))


def sql(key_path: str) -> TextClause:
    if key_path in _statement_cache.get():
        return _statement_cache.get()[key_path]

    _path = Path(__file__).parent / f"{key_path}.sql"
    with open(_path) as f:
        stmt = f.read()
        _statement_cache.get()[key_path] = stmt
        return stmt
