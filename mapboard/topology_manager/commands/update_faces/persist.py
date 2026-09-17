"""Persisting dissolved components onto `map_face`.

Two strategies implement the same interface, selected by `FaceUpdateMode`:

- `MoveFacesPersister` (``move``): primitives are moved between existing faces.
- `ReplaceFacesPersister` (``replace``): overlapping faces are deleted and a new
  one is created (the historical behaviour).

Both return the primitives that the operation *re-seeded* — the remainder of any
face that lost primitives — so the loop can revisit them. That is what turns a
shed into a split when the remainder is disconnected, and what prevents a face's
remainder from being left without a map face.
"""

from collections import defaultdict
from typing import Iterable, Optional

from macrostrat.database import Database
from macrostrat.utils import get_logger

from ...config import FaceUpdateMode
from .models import DirtyFace, FaceUpdateResult, FaceUpdateStats, MapFaceChange
from .store import MapFaceStore

log = get_logger("mapboard.topology_manager.update_faces")


class FacePersister:
    """Persists components one at a time; subclasses decide how."""

    mode: FaceUpdateMode

    def __init__(self, db: Database):
        self.db = db
        self.store = MapFaceStore(db)
        self.stats = FaceUpdateStats()

    # Run lifecycle -----------------------------------------------------------

    def begin_run(self, seeds: Iterable[DirtyFace]):
        """Called once with the dirty faces present when the run starts."""

    def end_run(self):
        """Called once when the run has drained the queue."""

    # Persisting ---------------------------------------------------------------

    def apply(self, component: FaceUpdateResult) -> MapFaceChange:
        raise NotImplementedError

    def persist(
        self, components: list[FaceUpdateResult], *, unmark_dirty: bool = True
    ) -> list[DirtyFace]:
        """Persist a batch of components, returning the primitives to revisit."""
        reseeds: list[DirtyFace] = []
        for component in components:
            change = self.apply(component)
            self.stats.add(change)
            reseeds.extend(change.reseeds(component.map_layer))
        if unmark_dirty:
            # The re-seeded primitives lie outside every component in the batch,
            # so they survive this and are picked up by the loop.
            self.store.unmark_dirty_components(components)
        self._log_batch(components, reseeds)
        return reseeds

    def _log_batch(self, components, reseeds):
        by_layer = defaultdict(int)
        for c in components:
            by_layer[c.map_layer] += 1
        log.info(
            "Persisted %d components (%s mode) in layers %s; %d primitives re-seeded",
            len(components),
            self.mode.value,
            ", ".join(f"{k}: {v}" for k, v in by_layer.items()),
            len(reseeds),
        )


class MoveFacesPersister(FacePersister):
    """Move primitives between existing map faces (`map_face_absorb`)."""

    mode = FaceUpdateMode.MOVE

    def begin_run(self, seeds: Iterable[DirtyFace]):
        by_layer: dict[int, set[int]] = defaultdict(set)
        for seed in seeds:
            by_layer[seed.map_layer].add(seed.id)
        for layer, faces in by_layer.items():
            self.store.set_reshaped_faces(layer, faces)

    def end_run(self):
        self.store.clear_reshaped_faces()

    def apply(self, component: FaceUpdateResult) -> MapFaceChange:
        if component.touches_universe:
            return self.store.release(component.dissolved_faces, component.map_layer)
        return self.store.absorb(component.dissolved_faces, component.map_layer)


class ReplaceFacesPersister(FacePersister):
    """Delete overlapping map faces and create a new one (`map_face_replace`)."""

    mode = FaceUpdateMode.REPLACE

    def apply(self, component: FaceUpdateResult) -> MapFaceChange:
        return self.store.replace(
            component.dissolved_faces,
            component.map_layer,
            create=not component.touches_universe,
        )


_PERSISTERS = {
    FaceUpdateMode.MOVE: MoveFacesPersister,
    FaceUpdateMode.REPLACE: ReplaceFacesPersister,
}


def get_persister(db: Database, mode: FaceUpdateMode | str) -> FacePersister:
    return _PERSISTERS[FaceUpdateMode(mode)](db)


def persist_map_face_updates(
    db: Database,
    updates: list[FaceUpdateResult],
    *,
    unmark_dirty: bool = True,
    mode: Optional[FaceUpdateMode | str] = None,
) -> list[DirtyFace]:
    """Persist components outside the loop (compatibility entry point).

    Returns any re-seeded primitives; callers that want the invariants the loop
    guarantees (no holes, one face per component) must process them.
    """
    if mode is None:
        from ...config import get_context

        mode = get_context().face_update_mode
    persister = get_persister(db, mode)
    persister.begin_run([])
    try:
        return persister.persist(updates, unmark_dirty=unmark_dirty)
    finally:
        persister.end_run()
