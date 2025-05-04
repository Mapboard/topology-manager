import os
from threading import Timer

from typer import Option
from time import perf_counter
from macrostrat.database import Database
from macrostrat.utils.timer import Timer
from macrostrat.utils import get_logger
from enum import Enum
from typing import Optional

from ..database import get_database, sql
from ..utilities import console
from ..update_faces import update_map_face_python

count_ = "SELECT count(*)::integer nfaces FROM {topo_schema}.__dirty_face"

log = get_logger(__name__)


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
        Engine.PLPGSQL, help="Use Python or PL/pgSQL", envvar="TOPO_ENGINE"
    ),
):
    """Update faces"""
    db = get_database()
    _update_faces(db, reset=reset, fill_holes=fill_holes, engine=engine)


def _update_faces(
    db,
    *,
    reset: bool = False,
    fill_holes: bool = False,
    engine: Engine = Engine.PYTHON,
):
    # Load the engine from the environment if it's defined there.
    # This is mostly used in order to make sure that the tests run with the same engine
    # as the CLI commands. Eventually we should test with both engines at once.
    engine = os.environ.get("TOPO_ENGINE", engine)
    # Hard-code the Python engine for now
    engine = Engine.PYTHON

    log.info("Updating faces with engine %s", engine)

    t0 = perf_counter()
    if reset:
        db.run_sql(sql("procedures/reset-map-face"))

    if fill_holes:
        db.run_sql(sql("procedures/set-holes-as-dirty"))

    db.run_sql(sql("procedures/update-faces/01-prepare-update-faces"))

    Timer.add_step("prepare-update-face")
    t1 = perf_counter()

    log.info(f"Prepared to update faces in {t1 - t0:.2f} seconds")

    t0 = perf_counter()
    niter = 0
    init_n_faces = n_dirty_faces(db)
    n_faces = init_n_faces
    while n_faces > 0:
        log.info("%s dirty faces remaining", n_faces)
        # Extract one face
        face = db.run_query("SELECT id, map_layer FROM {topo_schema}.__dirty_face LIMIT 1", ).one()

        update_map_face_python(db, face)
        n_faces = n_dirty_faces(db)
        niter += 1

    t1 = perf_counter()
    log.info(f"Updated {init_n_faces} faces in {t1 - t0:.2f} seconds ({niter} iterations)")

    db.run_sql(sql("procedures/update-faces/02-post-update-faces"))


def update_map_face_plpgsql(db: Database):
    try:
        db.run_query("SELECT {topo_schema}.update_map_face()").one()
    except Exception as e:
        console.print(f"Error updating faces: {e}", style="error")


def get_n_dirty_faces(db: Database) -> int:
    """Get the number of dirty faces"""
    result = db.run_query(count_).scalar()
    if result is None:
        return 0
    return result
