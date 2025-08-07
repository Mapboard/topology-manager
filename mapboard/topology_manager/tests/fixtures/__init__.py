import os
from macrostrat.database.utils import temp_database
from macrostrat.utils import get_logger
from pytest import fixture

from .demo_units import create_demo_units
from ...commands.create_tables import _create_tables
from ...database import Database

testing_db = os.getenv("TOPO_TESTING_DATABASE_URL")
if not testing_db:
    raise RuntimeError("TOPO_TESTING_DATABASE_URL is not set")

log = get_logger(__name__)


@fixture(scope="session")
def empty_db(pytestconfig):
    # Check if we are dropping the database after tests
    drop = not pytestconfig.getoption("--no-drop")

    with temp_database(testing_db, drop=drop, ensure_empty=True) as engine:
        os.environ["MAPBOARD_DATABASE_URL"] = str(engine.url)
        os.environ["MAPBOARD_DATA_SCHEMA"] = "test_map_data"
        os.environ["MAPBOARD_TOPO_SCHEMA"] = "test_topology"
        os.environ["MAPBOARD_SRID"] = "32612"
        os.environ["MAPBOARD_TOPO_TOLERANCE"] = "0.1"
        database = Database(engine.url)
        database.set_active()
        yield database


@fixture(scope="session")
def base_db(empty_db):
    _create_tables(empty_db)
    create_demo_units(empty_db)
    yield empty_db


@fixture(scope="class")
def db(base_db, pytestconfig):
    """Create a database session that is rolled back after each test

    This is based on the Sparrow's implementation:
    https://github.com/EarthCubeGeochron/Sparrow/blob/main/backend/conftest.py
    """

    # Create a new database session for each test
    base_db.automap(schemas=["test_map_data"])

    commit = pytestconfig.getoption("--commit")
    if commit:
        # Enable auto-commit mode
        yield base_db
    else:
        with base_db.transaction(rollback="always"):
            log.info("Starting database transaction")
            yield base_db
        log.info("Rolling back database transaction")
