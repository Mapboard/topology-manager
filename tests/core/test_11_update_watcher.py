import importlib
import threading
import time

import pytest

from ..helpers import insert_line, map_layer_id, square

update_cmd = importlib.import_module("mapboard.topology_manager.commands.update")


class _TestLoop:
    def __init__(self, callback_runner):
        self.reader = None
        self.callback = None
        self._callback_runner = callback_runner

    def add_reader(self, reader, callback):
        self.reader = reader
        self.callback = callback

    def run_forever(self):
        self._callback_runner(self.callback)


def _insert_linework(db, layer_id):
    insert_line(
        db,
        square(2, (0, 0)),
        type="bedrock",
        map_layer=layer_id,
    )
    db.session.commit()


@pytest.fixture(scope="function")
def mgr_no_transaction(base_mgr):
    mgr = base_mgr
    yield mgr
    mgr.database.run_sql("""TRUNCATE TABLE {data_schema}.linework CASCADE;""")


def test_start_watcher_handles_real_linework_event(mgr_no_transaction, monkeypatch):
    db = mgr_no_transaction.database
    layer_id = map_layer_id(db, "surficial")
    update_calls = []

    def _run_callbacks(callback):
        notifier = threading.Thread(
            target=_insert_linework, args=(db, layer_id), daemon=True
        )
        notifier.start()
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline and not update_calls:
            callback()
            time.sleep(0.05)
        notifier.join(timeout=1)

    test_loop = _TestLoop(_run_callbacks)

    monkeypatch.setattr(
        update_cmd,
        "_update",
        lambda passed_ctx, **kwargs: update_calls.append((passed_ctx, kwargs)),
    )
    monkeypatch.setattr(update_cmd.asyncio, "get_event_loop", lambda: test_loop)

    # Start the watch command
    update_cmd._start_watcher(composite_layers=True)

    assert test_loop.reader is not None
    assert len(update_calls) == 1
    assert update_calls[0] == (mgr_no_transaction._ctx, {"composite_layers": True})
