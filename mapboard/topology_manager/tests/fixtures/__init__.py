import os

from macrostrat.database.utils import temporary_database
from macrostrat.database import Database
from pytest import fixture
from macrostrat.utils import get_logger
from psycopg.sql import Identifier

from ...config import create_context
from ...manager import TopologyManager
from .demo_units import create_demo_units

testing_db = os.getenv("TOPO_TESTING_DATABASE_URL")

log = get_logger(__name__)


@fixture(scope="session")
def empty_mgr(pytestconfig):
    # Check if we are dropping the database after tests
    drop = not pytestconfig.getoption("--no-drop")

    with temporary_database(testing_db, drop=False, ensure_empty=True) as engine:
        database = Database(engine.url)
        ctx = create_context(
            database,
            topo_schema="test_topology",
            data_schema="test_map_data",
            srid=32612,
            tolerance=0.1,
        )
        manager = TopologyManager(ctx)
        yield manager
        if drop:
            # Drop the database with force
            url = engine.url
            database_name = url.database
            url.set(database=None)
            user_db = Database(url)
            user_db.run_sql(
                "DROP DATABASE {database} WITH (FORCE)",
                dict(database=Identifier(database_name)),
                use_transaction=False,
            )


@fixture(scope="session")
def empty_db(empty_mgr):
    return empty_mgr.db


@fixture(scope="session")
def base_mgr(empty_mgr):
    empty_mgr.create_tables()
    create_demo_units(empty_mgr.db)
    yield empty_mgr


@fixture(scope="session")
def base_db(base_mgr):
    return base_mgr.db


@fixture(scope="class")
def mgr(base_mgr, pytestconfig):
    """Create a database session that is rolled back after each test class.

    This is based on Sparrow's implementation:
    https://github.com/EarthCubeGeochron/Sparrow/blob/main/backend/conftest.py
    """
    base_db = base_mgr.db
    base_db.automap(schemas=["test_map_data"])

    commit = pytestconfig.getoption("--commit")
    rollback = "never" if commit else "always"
    with base_db.transaction(rollback=rollback):
        log.info("Starting database transaction")
        yield base_mgr
        if rollback == "always":
            log.info("Rolling back database transaction")


@fixture(scope="class")
def db(mgr):
    return mgr.db
