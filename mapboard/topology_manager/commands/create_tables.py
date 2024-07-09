from pathlib import Path

from ..database import Database

fixtures_dir = Path(__file__).parent.parent / "fixtures"


def _create_tables(db: Database):
    print(db.instance_params)
    _fixtures = list(fixtures_dir.glob("*.sql"))
    _fixtures.sort()

    for fixture in _fixtures:
        print(f"{fixture}")
        db.run_sql(fixture)
        print("")
