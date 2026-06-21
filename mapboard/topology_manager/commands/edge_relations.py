"""Validate and repair the cached ``__edge_relation`` table.

``__edge_relation`` is a trigger-maintained cache of the authoritative
``__edge_relation_dynamic`` view. If the triggers ever fall out of sync (e.g. a
bulk load with triggers disabled, or a topology edit that bypassed them), these
helpers report the drift and rebuild the cache from scratch.
"""

from dataclasses import dataclass

from macrostrat.utils import get_logger

from ..config import TopologyContext
from ..database import sql
from ..utilities import console

log = get_logger(__name__)

# Rows present in the authoritative view but missing from the cache.
_missing_query = """
SELECT count(*)
FROM {topo_schema}.__edge_relation_dynamic d
LEFT JOIN {topo_schema}.__edge_relation er
  ON er.line_id = d.line_id AND er.edge_id = d.edge_id
WHERE er.line_id IS NULL
"""

# Cached rows that are no longer in the authoritative view.
_extra_query = """
SELECT count(*)
FROM {topo_schema}.__edge_relation er
LEFT JOIN {topo_schema}.__edge_relation_dynamic d
  ON d.line_id = er.line_id AND d.edge_id = er.edge_id
WHERE d.line_id IS NULL
"""


@dataclass
class EdgeRelationReport:
    """Drift between the cached ``__edge_relation`` table and its authoritative view."""

    missing: int  # rows in the view absent from the cache
    extra: int  # cached rows absent from the view

    @property
    def in_sync(self) -> bool:
        return self.missing == 0 and self.extra == 0


def validate_edge_relations(ctx: TopologyContext) -> EdgeRelationReport:
    """Compare the cached ``__edge_relation`` table against its authoritative view,
    without modifying anything."""
    db = ctx.database
    return EdgeRelationReport(
        missing=db.run_query(_missing_query).scalar(),
        extra=db.run_query(_extra_query).scalar(),
    )


def rebuild_edge_relations(ctx: TopologyContext) -> EdgeRelationReport:
    """Rebuild the cached ``__edge_relation`` table from scratch.

    Returns the drift that was present *before* the rebuild, so callers can tell
    whether the cache had actually fallen out of sync.
    """
    db = ctx.database
    report = validate_edge_relations(ctx)
    if report.in_sync:
        log.info("Edge relations already in sync; rebuilding anyway")
    else:
        log.warning(
            "Edge relations out of sync (missing=%s, extra=%s); rebuilding",
            report.missing,
            report.extra,
        )
    db.run_sql(sql("procedures/rebuild-edge-relations"), raise_errors=True)
    db.session.commit()
    console.print(
        f"Rebuilt edge relations (was out of sync by "
        f"{report.missing + report.extra} rows)"
    )
    return report
