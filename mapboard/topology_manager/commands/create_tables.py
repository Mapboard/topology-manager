from pathlib import Path

from ..database import get_database

fixtures_dir = Path(__file__).parent.parent / "fixtures"


def create_tables():
    """Create tables"""
    db = get_database()

    _fixtures = fixtures_dir.glob("*.sql")
    _fixtures.sort()

    for fixture in _fixtures:
        db.run_sql(fixture)
