"""
Test that the topology manager correctly notifies the 'events' channel when linework is updated.
"""

from json import loads

import pytest
from .helpers import square, insert_line, map_layer_id
from macrostrat.utils import get_logger
from sqlalchemy import text


import threading
import time
from concurrent.futures import ThreadPoolExecutor, TimeoutError

log = get_logger(__name__)


def send_notify(engine, channel: str, message: str):
    """Sends a NOTIFY command after a short delay to ensure listener is ready."""
    time.sleep(0.5)  # Give listener time to start
    log.info("Started notifier thread for channel: %s", channel)
    engine.execute(text("SELECT pg_notify(%s, %s)"), (channel, message))


def listen_notify(engine, channel: str, timeout: float = 2.0):
    """Listens for a NOTIFY on the given channel."""
    # Connect to the database and set isolation level to autocommit
    conn = engine.connect().connection
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute(f"LISTEN {channel};")

        log.info("Listening for notifications on channel: %s", channel)
        gen = conn.notifies()
        res = consume_with_timeout(gen, timeout)
        return res

def consume_with_timeout(iterator, timeout_sec):
    with ThreadPoolExecutor(max_workers=1) as executor:
        # Submit the next(iterator) call to the thread pool
        future = executor.submit(next, iterator, None)
        try:
            item = future.result(timeout=timeout_sec)
            return item
        except TimeoutError:
            return None

@pytest.mark.skip(reason="We need to update this handling for Psycopg")
def test_listen_notify_psycopg(db):
    channel = "test_channel"
    message = "hello_world"
    # Start the notifier in a background thread
    notifier = threading.Thread(target=send_notify, args=(db.engine, channel, message))
    notifier.start()

    # Listen for notification
    notification = listen_notify(db.engine, channel)

    notifier.join()

    # Assert notification was received
    assert notification is not None, "No notification received"
    assert notification.channel == channel
    assert notification.payload == message


def _perform_linework_update(db, lyr):
    # Wait a moment to ensure the listener is ready
    time.sleep(0.5)
    log.info("Performing linework update in a separate thread")
    insert_line(
        db,
        square(2, (0, 0)),
        type="bedrock",
        map_layer=lyr,
    )
    db.session.commit()
    log.info("Linework update completed, sending notification")


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

    lyr = map_layer_id(db, "surficial")

    # Perform an operation that should trigger a notification,
    # on a different thread
    # Wait a tick to ensure the listener is ready
    notifier = threading.Thread(target=_perform_linework_update, args=(db, lyr))

    notifier.start()

    notification = listen_notify(db.engine, "events", timeout=2.0)

    notifier.join()

    data = loads(notification.payload)
    log.info("Received notification data: %s", data)

    assert data["operation"] == "INSERT"
    assert lyr in data["map_layers"]
    assert lyr in data["affected_layers"]
    assert data["editable"]
    assert not data["composite"]
