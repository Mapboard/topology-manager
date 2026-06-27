from time import perf_counter

from ..config import TopologyContext, get_context
from ..utilities import console, print_step
from .clean_topology import clean_topology
from .update_contacts import update_contacts
from .update_faces import update_faces
from .update_composite_layers import update_composite_layers

verbose = True


def update(
    ctx: TopologyContext = None,
    *,
    reset: bool = False,
    fill_holes: bool = False,
    fix_failed: bool = False,
    incremental: bool = False,
    composite_layers: bool = False,
    boundaries: bool = True,
    faces: bool = True,
):
    """Update the topology"""
    if ctx is None:
        ctx = get_context()

    n_contacts_updated = 0

    t_init = perf_counter()
    t_start = t_init

    if boundaries:
        console.print("Updating boundaries", style="header")
        n_contacts_updated = update_contacts(ctx, fix_failed=fix_failed)
        t1 = perf_counter()
        print_step("Update boundaries", t1 - t_start)
        t_start = t1

    if n_contacts_updated > 0:
        console.print("Cleaning topology (pre-faces)", style="header")
        clean_topology(ctx)
        t2 = perf_counter()
        print_step("Clean topology (pre-faces)", t2 - t_start)
        t_start = t2

    if faces:
        console.print("Updating faces", style="header")
        update_faces(
            ctx,
            reset=reset,
            fill_holes=fill_holes,
            incremental=incremental,
        )
        t3 = perf_counter()
        print_step("Update faces", t3 - t_start)
        t_start = t3

    if boundaries or faces:
        console.print("Cleaning topology", style="header")
        clean_topology(ctx)
        t4 = perf_counter()
        print_step("Clean topology", t4 - t_start)
        t_start = t4

    if composite_layers:
        console.print("Updating composite layers", style="header")
        update_composite_layers(ctx)
        t5 = perf_counter()
        print_step("Update composite layers", t5 - t_start)

    print_step("Total", perf_counter() - t_start)
