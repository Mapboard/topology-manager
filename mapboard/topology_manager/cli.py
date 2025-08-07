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


def operation_command(db, name: str, ask: bool = True):
    # Prompt user for confirmation
    if ask:
        res = Confirm.ask(f"Do you really want to {name} the topology?")
        if not res:
            return
    db.run_sql(sql(f"procedures/{name}-topology"))


def delete_topology(confirm=True):
    """Delete the topology"""
    db = get_database()
    operation_command(db, "delete", ask=confirm)


def reset_topology(confirm: bool = True):
    """Reset the topology"""
    db = get_database()
    operation_command(db, "reset", ask=confirm)


# Add commands for delete and reset operations
app.add_command(delete_topology, name="delete", short_help="Delete the topology")
app.add_command(reset_topology, name="reset", short_help="Reset the topology")


@app.command(name="show-errors")
def show_errors():
    """Show topology errors"""
    db = get_database()
    _query = sql("procedures/get-contacts-with-errors")
    res = db.run_query(_query)
    for row in res:
        console.print(f"[dim]{row.id}[/dim] [red]{row.topology_error}[/red]")
