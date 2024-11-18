from rich.progress import Progress
from typer import Option
from time import perf_counter

from ..database import get_database, sql
from ..utilities import console

count_ = "SELECT count(*)::integer nfaces FROM {topo_schema}.__dirty_face"


def update_faces(
    reset: bool = Option(False, help="Rebuild from scratch"),
    fill_holes: bool = Option(False, help="Try to fill all holes"),
):
    """Update faces"""
    db = get_database()
    _update_faces(db, reset, fill_holes)


def _update_faces(db, reset: bool = False, fill_holes: bool = False):
    t0 = perf_counter()
    if reset:
        db.run_sql(sql("procedures/reset-map_face"))

    if fill_holes:
        db.run_sql(sql("procedures/set-holes-as-dirty"))

    db.run_sql(sql("procedures/prepare-update-face"))

    nfaces = db.run_query(count_).scalar()

    if nfaces == 0:
        console.print("No faces to update")

    t1 = perf_counter()

    console.print(f"Prepared to update {nfaces} faces in {t1 - t0:.2f} seconds")

    t0 = perf_counter()

    with Progress() as progress:
        bar = progress.add_task("Updating faces", total=nfaces)
        while nfaces > 0:
            try:
                db.run_query("SELECT {topo_schema}.update_map_face()").one()
            except Exception as e:
                console.print(f"Error updating faces: {e}", style="error")
            next_count = db.run_query(count_).scalar()
            progress.update(bar, completed=nfaces - next_count)
            nfaces = next_count

    t1 = perf_counter()
    console.print(f"Updated {nfaces} faces in {t1 - t0:.2f} seconds")
