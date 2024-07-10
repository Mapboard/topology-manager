from rich.progress import Progress

from ..database import Database, get_database, sql
from ..utilities import console

count = sql("procedures/count-contact")
get_contacts = sql("procedures/get-contacts-to-update")
reset_errors = sql("procedures/reset-linework-errors")
post_update = sql("procedures/post-update-contacts")


def update_contacts(fix_failed: bool = False):
    """Update contacts"""
    db = get_database()
    _update_contacts(db, fix_failed)


def _update_contacts(db: Database, fix_failed: bool = False, bulk: bool = False):
    nlines = db.run_query(count).scalar()

    if fix_failed:
        db.run_sql(reset_errors)

    if nlines == 0:
        console.print("No contacts to update")

    if bulk:
        db.run_sql("SET session_replication_role = replica;")

    res = db.run_query(get_contacts).all()
    remaining = len(res)
    if remaining == 0:
        return

    with Progress() as progress:
        bar = progress.add_task("Updating lines", total=nlines)
        while remaining > 0:
            rows = db.run_query(sql("procedures/update-contact"), {"n": 10}).all()
            nrows = len(rows)
            for row in rows:
                if row.err is not None:
                    console.print(f"[dim]{row.id}[/dim]: [error]{row.err}[/error]")
            progress.update(bar, advance=nrows)
            remaining -= nrows

    db.run_query(post_update)

    if bulk:
        db.run_sql("SET session_replication_role = DEFAULT;")
        # Mark all faces as dirty
