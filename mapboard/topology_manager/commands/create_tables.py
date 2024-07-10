from pathlib import Path
from macrostrat.utils import get_logger

from ..database import Database

fixtures_dir = Path(__file__).parent.parent / "fixtures"

log = get_logger(__name__)


def _create_tables(db: Database):
    log.info("Creating tables", db.instance_params)
    db.run_fixtures(fixtures_dir)
