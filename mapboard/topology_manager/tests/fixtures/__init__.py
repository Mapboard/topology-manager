import os

from macrostrat.database.utils import temp_database
from macrostrat.database import Database
from pytest import fixture
from macrostrat.utils import get_logger
from psycopg.sql import Identifier

from ...commands.create_tables import _create_tables
from ...config import create_context
from .demo_units import create_demo_units

testing_db = os.getenv("TOPO_TESTING_DATABASE_URL")

log = get_logger(__name__)


@fixture(scope="session")
def empty_ctx(pytestconfig):
    # Check if we are dropping the database after tests
    drop = not pytestconfig.getoption("--no-drop")

    with temp_database(testing_db, drop=False, ensure_empty=True) as engine:
        database = Database(engine.url)
        ctx = create_context(
            database,
            topo_schema="test_topology",
            data_schema="test_map_data",
            srid=32612,
            tolerance=0.1,
        )
        yield ctx
        if drop:
            # Drop the database with force
            url = engine.url
            database_name = url.database
            url.set(database=None)
            user_db = Database(url)
            user_db.run_sql(
                "COMMIT; DROP DATABASE {database} WITH (FORCE)",
                dict(database=Identifier(database_name)),
            )


@fixture(scope="session")
def empty_db(empty_ctx):
    return empty_ctx.database


@fixture(scope="session")
def base_ctx(empty_ctx):
    _create_tables(empty_ctx)
    create_demo_units(empty_ctx.database)
    yield empty_ctx


@fixture(scope="session")
def base_db(base_ctx):
    return base_ctx.database


@fixture(scope="class")
def ctx(base_ctx, pytestconfig):
    """Create a database session that is rolled back after each test

    This is based on the Sparrow's implementation:
    https://github.com/EarthCubeGeochron/Sparrow/blob/main/backend/conftest.py
    """

    base_db = base_ctx.database
    # Create a new database session for each test
    base_db.automap(schemas=["test_map_data"])

    commit = pytestconfig.getoption("--commit")
    rollback = "never" if commit else "always"
    with base_db.transaction(rollback=rollback):
        log.info("Starting database transaction")
        yield base_ctx
        if rollback == "always":
            log.info("Rolling back database transaction")


@fixture(scope="class")
def db(ctx):
    return ctx.database
