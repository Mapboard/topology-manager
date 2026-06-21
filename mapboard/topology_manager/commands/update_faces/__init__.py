import warnings
from threading import Timer

from collections import defaultdict
from typer import Option, Argument
from time import perf_counter
from macrostrat.database import Database
from macrostrat.utils.timer import Timer
from enum import Enum
from typing import Optional
from rich.progress import Progress

from ...config import TopologyContext, sql, get_context
from .helpers import (
    persist_map_face_updates,
    persist_map_face_updates_simple,
    dissolve_dirty_faces,
    log,
)

count_ = "SELECT count(*)::integer nfaces FROM {topo_schema}.dirty_face"


def n_dirty_faces(db: Database, map_layer: Optional[int] = None) -> int:
    """Get the number of dirty faces in a layer"""
    sql = "SELECT count(*)::integer nfaces FROM {topo_schema}.dirty_face"
    params = {}
    if map_layer is not None:
        sql = sql + " WHERE map_layer = :layer"
        params["layer"] = map_layer
    return db.run_query(sql, params).scalar()


class Engine(str, Enum):
    PYTHON = "python"
    PLPGSQL = "plpgsql"


def update_faces(
    ctx: TopologyContext = Argument(callback=get_context, help="Database connection"),
    *,
    reset: bool = Option(False, help="Rebuild from scratch"),
    fill_holes: bool = Option(False, help="Try to fill all holes"),
    engine: Engine = Option(
        Engine.PYTHON,
        help="Use Python or PL/pgSQL (not yet implemented)",
        envvar="TOPO_ENGINE",
    ),
    composite_layers: bool = Option(False, help="Update composite layers"),
    incremental: bool = Option(False, help="Incremental update of faces, vs. batch"),
):
    """Update faces"""
    log.info("Updating faces with engine %s", engine)

    db = ctx.database

    if fill_holes:
        warnings.warn("The 'fill_holes' option has been removed", DeprecationWarning)

    t0 = perf_counter()
    if reset:
        db.run_sql(sql("procedures/reset-map-face"))

    Timer.add_step("prepare-update-face")
    t1 = perf_counter()

    log.info(f"Prepared to update faces in {t1 - t0:.2f} seconds")

    t0 = perf_counter()

    dirty_faces = db.run_query(
        "SELECT id, map_layer FROM {topo_schema}.dirty_face"
    ).all()
    init_n_faces = len(dirty_faces)
    print(f"{init_n_faces} dirty faces to update")
    ix = get_dirty_faces_layer_index(dirty_faces)
    log.info(
        "Dirty faces in layers: %s",
        ", ".join(f"{k}: {v}" for k, v in ix.items() if v > 0),
    )

    # Dissolve groups are computed server-side over a graph that is static for the
    # whole run (writes are deferred), so we compute them once up front.
    results = dissolve_dirty_faces(db, dirty_faces)
    niter = len(results)

    if incremental:
        # Checkpoint: persist and commit one group at a time, so an interrupted run
        # keeps the groups already written (and their dirty faces stay unmarked).
        # Safe because persisting a map face does not change the dissolve graph.
        with Progress() as progress:
            bar = progress.add_task("Persisting map faces", total=len(results))
            for res in results:
                persist_map_face_updates_simple(db, [res])
                db.session.commit()
                progress.update(bar, advance=1)
    else:
        # Persist everything in one batch, then commit once. Fastest, but an
        # interruption loses the whole run's face calculations.
        persist_map_face_updates(db, results)

    t1 = perf_counter()
    log.info(
        f"Updated {init_n_faces} faces in {t1 - t0:.2f} seconds ({niter} iterations)"
    )

    db.run_sql(sql("procedures/update-faces/post-update-faces"))


def _update_faces(*args, **kwargs):
    warnings.warn(
        "The 'update_faces' function has been deprecated. "
        "Use the 'topology_manager.commands.update_faces.update_faces' command instead.",
        DeprecationWarning,
    )
    update_faces(*args, **kwargs)


def get_dirty_faces_layer_index(dirty_faces: list[dict]) -> dict[int, int]:
    face_ix = defaultdict(int)
    for face in dirty_faces:
        face_ix[face.map_layer] += 1

    return face_ix


def get_n_dirty_faces(db: Database) -> int:
    """Get the number of dirty faces"""
    result = db.run_query(count_).scalar()
    if result is None:
        return 0
    return result
