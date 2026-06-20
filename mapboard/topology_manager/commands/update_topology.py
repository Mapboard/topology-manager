import asyncio
from contextvars import ContextVar
from time import perf_counter
from json import loads, JSONDecodeError

from ..config import TopologyContext, get_context
from ..utilities import console, print_step
from .clean_topology import _clean_topology
from .update_contacts import _update_contacts
from .update_faces import update_faces
from .update_composite_layers import update_composite_layers

verbose = True


def update(
    ctx: TopologyContext = None,
    *,
    reset: bool = False,
    fill_holes: bool = False,
    fix_failed: bool = False,
    incremental: bool = False,
    composite_layers: bool = False,
):
    """Update the topology"""
    if ctx is None:
        ctx = get_context()

    t_start = perf_counter()

    console.print("Updating boundaries", style="header")
    n_contacts_updated = _update_contacts(ctx, fix_failed=fix_failed)
    t1 = perf_counter()
    print_step("Update boundaries", t1 - t_start)

    if n_contacts_updated > 0:
        console.print("Cleaning topology (pre-faces)", style="header")
        _clean_topology(ctx)
        t2 = perf_counter()
        print_step("Clean topology (pre-faces)", t2 - t1)
    else:
        t2 = t1

    console.print("Updating faces", style="header")
    update_faces(
        ctx,
        reset=reset,
        fill_holes=fill_holes,
        incremental=incremental,
    )
    t3 = perf_counter()
    print_step("Update faces", t3 - t2)

    console.print("Cleaning topology", style="header")
    _clean_topology(ctx)
    t4 = perf_counter()
    print_step("Clean topology", t4 - t3)

    if composite_layers:
        console.print("Updating composite layers", style="header")
        update_composite_layers(ctx)
        t5 = perf_counter()
        print_step("Update composite layers", t5 - t4)

    print_step("Total", perf_counter() - t_start)


update_in_progress = ContextVar("update_in_progress", default=False)
needs_update = ContextVar("needs_update", default=True)


def _start_watcher(**kwargs):
    ctx = get_context()

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
        update(ctx, **kwargs)
        update_in_progress.set(False)
        ctx.database.session.close()

        print("Done updating topology")

    console.print("Watching for changes", style="header")

    sa_conn = ctx.database.engine.connect()
    # Get a raw driver connection to listen for notifications
    pooled_conn = sa_conn.connection
    conn = getattr(pooled_conn, "driver_connection", pooled_conn)
    conn.autocommit = True

    cursor = conn.cursor()
    cursor.execute("LISTEN events;")

    def _drain_notifies():
        notifies = getattr(conn, "notifies", [])
        if callable(notifies):
            while True:
                notify = next(conn.notifies(timeout=0, stop_after=1), None)
                if notify is None:
                    break
                yield notify
            return
        conn.poll()
        yield from notifies
        conn.notifies.clear()

    def handle_notify():
        for notify in _drain_notifies():
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

    loop = asyncio.get_event_loop()
    loop.add_reader(conn, handle_notify)
    try:
        loop.run_forever()
    finally:
        sa_conn.close()
