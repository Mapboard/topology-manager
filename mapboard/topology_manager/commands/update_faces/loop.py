"""The face-update loop: drain `dirty_face` into settled map faces.

    queue ← dirty faces
    while queue:
        batch ← dissolve the next N unsettled seeds (N = persist interval)
        reseeds ← persist(batch)          # create / absorb / replace, per mode
        queue ← queue + unsettled reseeds

A primitive is *settled* once it belongs to a persisted component; components
partition the layer's joinable graph and the graph does not change while faces
are persisted, so each seed is dissolved at most once and the loop terminates.
Re-seeds are the remainders of faces that lost primitives; processing them is
what splits a disconnected remainder and rebuilds a face that would otherwise be
left as a hole.
"""

from collections import defaultdict, deque
from time import perf_counter
from typing import Iterable, Optional

from macrostrat.database import Database
from macrostrat.utils import get_logger
from rich.progress import Progress

from .dissolve import dissolve_component
from .models import DirtyFace, FaceUpdateResult, FaceUpdateStats
from .persist import FacePersister

log = get_logger("mapboard.topology_manager.update_faces")


class FaceUpdateLoop:
    def __init__(
        self,
        db: Database,
        persister: FacePersister,
        *,
        batch_size: Optional[int] = None,
        progress: bool = True,
    ):
        self.db = db
        self.persister = persister
        # None: dissolve everything before persisting (one batch per round).
        self.batch_size = batch_size
        self.progress = progress

    def run(self, seeds: Iterable[DirtyFace]) -> FaceUpdateStats:
        seeds = list(seeds)
        queue: deque[DirtyFace] = deque(seeds)
        settled: dict[int, set[int]] = defaultdict(set)
        stats = self.persister.stats
        stats.seeds = len(seeds)

        t0 = perf_counter()
        self.persister.begin_run(seeds)
        try:
            with Progress(disable=not self.progress) as progress:
                bar = progress.add_task("Updating faces", total=len(seeds))
                total = len(seeds)
                done = 0
                while queue:
                    batch: list[FaceUpdateResult] = []
                    while queue and (
                        self.batch_size is None or len(batch) < self.batch_size
                    ):
                        seed = queue.popleft()
                        done += 1
                        if seed.id in settled[seed.map_layer]:
                            continue
                        component = dissolve_component(self.db, seed.id, seed.map_layer)
                        settled[seed.map_layer].update(component.dissolved_faces)
                        batch.append(component)
                        progress.update(bar, completed=done, total=total)

                    reseeds = self.persister.persist(batch)
                    stats.rounds += 1
                    fresh = [r for r in reseeds if r.id not in settled[r.map_layer]]
                    if fresh:
                        log.info("%d re-seeded primitives to revisit", len(fresh))
                        queue.extend(fresh)
                        total += len(fresh)
                    progress.update(bar, completed=done, total=total)
        finally:
            self.persister.end_run()

        log.info(
            "Updated %d dirty faces in %.2f seconds: %d components, %d created, "
            "%d updated, %d deleted, %d shed, %d re-seeded, %d rounds",
            stats.seeds,
            perf_counter() - t0,
            stats.components,
            stats.created,
            stats.updated,
            stats.deleted,
            stats.shed,
            stats.reseeded,
            stats.rounds,
        )
        return stats
