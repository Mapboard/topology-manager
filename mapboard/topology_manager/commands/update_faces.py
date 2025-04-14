import os
from threading import Timer

from rich.progress import Progress
from typer import Option
from time import perf_counter
from macrostrat.database import Database
from macrostrat.utils.timer import Timer
from macrostrat.utils import get_logger
from enum import Enum

from ..database import get_database, sql
from ..utilities import console
from ..update_faces import update_map_face_python

count_ = "SELECT count(*)::integer nfaces FROM {topo_schema}.__dirty_face"

log = get_logger(__name__)


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

    t0 = perf_counter()
    if reset:
        db.run_sql(sql("procedures/reset-map_face"))

    if fill_holes:
        db.run_sql(sql("procedures/set-holes-as-dirty"))

    db.run_sql(sql("procedures/prepare-update-face"))

    nfaces = db.run_query(count_).scalar()

    if nfaces == 0:
        console.print("No faces to update")

    Timer.add_step("prepare-update-face")
    t1 = perf_counter()

    console.print(f"Prepared to update {nfaces} faces in {t1 - t0:.2f} seconds")

    t0 = perf_counter()

    # with Progress() as progress:
    #    bar = progress.add_task("Updating faces", total=nfaces)
    niter = 0
    while nfaces > 0:
        if engine == Engine.PLPGSQL:
            update_map_face_plpgsql(db)
        else:
            update_map_face_python(db)
        next_count = db.run_query(count_).scalar()
        # progress.update(bar, completed=nfaces - next_count)
        nfaces = next_count
        niter += 1
        log.info(f"Updated {nfaces} faces")

    log.info(f"Updated {niter} times")

    t1 = perf_counter()
    log.info(f"Updated {nfaces} faces in {t1 - t0:.2f} seconds")


def update_map_face_plpgsql(db: Database):
    try:
        db.run_query("SELECT {topo_schema}.update_map_face()").one()
    except Exception as e:
        console.print(f"Error updating faces: {e}", style="error")
