from pathlib import Path
from macrostrat.utils import get_logger

from ..config import TopologyContext

fixtures_dir = Path(__file__).parent.parent / "fixtures"

log = get_logger(__name__)


def create_tables(ctx: TopologyContext):
    db = ctx.database
    _fixtures = list(fixtures_dir.glob("*.sql"))
    _fixtures.sort()

    skipped = []
    if not ctx.notify_triggers:
        skipped += ["notify"]
    if ctx.in_macrostrat_mode:
        skipped += ["data-tables", "linework", "polygon"]

    for fixture in _fixtures:
        should_skip = False
        for pattern in skipped:
            if pattern in fixture.name:
                log.info(f"Skipping {fixture}")
                should_skip = True
        if should_skip:
            continue
        print(f"{fixture}")
        db.run_sql(fixture)
        print("")
