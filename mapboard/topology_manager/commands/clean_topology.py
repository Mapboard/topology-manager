from ..database import get_database, sql
from ..utilities import console


def delete_edges():
    db = get_database()
    db.proc("procedures/clean-topology-01")

    console.print("Deleting edges", style="header")
    res = db.run_query(sql("procedures/get-edges-to-delete"))
    for row in res:
        edge_id = row.edge_id
        console.print(f"Deleting edge {edge_id}", style="error")
        try:
            db.run_query(
                sql("procedures/clean-topology-rem-edge"), {"edge_id": edge_id}
            ).one()
        except Exception as e:
            console.print(f"Error deleting edge {edge_id}: {e}", style="error")
            continue
    db.proc("procedures/clean-topology-02")


verbose = True


def clean_topology():
    """Clean topology"""
    db = get_database()

    delete_edges()

    with db.session.begin():
        console.print("Healing edges", style="header")
        res = db.run_query(sql("procedures/get-edges-to-heal"))
        counter = 0
        for row in res:
            console.print(
                f"Healing edges [green]{row.edge1}[/green] and [green]{row.edge2}[/green]"
            )
            try:
                db.run_query(
                    sql("procedures/clean-topology-heal-edges"),
                    {"edge1": row.edge1, "edge2": row.edge2},
                ).one()
                counter += 1
            except Exception as err:
                console.print(str(err), style="error")

        console.print(f"Healed {counter} edges")
