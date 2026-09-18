from typing import Optional

from macrostrat.database import Database
from rich.prompt import Confirm
from typer import Option, Typer

from .commands import create_tables, clean_topology, update_contacts, update_faces
from .commands.edge_relations import rebuild_edge_relations
from .commands.update_topology import update
from .watcher import start_watcher
from .config import FaceUpdateMode, get_database, sql, create_context, get_context
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
        db = Database(database)
        create_context(db)


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
    face_update_mode: Optional[FaceUpdateMode] = Option(
        None,
        help="How to persist faces: 'move' primitives between existing faces, "
        "or 'replace' overlapping faces (defaults to MAPBOARD_FACE_UPDATE_MODE / 'move')",
    ),
):
    """Update the topology"""

    ctx = get_context()

    kwargs = dict(
        composite_layers=composite_layers,
        face_update_mode=face_update_mode,
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


@app.command(name="update-faces")
def _update_faces(
    reset: bool = Option(False, help="Rebuild from scratch"),
    incremental: bool = Option(
        True, help="Persist faces in batches as they are computed"
    ),
    persist_interval: int = Option(100, help="Batch size for incremental persistence"),
    face_update_mode: Optional[FaceUpdateMode] = Option(
        None,
        help="How to persist faces: 'move' primitives between existing faces, "
        "or 'replace' overlapping faces (defaults to MAPBOARD_FACE_UPDATE_MODE / 'move')",
    ),
):
    """Update faces"""
    ctx = get_context()
    update_faces(
        ctx,
        reset=reset,
        incremental=incremental,
        persist_interval=persist_interval,
        face_update_mode=face_update_mode,
    )


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
