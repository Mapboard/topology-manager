from contextvars import ContextVar
from pathlib import Path

from dotenv import load_dotenv
from macrostrat.database import Database as _Database
from macrostrat.utils import relative_path
from sqlalchemy.sql.expression import TextClause, text

load_dotenv()


class Database(_Database):
    def proc(self, name):
        return self.run_sql(sql(name))


_db_ctx: ContextVar[Database] = ContextVar("db_ctx", default=None)
_statement_cache: ContextVar[dict[str, TextClause]] = ContextVar(
    "_statement_cache", default={}
)


def get_database() -> Database:
    db = _db_ctx.get()
    if db is None:
        raise RuntimeError("Database not initialized")
    return db


def set_database(database: str):
    _db_ctx.set(Database(database))


def sql(key_path: str) -> TextClause:
    if key_path in _statement_cache.get():
        return _statement_cache.get()[key_path]

    _path = Path(__file__).parent / f"{key_path}.sql"
    with open(_path) as f:
        stmt = text(f.read())
        _statement_cache.get()[key_path] = stmt
        return stmt
