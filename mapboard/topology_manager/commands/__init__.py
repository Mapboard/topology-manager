from ..config import get_context
from .clean_topology import clean_topology
from .create_tables import _create_tables
from .update import update
from .update_contacts import update_contacts
from .update_faces import update_faces


def create_tables_cmd():
    """Create tables"""
    ctx = get_context()
    _create_tables(ctx)


def add_all_commands(app):

    app.add_command(clean_topology)
    app.add_command(create_tables_cmd, name="create-tables")
    app.add_command(update)
    app.add_command(update_contacts)

    def _update_faces_cmd(**kwargs):
        ctx = get_context()
        update_faces(ctx, **kwargs)

    _update_faces_cmd.__doc__ = update_faces.__doc__
    _update_faces_cmd.__name__ = update_faces.__name__

    # The "Database" annotation cannot be used with Typer so we create a new set of annotations
    _update_faces_cmd.__annotations__ = {
        k: v for k, v in update_faces.__annotations__.items() if k != "db"
    }

    app.add_command(_update_faces_cmd)
