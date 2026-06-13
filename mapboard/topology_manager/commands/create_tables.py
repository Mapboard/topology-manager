from pathlib import Path
from macrostrat.utils import get_logger

from ..config import TopologyContext

fixtures_dir = Path(__file__).parent.parent / "fixtures"

log = get_logger(__name__)


def create_tables(ctx: TopologyContext):
    print(ctx.database.instance_params)
    db = ctx.database
    _fixtures = list(fixtures_dir.glob("*.sql"))
    _fixtures.sort()

    skipped = []
    if ctx.in_macrostrat_mode:
        skipped = ["data-tables", "linework", "polygon"]

    for fixture in _fixtures:
        print(f"{fixture}")
        should_skip = False
        for pattern in skipped:
            if pattern in fixture.name:
                log.info(f"Skipping {fixture}")
                should_skip = True
        if should_skip:
            continue

        db.run_sql(fixture)
        print("")
