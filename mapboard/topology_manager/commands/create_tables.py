from pathlib import Path

from ..config import TopologyContext

fixtures_dir = Path(__file__).parent.parent / "fixtures"


def _create_tables(ctx: TopologyContext):
    print(ctx.database.instance_params)
    db = ctx.database
    _fixtures = list(fixtures_dir.glob("*.sql"))
    _fixtures.sort()

    for fixture in _fixtures:
        print(f"{fixture}")
        db.run_sql(fixture)
        print("")
