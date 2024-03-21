from contextvars import ContextVar

from macrostrat.database import Database
from typer import Option, Typer

app = Typer(no_args_is_help=True)

db_ctx: ContextVar[Database] = ContextVar("db_ctx", default=None)


def get_database() -> Database:
    db = db_ctx.get()
    if db is None:
        raise RuntimeError("Database not initialized")
    return db


@app.command()
def test():
    # Your code here
    db = get_database()

    print("Welcome to Topology Manager!")
    print(db.query("SELECT 1"))


@app.callback()
def main(
    database: str = Option(
        None, envvar="MAPBOARD_DATABASE_URL", help="Database connection URL"
    ),
):
    if database is not None:
        db_ctx.set(Database(database))
