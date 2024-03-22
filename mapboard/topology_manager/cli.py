from typer import Option, Typer

from .commands import clean_topology, create_tables
from .database import get_database, set_database


class App(Typer):
    def __init__(self, *args, **kwargs):
        kwargs["no_args_is_help"] = True
        super().__init__(*args, **kwargs)

    def add_command(self, f, *args, **kwargs):
        return self.command(*args, **kwargs)(f)


app = App()


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


app.add_command(create_tables, name="create-tables")
app.add_command(clean_topology, name="clean-topology")
