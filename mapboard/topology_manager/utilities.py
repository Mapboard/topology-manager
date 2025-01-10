from rich.console import Console
from rich.theme import Theme

theme = Theme(
    {
        "error": "bold red",
        "header": "bold green",
    }
)

# Set up console styles
console = Console(
    theme=theme,
    log_time_format="[%X]",
)


def enable_triggers(db, enabled: bool):
    """Enable triggers for the database"""
    console.log("Enabling triggers")
    db.run_sql(
        """
        CREATE OR REPLACE FUNCTION {topo_schema}.triggers_enabled()
        RETURNS boolean AS $$
          SELECT :enabled;
        $$ LANGUAGE sql
        """,
        dict(enabled=enabled),
    )
