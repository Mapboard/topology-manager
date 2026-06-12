from pathlib import Path

from psycopg.sql import SQL, Identifier

root = Path(__file__).parent


def create_demo_units(db):
    db.run_sql(root / "procedures" / "01-create-temp-tables.sql")

    for type in ["linework", "polygon"]:
        import_csv(
            db,
            root / "defs" / f"{type}-types.csv",
            f"tmp_{type}_type",
        )


    db.run_sql(root / "procedures" / "03-add-to-map.sql")


def import_csv(db, csv_path: Path, tablename, schema=None, check=True):
    """Import CSV data into the database"""

    if schema is None:
        tablename = Identifier(tablename)
    else:
        tablename = Identifier(schema, tablename)

    stmt = (
        "COPY {tablename} (id, name, color, layer) FROM STDIN DELIMITER ',' CSV HEADER"
    )
    stmt = SQL(stmt).format(tablename=tablename)

    # Use an explicit transaction so imported rows are committed.
    with db.engine.begin() as conn:
        _conn = conn.connection.dbapi_connection
        with _conn.cursor() as cursor:
            with open(csv_path, "r") as f:
                with cursor.copy(stmt) as copy:
                    copy.write(f.read())

    if check:
        # Verify that COPY inserted at least one row.
        res = db.run_query("SELECT COUNT(*) FROM {tablename}", dict(tablename=tablename))
        assert res.scalar() > 0
