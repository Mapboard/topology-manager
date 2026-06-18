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


def print_step(name: str, tdelta: float):
    if tdelta > 60:
        step_time = f"{tdelta / 60:.2f} minutes"
    elif tdelta >= 0.5:
        step_time = f"{tdelta:.2f} seconds"
    elif tdelta >= 0.0005:
        step_time = f"{tdelta * 1000:.2f} ms"
    else:
        step_time = f"{tdelta * 1000 * 1000:.0f} µs"
    console.print(f"  [bold]{name}[/] [cyan]{step_time}[/]")
