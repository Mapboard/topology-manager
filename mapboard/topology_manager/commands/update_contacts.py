from rich.progress import Progress
from macrostrat.database import run_query

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


def _update_contacts(
    db: Database, fix_failed: bool = False, bulk: bool = False, chunk_size: int = 100
):
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
            rows = _run_query(db, chunk_size, bulk=bulk)
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


def _run_query(db, chunk_size, bulk=False):
    _proc = sql("procedures/update-contact")
    _params = {"n": chunk_size}
    if not bulk:
        # The simple case
        return db.run_query(_proc, _params).all()
    # If in bulk mode, we must use a version of run_query that supports
    # running outside a transaction block
    conn = db.engine.connect()
    conn.execution_options(isolation_level="AUTOCOMMIT")
    params = db._setup_params(_params, {})
    return run_query(
        conn,
        _proc,
        params,
    ).all()
