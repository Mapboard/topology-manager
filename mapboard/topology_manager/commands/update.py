import asyncio
from contextvars import ContextVar

from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from sqlalchemy import text
from typer import Option

from ..database import Database, get_database
from ..utilities import console
from .clean_topology import _clean_topology
from .update_contacts import _update_contacts
from .update_faces import _update_faces

verbose = True


def update(
    reset: bool = Option(False, help="Rebuild from scratch"),
    fill_holes: bool = Option(False, help="Try to fill all holes"),
    watch: bool = Option(False, help="Watch for changes"),
    bulk: bool = Option(False, help="Use bulk updates"),
    fix_failed: bool = Option(False, help="Fix failed contacts"),
):
    """Update the topology"""

    db = get_database()

    _update(db, reset=reset, fill_holes=fill_holes, fix_failed=fix_failed)

    if watch and bulk:
        raise ValueError("Bulk updates are not compatible with watching")

    if watch:
        _start_watcher()


def _update(
    db: Database,
    reset: bool = False,
    fill_holes: bool = False,
    fix_failed: bool = False,
    bulk: bool = False,
):
    """Update the topology"""
    console.print("Updating contacts", style="header")
    _update_contacts(db, fix_failed=fix_failed, bulk=bulk)
    console.print("Updating faces", style="header")
    _update_faces(db, reset=reset, fill_holes=fill_holes)
    console.print("Cleaning topology", style="header")
    _clean_topology(db)


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
        # Do the update
        _update(db)
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
            needs_update.set(True)
            _update_topology()
            if needs_update.get():
                _update_topology()
        conn.notifies.clear()

    loop = asyncio.get_event_loop()
    loop.add_reader(conn, handle_notify)
    loop.run_forever()
