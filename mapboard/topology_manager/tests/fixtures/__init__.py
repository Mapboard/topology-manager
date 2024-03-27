import os

from macrostrat.database.utils import temp_database
from pytest import fixture
from sqlalchemy import event
from sqlalchemy.orm import Session, scoped_session

from ...commands.create_tables import _create_tables
from ...database import Database
from .demo_units import create_demo_units

testing_db = os.getenv("TOPO_TESTING_DATABASE_URL")


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
def db(base_db):
    """Create a database session that is rolled back after each test

    This is based on the Sparrow's implementation:
    https://github.com/EarthCubeGeochron/Sparrow/blob/main/backend/conftest.py
    """

    with base_db.savepoint() as db:
        yield db
