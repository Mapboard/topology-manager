from contextlib import contextmanager
from contextvars import ContextVar
from os import environ
from pathlib import Path

from dotenv import load_dotenv
from macrostrat.database import Database as _Database
from psycopg2.sql import SQL, Identifier
from sqlalchemy import event
from sqlalchemy.orm import Session
from sqlalchemy.sql.expression import TextClause, text

load_dotenv()


class Database(_Database):
    def proc(self, name, params=None, **kwargs):
        if params is None:
            params = {}
        params.update(get_params())
        return super().run_sql(sql(name), params, **kwargs)

    def run_sql(self, sql, params=None, **kwargs):
        if params is None:
            params = {}
        params.update(get_params())
        return super().run_sql(sql, params, **kwargs)

    def run_query(self, sql, params=None, **kwargs):
        if params is None:
            params = {}
        params.update(get_params())
        return super().run_query(sql, params, **kwargs)

    def set_active(self):
        _db_ctx.set(self)

    @contextmanager
    def rollback(self):
        """Create a database session that is rolled back after each test

        This is based on the Sparrow's implementation:
        https://github.com/EarthCubeGeochron/Sparrow/blob/main/backend/conftest.py
        """
        connection = self.engine.connect()
        transaction = connection.begin()
        session = Session(bind=connection)

        # start the session in a SAVEPOINT...
        # start the session in a SAVEPOINT...
        session.begin_nested()

        # then each time that SAVEPOINT ends, reopen it
        @event.listens_for(session, "after_transaction_end")
        def restart_savepoint(session, transaction):
            if transaction.nested and not transaction._parent.nested:
                # ensure that state is expired the way
                # session.commit() at the top level normally does
                # (optional step)
                session.expire_all()
                session.begin_nested()

        prev_session = self.session
        self.session = session

        try:
            yield self
        except Exception as e:
            raise e
        finally:
            session.close()
            transaction.rollback()
            connection.close()

            self.session = prev_session


_db_ctx: ContextVar[Database | None] = ContextVar("db_ctx", default=None)
_statement_cache: ContextVar[dict[str, TextClause]] = ContextVar(
    "_statement_cache", default={}
)


def get_database() -> Database:
    db = _db_ctx.get()
    if db is None:
        raise RuntimeError("Database not initialized")
    return db


def get_params():
    """Get parameters for topology calculations. Ideally, these should come
    from project settings, but for now they are set in the environment."""
    data_schema = environ.get("MAPBOARD_DATA_SCHEMA")
    topo_schema = environ.get("MAPBOARD_TOPO_SCHEMA")
    srid = int(environ.get("MAPBOARD_SRID", "4326"))
    if data_schema is None or topo_schema is None:
        raise RuntimeError("Database schema not set")

    return {
        "data_schema": Identifier(data_schema),
        "topo_schema": Identifier(topo_schema),
        "index_prefix": SQL(f"{data_schema}_"),
        "topo_prefix": SQL(f"{topo_schema}_"),
        "topo_name": topo_schema,
        "data_schema_name": data_schema,
        "srid": srid,
        "tolerance": float(environ.get("MAPBOARD_TOPO_TOLERANCE", 0.1)),
    }


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
