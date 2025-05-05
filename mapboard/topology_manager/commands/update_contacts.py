from time import perf_counter

from rich.progress import Progress

from ..database import Database, get_database, sql
from ..utilities import console
from .clean_topology import _clean_topology
from macrostrat.utils import get_logger

count = sql("procedures/count-contact")
get_contacts = sql("procedures/get-contacts-to-update")
reset_errors = sql("procedures/reset-linework-errors")

log = get_logger(__name__)


def update_contacts(fix_failed: bool = False):
    """Update contacts"""
    db = get_database()
    _update_contacts(db, fix_failed)


def _update_contacts(db: Database, fix_failed: bool = False):
    nlines = db.run_query(count).scalar()

    if fix_failed:
        db.run_sql(reset_errors)

    if nlines == 0:
        console.print("No contacts to update")

    res = db.run_query(get_contacts).all()
    remaining = len(res)
    if remaining == 0:
        return

    with Progress() as progress:
        bar = progress.add_task("Updating lines", total=nlines)
        nops = 0
        batch_size = 1
        while remaining > 0:
            if nops % 100 == 0:
                _clean_topology(db)

            t0 = perf_counter()
            rows = db.run_query(sql("procedures/update-contact"), {"n": batch_size}).all()
            db.session.commit()
            t1 = perf_counter()
            nrows = len(rows)
            for row in rows:
                if row.err is not None:
                    console.print(f"[dim]{row.id}[/dim]: [error]{row.err}[/error]")
            progress.update(bar, advance=nrows)
            remaining -= nrows
            duration = t1 - t0
            log.info("Updated %s lines in %.2f seconds", nrows, duration)
            # Dynamically adjust batch size
            # if duration < 1:
            #     batch_size = min(1000, batch_size * 10)
            #     log.info("Speeding up, using batch size %s", batch_size)
            # elif duration > 5:
            #     batch_size = max(1, batch_size // 10)
            #     log.info("Slowing down, using batch size %s", batch_size)

            nops += 1
