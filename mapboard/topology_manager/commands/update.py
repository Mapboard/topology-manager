import asyncio
import json
from contextvars import ContextVar
from time import perf_counter
from json import loads, JSONDecodeError

from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from typer import Option

from ..database import Database, get_database
from ..utilities import console
from .clean_topology import _clean_topology
from .update_contacts import _update_contacts
from .update_faces import update_faces
from .update_composite_layers import update_composite_layers
from macrostrat.utils.timer import Timer

verbose = True


def update(
    reset: bool = Option(False, help="Rebuild from scratch"),
    fill_holes: bool = Option(False, help="Try to fill all holes"),
    watch: bool = Option(False, help="Watch for changes"),
    fix_failed: bool = Option(False, help="Fix failed contacts"),
    composite_layers: bool = Option(False, help="Update composite layers"),
):
    """Update the topology"""

    db = get_database()

    kwargs = dict(
        composite_layers=composite_layers,
    )

    _update(
        db,
        reset=reset,
        fill_holes=fill_holes,
        fix_failed=fix_failed,
        **kwargs,
    )

    if watch:
        _start_watcher(**kwargs)


def _update(
    db: Database,
    *,
    reset: bool = False,
    fill_holes: bool = False,
    fix_failed: bool = False,
    incremental: bool = False,
    composite_layers: bool = False,
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
        )
        t1 = perf_counter()
        _print_step("Update faces", t1 - t0)

        console.print("Cleaning topology", style="header")
        _clean_topology(db)

        t2 = perf_counter()
        _print_step("Clean topology", t2 - t1)

        if composite_layers:
            console.print("Updating composite layers", style="header")
            update_composite_layers(db)
            t3 = perf_counter()
            _print_step("Update composite layers", t3 - t2)


update_in_progress = ContextVar("update_in_progress", default=False)
needs_update = ContextVar("needs_update", default=True)


def _start_watcher(**kwargs):
    db = get_database()

    def _update_topology():
        if update_in_progress.get():
            print("Update already in progress, skipping for now")
            needs_update.set(True)
            return
        if not needs_update.get():
            return

        update_in_progress.set(True)
        needs_update.set(False)
        # Do the update
        console.print("Updating topology", style="header")
        _update(db, **kwargs)
        update_in_progress.set(False)
        db.session.close()
        print("Done updating topology")

    console.print("Watching for changes", style="header")

    conn = db.engine.connect()
    # Get a raw connection to listen for notifications
    conn = conn.connection
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)

    cursor = conn.cursor()
    cursor.execute("LISTEN events;")

    def handle_notify():
        conn.poll()
        for notify in conn.notifies:
            should_update = False
            try:
                data = loads(notify.payload)
                print(data)
                # Ignore changes to the composite layers
                if not data.get("composite", True) and len(data["map_layers"]) > 0:
                    should_update = True
            except JSONDecodeError:
                print("Failed to decode JSON from notify payload")
                should_update = True
            if should_update:
                needs_update.set(True)
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
