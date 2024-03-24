import asyncio
from contextvars import ContextVar

from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from sqlalchemy import text
from typer import Option

from ..database import get_database
from ..utilities import console
from .clean_topology import clean_topology
from .update_contacts import update_contacts
from .update_faces import update_faces

verbose = True


def update(
    reset: bool = Option(False, help="Rebuild from scratch"),
    fill_holes: bool = Option(False, help="Try to fill all holes"),
    watch: bool = Option(False, help="Watch for changes"),
    fix_failed: bool = Option(False, help="Fix failed contacts"),
):
    """Update the topology"""

    if watch:
        _start_watcher()
        return

    _update(reset=reset, fill_holes=fill_holes, fix_failed=fix_failed)


def _update(
    reset: bool = False,
    fill_holes: bool = False,
    fix_failed: bool = False,
):
    """Update the topology"""

    console.print("Updating contacts", style="header")
    update_contacts(fix_failed=fix_failed)
    console.print("Updating faces", style="header")
    update_faces(reset=reset, fill_holes=fill_holes)
    console.print("Cleaning topology", style="header")
    clean_topology()


update_in_progress = ContextVar("update_in_progress", default=False)
needs_update = ContextVar("needs_update", default=True)


def _start_watcher():
    db = get_database()

    def _update_topology():
        if update_in_progress.get():
            needs_update.set(True)
            return
        if not needs_update.get():
            return

        update_in_progress.set(True)
        needs_update.set(False)
        _update()
        update_in_progress.set(False)

    conn = db.engine.connect()
    # Get a raw connection to listen for notifications
    conn = conn.connection
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)

    cursor = conn.cursor()
    cursor.execute("LISTEN events;")

    def handle_notify():
        conn.poll()
        for notify in conn.notifies:
            print(notify.payload)
            _update_topology()
        conn.notifies.clear()

    loop = asyncio.get_event_loop()
    loop.add_reader(conn, handle_notify)
    loop.run_forever()
