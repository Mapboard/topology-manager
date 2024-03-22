from typer import Option, Typer

from .settings import get_database, set_database

app = Typer(no_args_is_help=True)


@app.command()
def test():
    # Your code here
    db = get_database()

    print("Welcome to Topology Manager!")
    print(db.run_query("SELECT 1").scalar())


@app.callback()
def main(
    database: str = Option(
        None, envvar="MAPBOARD_DATABASE_URL", help="Database connection URL"
    ),
):
    if database is not None:
        set_database(database)
