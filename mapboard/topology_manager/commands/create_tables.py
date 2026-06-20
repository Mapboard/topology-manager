from pathlib import Path

from macrostrat.utils import get_logger

from ..config import TopologyContext
from .check_setup import assert_topology_setup

fixtures_dir = Path(__file__).parent.parent / "fixtures"

log = get_logger(__name__)


def default_create_data_tables(ctx: TopologyContext):
    """Create the library's default feature tables (linework/polygon) and the
    default identity column.

    This is the fallback used when a context supplies no `create_data_tables`
    callable of its own; a host overrides it by setting `create_data_tables` on the
    context. Both run at the same point in the `create_tables` sequence.
    """
    for fixture in sorted(fixtures_dir.glob("*data-tables*.sql")):
        print(f"{fixture}")
        ctx.database.run_sql(fixture)


def create_tables(ctx: TopologyContext, *, check: bool = True):
    db = ctx.database
    _fixtures = sorted(fixtures_dir.glob("*.sql"))

    # Data tables (and the identity column they carry) are always created by a
    # callable — the host's, or the library default — so there is no host/library
    # branch here.
    create_data_tables = ctx.create_data_tables or default_create_data_tables

    skipped = []
    if not ctx.notify_triggers:
        skipped += ["notify"]
    if not ctx.manage_data_tables:
        # Polygon triggers act on the library-owned polygon table.
        skipped += ["polygon-triggers"]

    did_data_tables = False
    did_setup_identity = False

    def setup_identity():
        """Install the strategy's resolution functions, once the core topology
        functions exist (the identity functions depend on `__map_face_layer_id`
        etc. from 03-topology-functions) and before the 04+ fixtures that use them.
        The identity *column* is created earlier, by data-table creation."""
        nonlocal did_setup_identity
        if did_setup_identity:
            return
        ctx.identity_strategy.install(ctx)
        did_setup_identity = True

    for fixture in _fixtures:
        name = fixture.name

        # The data-table fixtures mark where data-table creation happens in the
        # sequence; the callable runs there (and supersedes running them directly).
        if "data-tables" in name:
            if not did_data_tables:
                did_data_tables = True
                create_data_tables(ctx)
            continue

        if any(pattern in name for pattern in skipped):
            log.info(f"Skipping {fixture}")
            continue

        print(f"{fixture}")
        db.run_sql(fixture)
        print("")

        if "topology-functions" in name:
            setup_identity()

    # Fallback, in case the topology-functions fixture was absent.
    setup_identity()

    # Fail fast on a misconfigured host strategy / data-table callable.
    if check:
        assert_topology_setup(ctx)
