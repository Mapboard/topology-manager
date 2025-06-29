"""
Test that the topology manager correctly notifies the 'events' channel when linework is updated.
"""

import asyncio
import pytest
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from .helpers import square, insert_line
from ..database import get_database
from contextvars import ContextVar
from macrostrat.utils import get_logger


import threading
import time
import psycopg2
import select

log = get_logger(__name__)


def send_notify(engine, channel: str, message: str):
    """Sends a NOTIFY command after a short delay to ensure listener is ready."""
    time.sleep(0.5)  # Give listener time to start
    log.info("Started notifier thread for channel: %s", channel)
    conn = engine.connect().connection
    with conn.cursor() as cur:
        cur.execute(f"NOTIFY {channel}, %s;", (message,))
        log.info("Sent notification on channel: %s with message: %s", channel, message)
        conn.commit()


def listen_notify(db, channel: str, timeout: float = 2.0):
    """Listens for a NOTIFY on the given channel."""
    # Connect to the database and set isolation level to autocommit
    conn = db.engine.connect().connection
    conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
    with conn.cursor() as cur:
        cur.execute(f"LISTEN {channel};")
        log.info("Listening for notifications on channel: %s", channel)

        # Wait for notify
        start = time.time()
        while True:
            if (time.time() - start) > timeout:
                break
            if select.select([conn], [], [], timeout)[0]:
                conn.poll()
                while conn.notifies:
                    return conn.notifies.pop(0)
    return None


def test_listen_notify_psycopg2(db):
    channel = "test_channel"
    message = "hello_world"

    # Start the notifier in a background thread
    notifier = threading.Thread(target=send_notify, args=(db.engine, channel, message))
    notifier.start()

    # Listen for notification
    notification = listen_notify(db, channel)

    notifier.join()

    # Assert notification was received
    assert notification is not None, "No notification received"
    assert notification.channel == channel
    assert notification.payload == message


def _perform_linework_update(db):
    # Wait a moment to ensure the listener is ready
    time.sleep(0.5)
    log.info("Performing linework update in a separate thread")
    insert_line(
        db,
        square(2, (0, 0)),
        type="bedrock",
        map_layer="surficial",
    )
    db.session.commit()
    log.info("Linework update completed, sending notification")


_did_notify = ContextVar("_did_notify", default=False)


@pytest.fixture(scope="function")
def db_no_transaction(base_db):
    """Fixture to set up the database for testing."""
    db = base_db
    yield db
    # Remove the test data after the test
    db.run_sql("""TRUNCATE TABLE {data_schema}.linework CASCADE;""")


def test_linework_notify(db_no_transaction):
    db = db_no_transaction
    # Set up the polling mechanism to listen for notifications
    conn = db.engine.connect().connection

    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cursor = conn.cursor()

    cursor.execute("LISTEN events;")

    def handle_notify():
        conn.poll()
        for notify in conn.notifies:
            data = notify.payload
            assert (
                data == "linework_updated"
            ), f"Expected 'linework_updated', got {data}"
            _did_notify.set(True)
            # Close the connection to stop listening
        conn.notifies.clear()

    # Set up a loop to poll for notifications
    # loop = asyncio.get_event_loop()
    # loop.add_reader(conn, handle_notify)

    # Perform an operation that should trigger a notification,
    # on a different thread
    # Wait a tick to ensure the listener is ready
    notifier = threading.Thread(target=_perform_linework_update, args=(db,))
    # notifier = threading.Thread(target=send_notify, args=(db.engine, "events", "hello"))

    notifier.start()

    notification = listen_notify(db, "events", timeout=2.0)

    notifier.join()
    did_notify = notification is not None

    # loop.run_in_executor(None, _perform_linework_update)

    # Wait for a short time to allow the notification to be processed
    # loop.run_until_complete(asyncio.sleep(2))

    # Check if the notification was received
    # did_notify = _did_notify.get()
    assert did_notify, "Did not receive notification for linework update"
