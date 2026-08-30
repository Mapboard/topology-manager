"""
Repair topology metadata that a dump/restore can invalidate.

Two artifacts drift for the same reason -- PostGIS records the topology id in
places a restore can renumber:

- the per-layer ``check_topogeom_topo`` constraints, which may be dropped or
  left unvalidated;
- the ``relation_integrity_checks`` trigger, which carries the topology id as
  a *literal* in its arguments while ``topology.topology.id`` comes from a
  sequence. When those disagree every topogeometry insert fails with
  ``Layer N does not exist in topology <stale id>``.

The two are independent -- constraints can be perfectly valid while the
trigger is stale -- so both are checked.
"""
from ..config import TopologyContext
from psycopg.sql import Identifier, Literal
from rich import print

def rebuild_layer_constraints(ctx: TopologyContext):
    """Rebuild layer check constraints, then repair the relation trigger."""
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

    rebuild_relation_trigger(ctx)


def rebuild_relation_trigger(ctx: TopologyContext):
    """Re-point the relation integrity trigger at the topology's current id.

    PostGIS writes the id into the trigger's arguments as a literal, so a
    restore that renumbers ``topology.topology`` leaves the trigger pointing at
    a topology that no longer exists.
    """
    res = ctx.database.run_query(
        """
        SELECT
          t.id,
          pg_get_triggerdef(g.oid) NOT LIKE
            '%relationtrigger(' || quote_literal(t.id::text) || '%' AS stale
        FROM topology.topology t
        JOIN pg_trigger g
          ON g.tgname = 'relation_integrity_checks'
         AND g.tgrelid = (t.name || '.relation')::regclass
        WHERE t.name = :topo_name
        """
    ).one_or_none()

    print("[bold cyan]relation_integrity_checks[/bold cyan]:")
    if res is not None and not res.stale:
        print("  valid, skipping")
        return

    topology_id = ctx.database.run_query(
        "SELECT id FROM topology.topology WHERE name = :topo_name"
    ).scalar()
    if topology_id is None:
        print("  no such topology, skipping")
        return
    print(f"  rebuilding against topology {topology_id}")

    relation = Identifier(ctx.topo_schema, "relation")
    ctx.database.run_sql(
        "DROP TRIGGER IF EXISTS relation_integrity_checks ON {relation}",
        dict(relation=relation),
    )
    ctx.database.run_sql(
        """
        CREATE TRIGGER relation_integrity_checks
          BEFORE INSERT OR UPDATE ON {relation}
          FOR EACH ROW
          EXECUTE FUNCTION topology.relationtrigger(:topology_id, :topo_name)
        """,
        dict(
            relation=relation,
            topology_id=str(topology_id),
        ),
    )
