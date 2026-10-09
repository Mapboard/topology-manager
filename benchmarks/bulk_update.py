"""Bulk-update benchmark for the face-update loop.

The scenario is the one that hurts in production and that a small "flip one
corner" test never exercises: a layer already holds *large* map faces, and a
bulk change dirties a set of primitives that does **not** cover those faces.

    base topology
      layer "medium": an N x N grid of small map areas (the primitives)
      layer "large":  four quadrant maps covering the grid -> four faces of
                      N*N/4 primitives each
    bulk update
      K new higher-priority maps are added to layer "large", scattered over the
      grid; update_contacts marks the primitives they touch dirty (a few hundred
      of the N*N), then `update_faces` is timed.

Each mode x engine cell runs against a fresh copy of the same base (a template
database), so cells are comparable and the benchmark is repeatable. Reported per
cell: wall time of `update_faces`, components persisted, faces created / updated
/ deleted, primitives re-marked, and afterwards the number of identified
primitives without a face ("holes") and of orphaned relation rows.

    export TOPO_TESTING_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/mapboard_topology_bench
    uv run python benchmarks/bulk_update.py            # N=40, K=24
    BENCH_GRID=60 BENCH_MAPS=50 uv run python benchmarks/bulk_update.py
    BENCH_CELLS="replace/python,move/plpgsql" uv run python benchmarks/bulk_update.py
"""

import builtins
import logging
import os
import sys
from pathlib import Path
from time import perf_counter

from macrostrat.database import Database
from macrostrat.database.utils import create_database, drop_database
from sqlalchemy.engine import make_url

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from mapboard.topology_manager import TopologyInspector, create_context  # noqa: E402
from mapboard.topology_manager.commands import (  # noqa: E402
    clean_topology,
    create_tables,
    update_contacts,
)
from mapboard.topology_manager.commands.update_faces import update_faces  # noqa: E402
from mapboard.topology_manager.commands.update_topology import update  # noqa: E402
from mapboard.topology_manager.config import (  # noqa: E402
    FaceUpdateEngine,
    FaceUpdateMode,
)
from tests.map_areas.support import (  # noqa: E402
    DATA_SCHEMA,
    DIRECT_STRATEGY,
    TOPO_SCHEMA,
    add_map,
    create_data_tables,
)

N = int(os.environ.get("BENCH_GRID", "40"))
K = int(os.environ.get("BENCH_MAPS", "24"))
CELLS = [
    tuple(c.split("/"))
    for c in os.environ.get(
        "BENCH_CELLS", "replace/python,replace/plpgsql,move/python,move/plpgsql"
    ).split(",")
]
SIZE = 100.0
CELL = SIZE / N

# Silence the pipeline's console output; the benchmark prints its own table.
logging.disable(logging.CRITICAL)
_print = builtins.print
builtins.print = lambda *a, **k: None
from mapboard.topology_manager import utilities  # noqa: E402

utilities.console.quiet = True


def make_context(db, **kwargs):
    return create_context(
        db,
        data_schema=DATA_SCHEMA,
        topo_schema=TOPO_SCHEMA,
        srid=4326,
        tolerance=0.0001,
        identity_strategy=DIRECT_STRATEGY,
        boundary_table="map_area",
        create_data_tables=create_data_tables,
        notify_triggers=False,
        **kwargs,
    )


def build_base(url):
    """The base topology: grid + four big faces, fully solved."""
    create_database(url, exists_ok=True, replace=True)
    db = Database(url)
    ctx = make_context(db)
    create_tables(ctx)
    d = ctx.database
    t0 = perf_counter()
    for i in range(N):
        for j in range(N):
            add_map(
                d,
                f"ST_MakeEnvelope({i*CELL}, {j*CELL}, {(i+1)*CELL}, {(j+1)*CELL})",
                "medium",
            )
    half = SIZE / 2
    for x0 in (0, half):
        for y0 in (0, half):
            add_map(
                d,
                f"ST_MakeEnvelope({x0}, {y0}, {x0+half}, {y0+half})",
                "large",
                priority=0,
            )
    update(ctx, composite_layers=False)
    insp = TopologyInspector(ctx)
    layer = insp.map_layer_id("Large")
    _print(
        f"base: {insp.n_face_primitives()} primitives, "
        f"{insp.n_faces(map_layer=layer)} faces in 'large', built in {perf_counter()-t0:.0f} s"
    )
    d.session.close()
    d.engine.dispose()


def run_cell(url, mode, engine):
    db = Database(url)
    ctx = make_context(db, face_update_mode=mode, face_update_engine=engine)
    d = ctx.database
    insp = TopologyInspector(ctx)
    layer = insp.map_layer_id("Large")
    faces_before = insp.n_faces(map_layer=layer)

    # The bulk change: K small, higher-priority maps scattered over the grid,
    # each 1.5 cells wide so it cuts primitives rather than aligning with them.
    step = SIZE / (K + 1)
    for k in range(1, K + 1):
        x = k * step
        y = ((k * 37) % (K + 1)) * step  # spread over both axes, deterministic
        add_map(
            d,
            f"ST_MakeEnvelope({x}, {y}, {x + 1.5*CELL}, {y + 1.5*CELL})",
            "large",
            priority=-1,
        )
    update_contacts(ctx)
    clean_topology(ctx)
    dirty_before = d.run_query(
        "SELECT count(*) FROM {topo_schema}.dirty_face WHERE map_layer = :l",
        dict(l=layer),
    ).scalar()

    t0 = perf_counter()
    stats = update_faces(ctx, face_update_mode=mode, engine=engine, incremental=True)
    elapsed = perf_counter() - t0

    clean_topology(ctx)  # what `update()` does after faces: reclaims orphans
    holes = len(insp.unfaced_primitives(layer))
    orphans = insp.orphaned_relations()
    faces_after = insp.n_faces(map_layer=layer)
    d.session.close()
    d.engine.dispose()
    return dict(
        mode=mode,
        engine=engine,
        dirty=dirty_before,
        seconds=elapsed,
        components=stats.components,
        created=stats.created,
        updated=stats.updated,
        deleted=stats.deleted,
        reseeded=stats.reseeded,
        faces=f"{faces_before}->{faces_after}",
        holes=holes,
        orphans=orphans,
    )


def main():
    base_url = make_url(os.environ["TOPO_TESTING_DATABASE_URL"])
    template = base_url.database + "_bulkbase"
    template_url = base_url.set(database=template)
    run_url = base_url.set(database=base_url.database + "_bulkrun")

    _print(f"== bulk update: {N}x{N} grid, 4 large faces, {K} new maps")
    build_base(template_url)

    rows = []
    for mode, engine in CELLS:
        drop_database(run_url, allow_missing=True)
        create_database(run_url, template=template)
        # Database-level settings are not copied with a template; the topology
        # extension puts its schema on the search_path that way.
        Database(run_url).run_sql(
            f'ALTER DATABASE "{run_url.database}" SET search_path = "$user", public, topology'
        )
        rows.append(run_cell(run_url, FaceUpdateMode(mode), FaceUpdateEngine(engine)))
        r = rows[-1]
        _print(
            f"  {r['mode'].value:7} {r['engine'].value:7} dirty={r['dirty']:<6} "
            f"{r['seconds']:7.2f} s  components={r['components']:<5} "
            f"created={r['created']:<4} updated={r['updated']:<4} deleted={r['deleted']:<4} "
            f"reseeded={r['reseeded']:<5} faces {r['faces']:<9} holes={r['holes']} orphans={r['orphans']}"
        )
    drop_database(run_url, allow_missing=True)


if __name__ == "__main__":
    main()
