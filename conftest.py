from dotenv import load_dotenv

load_dotenv()

from mapboard.topology_manager.tests.fixtures import db, empty_db


# Add option to keep the database after tests
def pytest_addoption(parser):
    parser.addoption(
        "--no-drop",
        action="store_true",
        default=False,
        help="Keep the database after tests",
    )
