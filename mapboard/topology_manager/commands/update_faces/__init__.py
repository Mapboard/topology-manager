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
    dissolve_layer_groups,
    log,
    persist_map_face_updates,
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
    incremental: bool = Option(True, help="Incremental update"),
    persist_interval: int = 100,
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
    map_layers = set(d.map_layer for d in dirty_faces)
    print(f"{init_n_faces} dirty faces to update, across {len(map_layers)} layers")
    ix = get_dirty_faces_layer_index(dirty_faces)
    log.info(
        "Dirty faces in layers: %s",
        ", ".join(f"{k}: {v}" for k, v in ix.items() if v > 0),
    )

    # Dissolve is driven layer by layer, in batches: the database walks each
    # component and returns a batch of them in one round trip, then the batch is
    # persisted -- which unmarks its faces, so the next call sees a smaller dirty
    # set. `persist_interval` is the batch size. Previously this loop made one
    # round trip per dirty face, which left the database idle waiting on the
    # client for roughly a third of a bulk update.
    niter = 0
    # `incremental` still means "checkpoint as you go": it is the batch size that
    # provides it now, so a non-incremental run simply takes every group at once.
    batch_size = persist_interval if incremental else None
    with Progress() as progress:
        bar = progress.add_task("Updating faces", total=init_n_faces)
        for map_layer in sorted(map_layers):
            remaining = n_dirty_faces(db, map_layer)
            while remaining > 0:
                results = dissolve_layer_groups(db, map_layer, max_groups=batch_size)
                if not results:
                    break
                persist_map_face_updates(db, results)
                niter += len(results)

                prev, remaining = remaining, n_dirty_faces(db, map_layer)
                progress.update(
                    bar, completed=max(0, init_n_faces - n_dirty_faces(db))
                )
                # A group that dissolves nothing leaves its faces marked, so
                # without this the layer would loop forever.
                if remaining >= prev:
                    log.warning(
                        "No progress on %d dirty faces in layer %s; moving on",
                        remaining,
                        map_layer,
                    )
                    break

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
