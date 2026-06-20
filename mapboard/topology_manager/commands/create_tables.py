from pathlib import Path

from macrostrat.utils import get_logger

from ..config import TopologyContext
from .check_setup import assert_topology_setup

fixtures_dir = Path(__file__).parent.parent / "fixtures"

log = get_logger(__name__)


def create_tables(ctx: TopologyContext, *, check: bool = True):
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
        """Install the strategy's resolution functions. Runs once, after the core
        topology functions exist (the identity functions depend on
        ``__map_face_layer_id`` etc. from 03-topology-functions) and before the
        fixtures (04+) that reference them. The identity *column* is created
        earlier, by data-table creation."""
        nonlocal did_setup_identity
        if did_setup_identity:
            return
        ctx.identity_strategy.install(ctx)
        did_setup_identity = True

    handled_data_tables = False
    for fixture in _fixtures:
        name = fixture.name

        # The data-tables stage creates the feature tables and the identity column:
        # the host callable when supplied, otherwise the library fixture.
        if "data-tables" in name:
            if not handled_data_tables:
                handled_data_tables = True
                if host_managed:
                    ctx.create_data_tables(ctx)
                else:
                    print(f"{fixture}")
                    db.run_sql(fixture)
            elif not host_managed:
                print(f"{fixture}")
                db.run_sql(fixture)
            continue

        if any(pattern in name for pattern in skipped):
            log.info(f"Skipping {fixture}")
            continue

        print(f"{fixture}")
        db.run_sql(fixture)
        print("")

        # The strategy's functions depend on the core topology helpers, so install
        # them once those exist — before the 04+ fixtures that consume them.
        if "topology-functions" in name:
            setup_identity()

    # Fallback, in case the topology-functions fixture was absent.
    setup_identity()

    # Fail fast on a misconfigured host strategy / data-table callable.
    if check:
        assert_topology_setup(ctx)
