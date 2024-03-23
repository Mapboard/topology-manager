from rich.prompt import Confirm
from typer import Option, Typer

from .commands import add_all_commands
from .database import get_database, set_database, sql
from .utilities import console


class App(Typer):
    def __init__(self, *args, **kwargs):
        kwargs["no_args_is_help"] = True
        super().__init__(*args, **kwargs)

    def add_command(self, f, *args, **kwargs):
        return self.command(*args, **kwargs)(f)


app = App()


@app.callback()
def main(
    database: str = Option(
        None, envvar="MAPBOARD_DATABASE_URL", help="Database connection URL"
    ),
):
    if database is not None:
        set_database(database)


add_all_commands(app)


def _operation_command(name):
    # Prompt user for confirmation
    res = Confirm.ask(f"Do you really want to {name} the topology?")
    if not res:
        return
    db = get_database()
    db.proc(f"procedures/{name}-topology")


for op in ["delete", "reset"]:

    def command():
        _operation_command(op)

    app.add_command(command, name=op, short_help=f"{op.capitalize()} the topology")


@app.command(name="show-errors")
def show_errors():
    """Show topology errors"""
    db = get_database()
    _query = sql("procedures/get-contacts-with-errors")
    res = db.run_query(_query)
    for row in res:
        console.print(f"[dim]{row.id}[/dim] [red]{row.topology_error}[/red]")
