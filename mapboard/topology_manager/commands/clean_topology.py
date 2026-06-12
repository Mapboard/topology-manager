from ..database import get_database, sql
from ..utilities import console
from psycopg.sql import Identifier
from macrostrat.utils import get_logger

log = get_logger(__name__)


def clean_topology():
    """Clean the topology"""
    db = get_database()
    _clean_topology(db)


def _delete_edges(db):
    """
    This function deletes edges in the topology. It is a legacy
    function and not used anymore, but we keep it around in case we need
    to bring it back into use.
    """

    db.proc("procedures/clean-topology-01")

    console.print("Deleting edges", style="header")
    res = db.run_query(sql("procedures/get-edges-to-delete"))
    for row in res:
        edge_id = row.edge_id
        console.print(f"Deleting edge {edge_id}", style="error")
        db.run_sql(
            sql("procedures/clean-topology-rem-edge"),
            {"edge_id": edge_id},
        )
    db.proc("procedures/clean-topology-02")


verbose = True


def remove_empty_topogeometries(db, schema, table, column):
    table_name = f"{schema}.{table}"
    params = dict(
        table=Identifier(schema, table),
        table_name=table_name,
        column=Identifier(column),
        column_name=column,
    )

    with db.session.begin_nested():
        res = db.run_query(
            sql("procedures/clean-topology/remove-empty-topogeometries"), params
        ).scalar()
        db.session.commit()
        console.print(
            f"Removed {res} empty topogeometries for [cyan]{table_name}[/cyan][gray].{column}[/gray]"
        )


def _clean_topology(db):
    """Clean topology"""
    # _delete_edges(db)

    data_schema = db.instance_params["data_schema_name"]
    topo_schema = db.instance_params["topo_name"]

    remove_empty_topogeometries(db, data_schema, "linework", "topo")
    remove_empty_topogeometries(db, topo_schema, "map_face", "topo")

    res = db.run_query("SELECT RemoveUnusedPrimitives(:topo_name)").scalar()
    log.info(f"Removed {res} unused primitives")

    res = db.run_query(sql("procedures/clean-topology/heal-edges")).scalar()
    log.info(f"Healed {res} edges")

    # heal_edges_piecewise(db)


def heal_edges_piecewise(db):
    with db.session.begin_nested():
        console.print("Healing edges", style="header")
        res = db.run_query(sql("procedures/clean-topology/get-edges-to-heal"))
        counter = 0
        for row in res:
            console.print(
                f"Healing edges [green]{row.edge1}[/green] and [green]{row.edge2}[/green]"
            )
            try:
                db.run_query(
                    "SELECT ST_ModEdgeHeal(:topo_name , :edge1, :edge2)",
                    {"edge1": row.edge1, "edge2": row.edge2},
                ).one()
                counter += 1
            except Exception as err:
                console.print(str(err), style="error")

        log.info(f"Healed {counter} edges")
