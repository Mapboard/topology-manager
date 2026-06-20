from pathlib import Path

from macrostrat.utils import get_logger

from ..config import TopologyContext

fixtures_dir = Path(__file__).parent.parent / "fixtures"

log = get_logger(__name__)


def create_tables(ctx: TopologyContext):
    db = ctx.database
    _fixtures = list(fixtures_dir.glob("*.sql"))
    _fixtures.sort()

    host_managed = ctx.create_data_tables is not None

    skipped = []
    if not ctx.notify_triggers:
        skipped += ["notify"]
    if host_managed:
        # The host owns the feature tables (and their identity column) and polygon triggers
        skipped += ["data-tables", "polygon-triggers"]

    did_setup_identity = False

    def setup_identity():
        """Install the strategy's resolution functions. Runs once, after the
        data-table stage (so the identity column and the tables it reads exist)
        and before fixtures that reference them."""
        nonlocal did_setup_identity
        if did_setup_identity:
            return
        ctx.identity_strategy.install(ctx)
        did_setup_identity = True

    handled_data_tables = False
    for fixture in _fixtures:
        name = fixture.name

        # The data-tables stage creates the feature tables and the identity column:
        # the host callable when supplied, otherwise the library fixture. The
        # identity functions are installed immediately afterward.
        if "data-tables" in name:
            if not handled_data_tables:
                handled_data_tables = True
                if host_managed:
                    ctx.create_data_tables(ctx)
                else:
                    print(f"{fixture}")
                    db.run_sql(fixture)
                setup_identity()
            elif not host_managed:
                print(f"{fixture}")
                db.run_sql(fixture)
            continue

        # Once past the data-tables stage, ensure identity is in place before
        # running anything that references it.
        if handled_data_tables:
            setup_identity()

        if any(pattern in name for pattern in skipped):
            log.info(f"Skipping {fixture}")
            continue

        print(f"{fixture}")
        db.run_sql(fixture)
        print("")

    # Fallback, in case there were no data-table fixtures at all
    setup_identity()
