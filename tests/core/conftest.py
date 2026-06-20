import os

from macrostrat.database.utils import temporary_database
from macrostrat.database import Database
from pytest import fixture
from macrostrat.utils import get_logger

from mapboard.topology_manager.config import create_context
from mapboard.topology_manager.manager import TopologyManager
from .demo_units import create_demo_units


log = get_logger(__name__)


@fixture(scope="session")
def base_mgr(empty_db):
    ctx = create_context(
        empty_db,
        topo_schema="test_topology",
        data_schema="test_map_data",
        srid=32612,
        tolerance=0.1,
    )
    manager = TopologyManager(ctx)
    manager.create_tables()
    create_demo_units(manager.db)
    yield manager


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
