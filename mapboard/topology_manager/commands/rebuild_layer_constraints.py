"""
Rebuild check constraints for all layers in the topology. Sometimes, dumps and
restores can invalidate constraints, requiring topogeometries to be rebuilt.
"""
from ..config import TopologyContext
from psycopg.sql import Identifier, Literal
from rich import print

def rebuild_layer_constraints(ctx: TopologyContext):
    layers = ctx.database.run_query(
        """
        SELECT l.*
        FROM topology.layer l
        JOIN topology.topology t
          ON l.topology_id = t.id
        WHERE t.name = :topo_name
        """
    ).all()

    for l in layers:
        # If the constraint exists and is validated, we skip it
        table = Identifier(l.schema_name, l.table_name)
        table_name = f"{l.schema_name}.{l.table_name}"
        res = ctx.database.run_query(
            """
            SELECT conname, convalidated
            FROM pg_constraint
            WHERE conname = 'check_topogeom_topo'
              AND conrelid = :table::regclass
            """,
            dict(table=table_name),
        ).one_or_none()
        _exists = res is not None
        _valid = _exists and res.convalidated
        print(f"[bold cyan]{table_name}[/bold cyan]:")
        if _exists and _valid:
            print(f"  valid, skipping")
            continue
        if _exists and not _valid:
            print(f"  invalid")
            ctx.database.run_sql("ALTER TABLE {table} DROP CONSTRAINT check_topogeom_topo", dict(table=table))

        print(f"  rebuilding")

        ctx.database.run_sql(
            """
            ALTER TABLE {table} ADD CONSTRAINT check_topogeom_topo
                CHECK (
                    (
                        (({feature_column}).topology_id = {topology_id})
                    AND (({feature_column}).layer_id = {layer_id})
                    AND (({feature_column}).type = {feature_type})
                    )
                ) NOT VALID;
            ALTER TABLE {table} VALIDATE CONSTRAINT check_topogeom_topo;
            """,
            dict(
                feature_column=Identifier(l.feature_column),
                table=table,
                topology_id = Literal(l.topology_id),
                layer_id = Literal(l.layer_id),
                feature_type = Literal(l.feature_type)
            )
        )
