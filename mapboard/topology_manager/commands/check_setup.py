"""Post-installation sanity checks.

After ``create_tables`` runs the (possibly host-supplied) ``create_data_tables``
and ``IdentityStrategy.install``, this verifies that the pieces those callables
are responsible for actually exist — so a misnamed identity column or a function
that ``install`` forgot to define fails immediately and legibly, rather than deep
in the update pipeline.
"""

from ..config import TopologyContext

# Functions every IdentityStrategy.install must leave defined in the topo schema.
IDENTITY_FUNCTIONS = (
    "identity_for_area",
    "identity_for_face",
    "faces_are_joinable",
    "map_face_is_identified",
)

# Columns the update pipeline relies on for any boundary table.
BOUNDARY_COLUMNS = ("geometry", "map_layer", "geometry_hash", "topology_error")


def _column_exists(db, schema, table, column) -> bool:
    return db.run_query(
        "SELECT EXISTS (SELECT 1 FROM information_schema.columns "
        "WHERE table_schema = :s AND table_name = :t AND column_name = :c)",
        dict(s=schema, t=table, c=column),
    ).scalar()


def _function_exists(db, schema, name) -> bool:
    return db.run_query(
        "SELECT EXISTS (SELECT 1 FROM pg_proc p "
        "JOIN pg_namespace n ON n.oid = p.pronamespace "
        "WHERE n.nspname = :s AND p.proname = :f)",
        dict(s=schema, f=name),
    ).scalar()


def _table_exists(db, schema, table) -> bool:
    return db.run_query(
        "SELECT to_regclass(:qname) IS NOT NULL",
        dict(qname=f"{schema}.{table}"),
    ).scalar()


def _topogeometry_registered(db, schema, table, column="topo") -> bool:
    return db.run_query(
        "SELECT EXISTS (SELECT 1 FROM topology.layer "
        "WHERE schema_name = :s AND table_name = :t AND feature_column = :c)",
        dict(s=schema, t=table, c=column),
    ).scalar()


def check_topology_setup(ctx: TopologyContext) -> list[str]:
    """Return a list of setup problems (empty when everything is in place)."""
    db = ctx.database
    topo = ctx.topo_schema
    data = ctx.data_schema
    column = ctx.identity_strategy.identity_column

    problems: list[str] = []

    # Identity column — created by data-table creation, must match the strategy's name.
    for table in ("map_face", "face_identity"):
        if not _column_exists(db, topo, table, column):
            problems.append(
                f"identity column {topo}.{table}.{column} is missing — data-table "
                f"creation must add the column named by IdentityStrategy.identity_column"
            )

    # Identity functions — defined by IdentityStrategy.install.
    for fn in IDENTITY_FUNCTIONS:
        if not _function_exists(db, topo, fn):
            problems.append(
                f"function {topo}.{fn}(...) is missing — IdentityStrategy.install must define it"
            )

    # Boundary table + its topogeometry and the columns the pipeline needs.
    boundary = ctx.boundary_table
    if not _table_exists(db, data, boundary):
        problems.append(f"boundary table {data}.{boundary} is missing")
    else:
        if not _topogeometry_registered(db, data, boundary):
            problems.append(
                f"boundary table {data}.{boundary} has no registered 'topo' "
                f"topogeometry column (topology.AddTopoGeometryColumn)"
            )
        for col in BOUNDARY_COLUMNS:
            if not _column_exists(db, data, boundary, col):
                problems.append(
                    f"boundary table {data}.{boundary} is missing required column '{col}'"
                )

    return problems


def assert_topology_setup(ctx: TopologyContext) -> TopologyContext:
    """Raise if the topology setup is incomplete, listing every problem found."""
    problems = check_topology_setup(ctx)
    if problems:
        raise RuntimeError(
            "Topology setup check failed:\n"
            + "\n".join(f"  - {p}" for p in problems)
        )
    return ctx
