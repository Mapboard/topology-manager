from time import perf_counter

from psycopg.sql import Identifier

from ..config import TopologyContext, get_context
from ..database import sql
from ..utilities import console, print_step
from macrostrat.utils import get_logger

log = get_logger(__name__)


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


def remove_empty_topogeometries(db):
    layers = db.run_query(
        """
      SELECT
          l.topology_id,
          l.layer_id,
          l.schema_name,
          l.table_name,
          l.feature_column,
          l.feature_type
      FROM topology.layer l
      JOIN topology.topology t ON t.id = l.topology_id
      WHERE t.name = :topo_name
    """
    ).all()

    for lyr in layers:
        with db.session.begin_nested():
            table_name = f"{lyr.schema_name}.{lyr.table_name}"
            params = dict(
                table=Identifier(lyr.schema_name, lyr.table_name),
                feature_column=Identifier(lyr.feature_column),
                layer_id=lyr.layer_id,
                feature_type=lyr.feature_type,
                topology_id=lyr.topology_id,
            )

            res = db.run_query(
                sql("procedures/clean-topology/remove-empty-topogeometries"), params
            ).scalar()
            console.print(
                f"Removed {res} empty relations for [cyan]{table_name}[/cyan][dim].{lyr.feature_column}[/dim]"
            )


def clean_topology(ctx: TopologyContext):
    """Clean topology"""
    # _delete_edges(db)

    db = ctx.database

    data_layer = (ctx.boundary_table, "topo")

    t0 = perf_counter()

    # Is removing empty topogeometries still needed? Removing them from the data layer
    # seems like overkill.
    # remove_empty_topogeometries(db, ctx.data_schema, *data_layer)

    remove_empty_topogeometries(db)
    print_step("remove empty topogeometries", perf_counter() - t0)

    db.session.commit()
    t1 = perf_counter()
    res = db.run_query(
        "SELECT RemoveUnusedPrimitives(:topo_name)", use_transaction=False
    ).scalar()
    log.info(f"Removed {res} unused primitives")
    print_step("RemoveUnusedPrimitives", perf_counter() - t1)

    t2 = perf_counter()
    res = db.run_query(sql("procedures/clean-topology/heal-edges")).scalar()
    log.info(f"Healed {res} edges")
    print_step("heal edges", perf_counter() - t2)

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
