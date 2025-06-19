from dotenv import load_dotenv
import logging

load_dotenv()

from mapboard.topology_manager.tests.fixtures import *

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
