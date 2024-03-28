from ..database import get_database
from .clean_topology import clean_topology
from .create_tables import _create_tables
from .update import update
from .update_contacts import update_contacts
from .update_faces import update_faces


def create_tables_cmd():
    """Create tables"""
    db = get_database()
    _create_tables(db)


def add_all_commands(app):

    app.add_command(clean_topology)
    app.add_command(create_tables_cmd, name="create-tables")
    app.add_command(update)
    app.add_command(update_contacts)
    app.add_command(update_faces)
