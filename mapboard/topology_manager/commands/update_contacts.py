from rich.progress import Progress

from ..database import get_database, sql
from ..utilities import console

count = sql("procedures/count-contact")
update_contacts = sql("procedures/update-contact")  # Called `proc` in the original code
reset_errors = sql("procedures/reset-linework-errors")
get_contacts = sql("procedures/get-contacts-to-update")
post_update = sql("procedures/post-update-contacts")


def update_contacts(fix_failed: bool = False):
    """Update contacts"""
    db = get_database()

    nlines = db.run_query(count).one().nlines

    if fix_failed:
        db.run_sql(reset_errors)

    if nlines == 0:
        console.print("No contacts to update")

    res = db.run_query(get_contacts)
    remaining = res.count()
    with Progress() as progress:
        bar = progress.add_task("Updating lines", total=nlines)
        while remaining > 0:
            try:
                rows = db.run_query(update_contacts, {"n": 10}).all()
                nrows = len(rows)
                for row in rows:
                    if row.err is not None:
                        console.print(f"[dim]{row.id}[/dim]: [error]{row.err}[/error]")
            except Exception as e:
                console.print(f"{e}", style="error")
            bar.update(advance=nrows)
            remaining -= nrows

    return db.run_query(post_update).all()
