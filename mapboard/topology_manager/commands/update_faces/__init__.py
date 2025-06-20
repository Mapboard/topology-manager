import warnings
from threading import Timer

from black.trans import defaultdict
from typer import Option
from time import perf_counter
from macrostrat.database import Database
from macrostrat.utils.timer import Timer
from macrostrat.utils import get_logger
from enum import Enum
from typing import Optional

from ...database import get_database, sql
from .helpers import (
    update_map_face_python,
    persist_map_face_updates,
    persist_map_face_updates_simple,
)

count_ = "SELECT count(*)::integer nfaces FROM {topo_schema}.__dirty_face"

log = get_logger("mapboard.topology_manager.update_faces")


def n_dirty_faces(db: Database, map_layer: Optional[int] = None) -> int:
    """Get the number of dirty faces in a layer"""
    sql = "SELECT count(*)::integer nfaces FROM {topo_schema}.__dirty_face"
    params = {}
    if map_layer is not None:
        sql = sql + " WHERE map_layer = :layer"
        params["layer"] = map_layer
    return db.run_query(sql, params).scalar()


class Engine(str, Enum):
    PYTHON = "python"
    PLPGSQL = "plpgsql"


def update_faces(
    reset: bool = Option(False, help="Rebuild from scratch"),
    fill_holes: bool = Option(False, help="Try to fill all holes"),
    engine: Engine = Option(
        Engine.PYTHON,
        help="Use Python or PL/pgSQL (not yet implemented)",
        envvar="TOPO_ENGINE",
    ),
):
    """Update faces"""
    db = get_database()
    _update_faces(
        db,
        reset=reset,
        fill_holes=fill_holes,
        engine=engine,
    )


def _update_faces(
    db,
    *,
    reset: bool = False,
    fill_holes: bool = False,
    engine: Engine = Engine.PYTHON,
    incremental: bool = False,
):
    log.info("Updating faces with engine %s", engine)

    if fill_holes:
        warnings.warn("The 'fill_holes' option has been removed", DeprecationWarning)

    t0 = perf_counter()
    if reset:
        db.run_sql(sql("procedures/reset-map-face"))

    Timer.add_step("prepare-update-face")
    t1 = perf_counter()

    log.info(f"Prepared to update faces in {t1 - t0:.2f} seconds")

    t0 = perf_counter()
    niter = 0

    dirty_faces = db.run_query(
        "SELECT id, map_layer FROM {topo_schema}.__dirty_face"
    ).all()
    init_n_faces = len(dirty_faces)
    ix = get_dirty_faces_layer_index(dirty_faces)
    log.info(
        "Dirty faces in layers: %s",
        ", ".join(f"{k}: {v}" for k, v in ix.items() if v > 0),
    )
    results = []
    while len(dirty_faces) > 0:
        log.info(
            "%s dirty faces remaining",
            len(dirty_faces),
        )
        # Extract one face
        face = dirty_faces.pop(0)

        res = update_map_face_python(db, face, write=incremental)
        results.append(res)

        # Filter dirty faces to remove the ones that have been dissolved into the current face
        dirty_faces = [
            d
            for d in dirty_faces
            if not (d.id in res.dissolved_faces and d.map_layer == res.map_layer)
        ]
        niter += 1

    ## Delete old topogeoms
    if not incremental:
        persist_map_face_updates(db, results)

    t1 = perf_counter()
    log.info(
        f"Updated {init_n_faces} faces in {t1 - t0:.2f} seconds ({niter} iterations)"
    )

    db.run_sql(sql("procedures/update-faces/post-update-faces"))


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
