"""Node boundary rows into the topology.

`update_contacts` is the whole-row pass the update pipeline runs: every boundary
row not yet noded from its current geometry is noded in one `toTopoGeom` call,
in adaptively sized batches. `update_boundary_piece` is the piecewise entry point
for a host whose rows are too large or fragile to node whole: it nodes one piece
of a row's geometry into the row's existing topogeometry, and the host decides
how to cut, simplify and retry (see `docs/design/piecewise-noding.md`).
"""

from time import perf_counter
from typing import Optional

from geoalchemy2.shape import from_shape
from macrostrat.utils import get_logger
from psycopg.sql import SQL
from rich.progress import Progress

from ..config import TopologyContext
from ..database import sql
from ..utilities import console
from .edge_relations import rebuild_dirty_edge_relations

count = sql("procedures/count-contact")
get_contacts = sql("procedures/get-contacts-to-update")
reset_errors = sql("procedures/reset-linework-errors")
record_failure = sql("procedures/linework-failures")
update_contact = sql("procedures/update-contact")
# The bind parameter is `noding_tolerance`, not `tolerance`: the database merges the
# context's instance parameters over a call's, and `tolerance` is the topology
# precision there.
update_piece = sql("procedures/update-boundary-piece")
contacts_with_errors = sql("procedures/get-contacts-with-errors")

log = get_logger(__name__)

# A row filter that selects nothing extra: the default.
ALL_ROWS = "true"


def selection_params(
    row_filter: Optional[str] = None,
    filter_params: Optional[dict] = None,
    *,
    include_failed: bool = False,
) -> dict:
    """Template and bind parameters for the row-selecting procedures.

    `row_filter` is a SQL boolean expression over the boundary table aliased `l`
    (e.g. ``"l.map_layer = :layer"`` or ``"l.id = ANY(:ids)"``), with its bind
    values in `filter_params`. It is spliced into the query, so it must come from
    the caller, never from user input. `include_failed` also selects rows that
    carry a `topology_error`.
    """
    params = dict(filter_params or {})
    params["row_filter"] = SQL(row_filter or ALL_ROWS)
    params["include_failed"] = SQL("true" if include_failed else "false")
    return params


def update_contacts(
    ctx: TopologyContext,
    fix_failed: bool = False,
    *,
    tolerance: Optional[float] = None,
    row_filter: Optional[str] = None,
    filter_params: Optional[dict] = None,
    include_failed: bool = False,
) -> int:
    """Node every pending boundary row whole, returning the number of rows processed.

    A row is pending when `geometry_hash IS NULL` and it is in a topological
    layer. Rows with a `topology_error` are skipped unless `include_failed` selects
    them (their error is replaced by the new outcome) or `fix_failed` clears their
    errors first. `row_filter` narrows the selection (see `selection_params`).
    `tolerance` is the snapping tolerance passed to `toTopoGeom`; None means the
    topology's precision. Each row is attempted exactly once per call.
    """
    db = ctx.database
    selection = selection_params(
        row_filter, filter_params, include_failed=include_failed or fix_failed
    )

    if fix_failed:
        db.run_sql(reset_errors, selection)

    ids = list(db.run_query(get_contacts, selection).scalars())
    if len(ids) == 0:
        console.print("No boundaries to update")
        return 0

    total_updated = 0
    with Progress() as progress:
        bar = progress.add_task("Updating lines", total=len(ids))
        batch_size = 1
        position = 0
        while position < len(ids):
            batch = ids[position : position + batch_size]
            position += len(batch)

            t0 = perf_counter()
            rows = db.run_query(
                update_contact, {"ids": batch, "noding_tolerance": tolerance}
            ).all()
            for row in rows:
                if row.err is not None:
                    progress.console.print(
                        f"[dim]{row.id}[/dim]: [error]{row.err}[/error]"
                    )
                    db.run_sql(record_failure, {"id": row.id, "error": row.err})
            db.session.commit()
            t1 = perf_counter()
            nrows = len(rows)
            progress.update(bar, advance=nrows)
            total_updated += nrows
            duration = t1 - t0
            log.info("Updated %s lines in %.2f seconds", nrows, duration)
            # Dynamically adjust batch size
            if duration < 1:
                batch_size = min(1000, batch_size * 10)
                progress.console.print(f"Batch size: {batch_size}")
                log.info("Speeding up, using batch size %s", batch_size)
            elif duration > 5:
                batch_size = max(1, batch_size // 10)
                progress.console.print(f"Batch size: {batch_size}")
                log.info("Slowing down, using batch size %s", batch_size)

    # Face-based boundaries defer their edge-relation cache maintenance
    rebuild_dirty_edge_relations(ctx)
    return total_updated


def failed_boundaries(
    ctx: TopologyContext,
    row_filter: Optional[str] = None,
    filter_params: Optional[dict] = None,
) -> list:
    """Boundary rows in topological layers with a recorded `topology_error`, as
    `(id, topology_error)` rows -- the set `update_contacts(include_failed=True)`
    or `fix_failed=True` retries."""
    return ctx.database.run_query(
        contacts_with_errors, selection_params(row_filter, filter_params)
    ).all()


def prepare_piece(piece, srid: int) -> str:
    """A piece as PostGIS geometry text: EWKT / hex EWKB strings pass through,
    shapely geometries are encoded with the topology's SRID."""
    if isinstance(piece, str):
        return piece
    return str(from_shape(piece, srid=srid, extended=True))


def update_boundary_piece(
    ctx: TopologyContext,
    row_id: int,
    piece,
    tolerance: Optional[float] = None,
) -> Optional[str]:
    """Node one piece of a boundary row's geometry into its topogeometry.

    The first piece creates the row's topogeometry; later pieces accumulate into
    it under the same id. Returns the noding error text, or None on success. On
    failure the row is unchanged and nothing is recorded on it -- the host keeps
    per-piece records and decides whether to simplify, subdivide or retry at
    another `tolerance` (None: the topology's precision). The host sets
    `geometry_hash` when it considers the row complete
    (``UPDATE ... SET geometry_hash = <topo_schema>.hash_geometry(geometry)``).

    Every call commits: an interrupted run leaves the pieces noded so far and the
    faces they touched queued in `dirty_face`, and the next `update_faces` resumes
    from there. The `__edge_relation` cache of a face-based boundary is refreshed
    lazily, by `update_faces` (or `rebuild_dirty_edge_relations`), not per piece.
    """
    db = ctx.database
    row = db.run_query(
        update_piece,
        {
            "id": row_id,
            "piece": prepare_piece(piece, ctx.srid),
            "noding_tolerance": tolerance,
        },
    ).one_or_none()
    db.session.commit()
    if row is None:
        raise ValueError(f"No boundary row with id {row_id}")
    return row.err
