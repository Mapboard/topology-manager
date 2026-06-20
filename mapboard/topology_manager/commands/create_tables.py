from pathlib import Path
from typing import Callable

from macrostrat.utils import get_logger

from ..config import TopologyContext

fixtures_dir = Path(__file__).parent.parent / "fixtures"

log = get_logger(__name__)


def _add_identity_column(ctx: TopologyContext):
    """Add the strategy's identity column to the library-owned topology tables.

    The strategy *declares* the column (name + type spec, the latter possibly
    referencing template vars like {data_schema}); the library *executes* the DDL
    so hosts never need to ALTER these tables themselves.
    """
    name, type_spec = ctx.identity_strategy.identity_column
    for table in ("map_face", "face_identity"):
        ctx.database.run_sql(
            "ALTER TABLE {topo_schema}." + table
            + " ADD COLUMN IF NOT EXISTS " + name + " " + type_spec + ";"
        )


def create_tables(
    ctx: TopologyContext, create_data_tables: Callable[[TopologyContext], None] = None
):
    db = ctx.database
    _fixtures = list(fixtures_dir.glob("*.sql"))
    _fixtures.sort()

    skipped = []
    if not ctx.notify_triggers:
        skipped += ["notify"]
    if not ctx.manage_data_tables:
        # The host owns the feature tables and polygon triggers
        skipped += ["data-tables", "polygon-triggers"]

    did_setup_identity = False

    def setup_identity():
        """Install the identity strategy: its column on the library tables, then
        its resolution functions. Run once, after the data-table stage (so the
        tables the strategy reads exist) and before fixtures that depend on it."""
        nonlocal did_setup_identity
        if did_setup_identity:
            return
        _add_identity_column(ctx)
        ctx.identity_strategy.install(ctx)
        did_setup_identity = True

    handled_data_tables = False
    for fixture in _fixtures:
        name = fixture.name

        # The data-tables stage: the host callback creates the feature tables
        # (or, when managed, the library fixture does). Either way, install the
        # identity strategy immediately afterward.
        if "data-tables" in name:
            if not handled_data_tables:
                handled_data_tables = True
                if create_data_tables is not None:
                    create_data_tables(ctx)
                if ctx.manage_data_tables:
                    print(f"{fixture}")
                    db.run_sql(fixture)
                setup_identity()
            elif ctx.manage_data_tables:
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
