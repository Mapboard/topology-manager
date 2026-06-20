from dotenv import load_dotenv
import logging
from importlib import import_module
from pathlib import Path
from macrostrat.database.utils import temporary_database
from macrostrat.database import Database
import os
from pytest import fixture

import_module("mapboard.topology_manager.config")

disable_loggers = ["macrostrat.database.utils"]
# INFO log level

# disable_loggers = []


def pytest_configure():
    # Quiet verbose logging
    for logger_name in disable_loggers:
        logger = logging.getLogger(logger_name)
        logger.disabled = True

    log = logging.getLogger("mapboard.topology_manager.update_faces")
    log.setLevel(logging.INFO)


# Add option to keep the database after tests
def pytest_addoption(parser):
    parser.addoption(
        "--no-drop",
        action="store_true",
        default=False,
        help="Keep the database after tests",
    )
    parser.addoption(
        "--commit",
        action="store_true",
        default=False,
        help="Commit the database after tests",
    )

@fixture(scope="session")
def empty_db(pytestconfig):

    envfile = Path(__file__).parent.parent / ".env"
    if envfile.exists():
        load_dotenv(envfile)
    testing_db = os.getenv("TOPO_TESTING_DATABASE_URL")
    if testing_db is None:
        raise RuntimeError("TOPO_TESTING_DATABASE_URL not set")

    # Check if we are dropping the database after tests
    drop = not pytestconfig.getoption("--no-drop")

    with temporary_database(testing_db, drop=False, ensure_empty=True) as engine:
        database = Database(engine.url)
        yield database

