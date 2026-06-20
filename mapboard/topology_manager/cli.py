from rich.prompt import Confirm
from typer import Option, Typer

from .commands import create_tables, clean_topology, update_contacts, update_faces
from .commands.edge_relations import rebuild_edge_relations
from .commands.update_topology import update
from .watcher import start_watcher
from .config import get_database, sql, create_context, get_context
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
        create_context(database)


@app.command(name="create-tables")
def _create_tables():
    """Create tables"""
    ctx = get_context()
    create_tables(ctx)


@app.command(name="update")
def _update(
    reset: bool = Option(False, help="Rebuild from scratch"),
    fill_holes: bool = Option(False, help="Try to fill all holes"),
    watch: bool = Option(False, help="Watch for changes"),
    fix_failed: bool = Option(False, help="Fix failed contacts"),
    composite_layers: bool = Option(False, help="Update composite layers"),
):
    """Update the topology"""

    ctx = get_context()

    kwargs = dict(
        composite_layers=composite_layers,
    )

    update(
        ctx,
        reset=reset,
        fill_holes=fill_holes,
        fix_failed=fix_failed,
        **kwargs,
    )

    if watch:
        start_watcher(**kwargs)


@app.command(name="update-contacts")
def _update_contacts(fix_failed: bool = False):
    """Update contacts"""
    ctx = get_context()
    update_contacts(ctx, fix_failed)


def _update_faces(**kwargs):
    """Update faces"""
    ctx = get_context()
    update_faces(ctx, **kwargs)


# The "Database" annotation cannot be used with Typer so we create a new set of annotations
_update_faces.__annotations__ = {
    k: v for k, v in update_faces.__annotations__.items() if k != "ctx"
}

app.add_command(_update_faces, name="update-faces", help="Update faces")


@app.command(name="clean-topology")
def _clean_topology():
    """Clean the topology"""
    ctx = get_context()
    clean_topology(ctx)


@app.command(name="rebuild-edge-relations")
def _rebuild_edge_relations():
    """Rebuild the cached __edge_relation table (repair out-of-sync triggers)"""
    ctx = get_context()
    rebuild_edge_relations(ctx)


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
