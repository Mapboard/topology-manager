import os

from macrostrat.database.utils import temp_database
from pytest import fixture

from ...commands.create_tables import _create_tables
from ...database import Database, _db_ctx
from .demo_units import create_demo_units

testing_db = os.getenv("TOPO_TESTING_DATABASE_URL")


@fixture(scope="session")
def empty_db(pytestconfig):
    with temp_database(testing_db) as engine:
        os.environ["MAPBOARD_DATABASE_URL"] = str(engine.url)
        os.environ["MAPBOARD_DATA_SCHEMA"] = "test_map_data"
        os.environ["MAPBOARD_TOPO_SCHEMA"] = "test_topology"
        os.environ["MAPBOARD_SRID"] = "32612"
        os.environ["MAPBOARD_TOPO_TOLERANCE"] = "0.1"
        database = Database(engine.url)
        _db_ctx.set(database)
        yield database


@fixture(scope="session")
def db(empty_db):
    _create_tables(empty_db)
    create_demo_units(empty_db)
    return empty_db
