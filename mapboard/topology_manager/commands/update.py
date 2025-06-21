import asyncio
from contextvars import ContextVar
from time import perf_counter

from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from typer import Option

from ..database import Database, get_database
from ..utilities import console
from .clean_topology import _clean_topology
from .update_contacts import _update_contacts
from .update_faces import update_faces
from macrostrat.utils.timer import Timer

verbose = True


def update(
    reset: bool = Option(False, help="Rebuild from scratch"),
    fill_holes: bool = Option(False, help="Try to fill all holes"),
    watch: bool = Option(False, help="Watch for changes"),
    fix_failed: bool = Option(False, help="Fix failed contacts"),
    composite_layers: bool = Option(True, help="Update composite layers"),
):
    """Update the topology"""

    db = get_database()

    _update(
        db,
        reset=reset,
        fill_holes=fill_holes,
        fix_failed=fix_failed,
        composite_layers=composite_layers,
    )

    if watch:
        _start_watcher()


def _update(
    db: Database,
    *,
    reset: bool = False,
    fill_holes: bool = False,
    fix_failed: bool = False,
    incremental: bool = False,
    composite_layers: bool = True,
):
    """Update the topology"""
    console.print("Updating contacts", style="header")
    timer = Timer()
    with timer.context():
        _update_contacts(db, fix_failed=fix_failed)
        print_step(timer, "Update contacts")
        _clean_topology(db)

        t0 = perf_counter()
        console.print("Updating faces", style="header")
        update_faces(
            db,
            reset=reset,
            fill_holes=fill_holes,
            incremental=incremental,
            composite_layers=composite_layers,
        )
        t1 = perf_counter()
        _print_step("Update faces", t1 - t0)

        console.print("Cleaning topology", style="header")
        _clean_topology(db)
        print_step(timer, "Clean topology")


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
        db.session.close()
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


def print_step(timer, step_name=None):
    step = timer.timings[-1]
    if step_name:
        step = timer._add_step(step_name)

    _print_step(step.name, step.delta)


def _print_step(name, tdelta):
    step_time = f"{tdelta:.2f} seconds"
    if tdelta > 60:
        step_time = f"{tdelta / 60:.2f} minutes"
    if tdelta < 0.5:
        step_time = f"{tdelta * 1000:.2f} ms"
    if tdelta < 0.0005:
        step_time = f"{tdelta * 1000 * 1000:.0f} µs"

    console.print(f"Step [bold underline]{name}[/] took [cyan bold]{step_time}")
