from pathlib import Path
from typing import Callable

from macrostrat.utils import get_logger

from ..config import TopologyContext

fixtures_dir = Path(__file__).parent.parent / "fixtures"

log = get_logger(__name__)


def create_tables(
    ctx: TopologyContext, create_data_tables: Callable[[TopologyContext], None] = None
):
    db = ctx.database
    _fixtures = list(fixtures_dir.glob("*.sql"))
    _fixtures.sort()

    skipped = []
    if not ctx.notify_triggers:
        skipped += ["notify"]
    if ctx.in_macrostrat_mode:
        skipped += ["data-tables", "linework-triggers", "polygon-triggers"]

    did_run_data_tables = False
    for fixture in _fixtures:
        should_skip = False

        if (
            create_data_tables is not None
            and "data-tables" in fixture.name
            and not did_run_data_tables
        ):
            # Run the create-data-tables function
            create_data_tables(ctx)
            did_run_data_tables = True
            continue

        for pattern in skipped:
            if pattern in fixture.name:
                log.info(f"Skipping {fixture}")
                should_skip = True

        if should_skip:
            continue
        print(f"{fixture}")
        db.run_sql(fixture)
        print("")
