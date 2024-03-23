from rich.progress import Progress
from typer import Option

from ..database import get_database, sql
from ..utilities import console

count_ = "SELECT count(*)::integer nfaces FROM ${topo_schema~}.__dirty_face"
update_face_ = "SELECT ${topo_schema~}.update_map_face()"


def update_faces(
    reset: bool = Option(False, help="Rebuild from scratch"),
    fill_holes: bool = Option(False, help="Try to fill all holes"),
):
    """Update faces"""
    db = get_database()

    if reset:
        db.run_sql(sql("procedures/reset-map_face"))

    if fill_holes:
        db.run_sql(sql("procedures/set-holes-as-dirty"))

    db.run_sql(sql("procedures/prepare-update-face"))

    nfaces = db.run_query(count_).scalar()

    if nfaces == 0:
        console.print("No faces to update")

    with Progress() as progress:
        bar = progress.add_task("Updating faces", total=nfaces)
        while nfaces > 0:
            db.run_query(update_face_).one()
            next_count = db.run_query(count_).scalar()
            bar.update(completed=nfaces - next_count)
