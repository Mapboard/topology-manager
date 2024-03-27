from .clean_topology import clean_topology
from .create_tables import create_tables
from .update import update
from .update_contacts import update_contacts
from .update_faces import update_faces


def add_all_commands(app):
    app.add_command(clean_topology)
    app.add_command(create_tables)
    app.add_command(update)
    app.add_command(update_contacts)
    app.add_command(update_faces)
