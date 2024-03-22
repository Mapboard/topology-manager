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
