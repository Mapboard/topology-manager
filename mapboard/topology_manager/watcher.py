import asyncio
from _contextvars import ContextVar
from json import loads, JSONDecodeError

from mapboard.topology_manager import update
from mapboard.topology_manager.config import get_context
from mapboard.topology_manager.utilities import console

update_in_progress = ContextVar("update_in_progress", default=False)
needs_update = ContextVar("needs_update", default=True)


def start_watcher(ctx = None, **kwargs):
    if ctx is None:
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
