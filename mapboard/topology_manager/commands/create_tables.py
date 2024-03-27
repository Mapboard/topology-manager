from pathlib import Path

from macrostrat.database import Database

from ..database import get_database

fixtures_dir = Path(__file__).parent.parent / "fixtures"


def create_tables():
    """Create tables"""
    db = get_database()
    _create_tables(db)


def _create_tables(db: Database):
    _fixtures = list(fixtures_dir.glob("*.sql"))
    _fixtures.sort()

    for fixture in _fixtures:
        db.run_sql(fixture)
