"""Resolve dirty topology primitives into `map_face` polygons.

The package is organised around the loop's three concerns:

- `dissolve`  — compute the joinable component around a seed (server-side).
- `persist`   — settle a component onto map faces (`move` or `replace` mode),
                built on the primitive CRUD in `store`.
- `loop`      — the queue that drains `dirty_face`, feeding shed remainders back
                in so faces are split and holes are filled. `FaceUpdateLoop`
                runs it from Python; `ServerSideFaceUpdateLoop` runs whole
                chunks in PL/pgSQL (`update_dirty_faces`, `--engine plpgsql`).

`helpers` re-exports the historical names for compatibility.
"""

import os
import warnings
from collections import defaultdict
from enum import Enum
from time import perf_counter
from typing import Optional

from macrostrat.database import Database
from macrostrat.utils.timer import Timer
from typer import Argument, Option
from typer.models import OptionInfo

from ...config import FaceUpdateMode, TopologyContext, get_context, sql
from ..edge_relations import rebuild_dirty_edge_relations
from .dissolve import dissolve_component, get_adjacent_faces, log, update_map_face
from .loop import FaceUpdateLoop, ServerSideFaceUpdateLoop
from .models import (
    DirtyFace,
    FaceOverlap,
    FaceUpdateResult,
    FaceUpdateStats,
    MapFaceChange,
)
from .persist import (
    FacePersister,
    MoveFacesPersister,
    ReplaceFacesPersister,
    get_persister,
    persist_map_face_updates,
)
from .store import MapFaceStore

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
    engine: Optional[Engine] = Option(
        None,
        help="Where the loop runs: 'python' (one round trip per step) or "
        "'plpgsql' (whole chunks server-side; defaults to TOPO_ENGINE / python)",
        envvar="TOPO_ENGINE",
    ),
    incremental: bool = Option(True, help="Incremental update"),
    persist_interval: int = 100,
    face_update_mode: Optional[FaceUpdateMode] = Option(
        None,
        help="How to persist faces: 'move' (update an existing topogeometry in "
        "place) or 'replace' overlapping faces (defaults to the context setting)",
        envvar="MAPBOARD_FACE_UPDATE_MODE",
    ),
) -> FaceUpdateStats:
    """Update faces"""
    # Called directly (not through the CLI) the typer defaults arrive as
    # OptionInfo objects; resolve them so e.g. `reset` is not truthy.
    reset, fill_holes, engine, incremental, persist_interval, face_update_mode = (
        _resolve_default(v)
        for v in (
            reset,
            fill_holes,
            engine,
            incremental,
            persist_interval,
            face_update_mode,
        )
    )
    engine = Engine(engine or os.environ.get("TOPO_ENGINE", Engine.PYTHON))
    log.info("Updating faces with engine %s", engine.value)

    db = ctx.database
    mode = FaceUpdateMode(face_update_mode or ctx.face_update_mode)

    if fill_holes:
        warnings.warn("The 'fill_holes' option has been removed", DeprecationWarning)

    t0 = perf_counter()
    if reset:
        db.run_sql(sql("procedures/reset-map-face"))

    Timer.add_step("prepare-update-face")
    t1 = perf_counter()
    log.info(f"Prepared to update faces in {t1 - t0:.2f} seconds")

    # Face-based boundaries queue their edge-relation cache updates; drain them
    # so the joinable graph sees every barrier (no-op when nothing is pending).
    rebuild_dirty_edge_relations(ctx)

    store = MapFaceStore(db)
    dirty_faces = store.dirty_faces()
    ix = get_dirty_faces_layer_index(dirty_faces)
    print(
        f"{len(dirty_faces)} dirty faces to update, across {len(ix)} layers "
        f"({mode.value} mode, {engine.value} engine)"
    )
    log.info(
        "Dirty faces in layers: %s",
        ", ".join(f"{k}: {v}" for k, v in ix.items() if v > 0),
    )

    loop_class = (
        ServerSideFaceUpdateLoop if engine == Engine.PLPGSQL else FaceUpdateLoop
    )
    loop = loop_class(
        db,
        get_persister(db, mode),
        batch_size=persist_interval if incremental else None,
    )
    stats = loop.run(dirty_faces)

    db.run_sql(sql("procedures/update-faces/post-update-faces"))
    return stats


def _resolve_default(value):
    """Unwrap a typer ``Option(...)`` default when the command is called as a function."""
    if isinstance(value, OptionInfo):
        return value.default
    return value


def _update_faces(*args, **kwargs):
    warnings.warn(
        "The 'update_faces' function has been deprecated. "
        "Use the 'topology_manager.commands.update_faces.update_faces' command instead.",
        DeprecationWarning,
    )
    update_faces(*args, **kwargs)


def get_dirty_faces_layer_index(dirty_faces: list) -> dict[int, int]:
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


__all__ = [
    "update_faces",
    "n_dirty_faces",
    "get_n_dirty_faces",
    "Engine",
    "FaceUpdateMode",
    "FaceUpdateLoop",
    "ServerSideFaceUpdateLoop",
    "FaceUpdateStats",
    "FaceUpdateResult",
    "FaceOverlap",
    "MapFaceChange",
    "MapFaceStore",
    "FacePersister",
    "MoveFacesPersister",
    "ReplaceFacesPersister",
    "get_persister",
    "persist_map_face_updates",
    "dissolve_component",
    "get_adjacent_faces",
    "update_map_face",
    "DirtyFace",
]
