"""The face-update loop: drain `dirty_face` into settled map faces.

    for each layer with dirty faces:
        while the layer has dirty faces:
            groups <- dissolve_groups(layer, batch)   # server-side, one round trip
            persist(groups)                          # move or replace, then un-mark

`dirty_face` itself is the queue. Persisting a batch un-marks its components;
anything a `move`-mode shed re-marks (one primitive per shed face) is simply
picked up by the next `dissolve_groups` call. `ServerSideFaceUpdateLoop` runs
the same loop entirely in PL/pgSQL, one call per chunk.
"""

from collections import defaultdict
from time import perf_counter
from typing import Iterable, Optional

from macrostrat.database import Database
from macrostrat.utils import get_logger
from rich.progress import Progress

from .dissolve import dissolve_layer_groups
from .models import DirtyFace, FaceUpdateStats
from .persist import FacePersister

log = get_logger("mapboard.topology_manager.update_faces")


def _n_dirty(db: Database, map_layer: Optional[int] = None) -> int:
    query = "SELECT count(*)::integer FROM {topo_schema}.dirty_face"
    params = {}
    if map_layer is not None:
        query += " WHERE map_layer = :map_layer"
        params["map_layer"] = map_layer
    return db.run_query(query, params).scalar()


class FaceUpdateLoop:
    """Batch loop driven from Python: `dissolve_groups` per layer, then persist."""

    def __init__(
        self,
        db: Database,
        persister: FacePersister,
        *,
        batch_size: Optional[int] = None,
        progress: bool = True,
        bulk_identity: bool = False,
    ):
        self.db = db
        self.persister = persister
        # None: dissolve every component of a layer before persisting.
        self.batch_size = batch_size
        self.progress = progress
        # `dissolve_groups` fills the identity cache itself when the strategy
        # offers one; the flag is accepted for interface parity with the
        # server-side loop.
        self.bulk_identity = bulk_identity

    def run(self, seeds: Iterable[DirtyFace]) -> FaceUpdateStats:
        seeds = list(seeds)
        stats = self.persister.stats
        stats.seeds = len(seeds)
        layers = sorted({s.map_layer for s in seeds})
        layer_start: dict[int, int] = defaultdict(int)
        for seed in seeds:
            layer_start[seed.map_layer] += 1

        t0 = perf_counter()
        self.persister.begin_run(seeds)
        try:
            with Progress(disable=not self.progress) as progress:
                total = len(seeds)
                done = 0
                bar = progress.add_task("Updating faces", total=total)
                for layer in layers:
                    layer_done = 0
                    remaining = _n_dirty(self.db, layer)
                    while remaining > 0:
                        groups = dissolve_layer_groups(
                            self.db, layer, max_groups=self.batch_size
                        )
                        if not groups:
                            log.warning(
                                "No components for %d dirty faces in layer %s; moving on",
                                remaining,
                                layer,
                            )
                            break
                        self.persister.persist(groups)
                        # Nothing above has committed. `run_query` does not (its
                        # commit sits after a yield the caller never resumes); only
                        # `unmark_dirty`, which happens to use `run_sql`, does. That
                        # makes the checkpoint depend on which helper a store method
                        # calls, so commit the batch deliberately instead.
                        self.db.session.commit()
                        stats.rounds += 1

                        remaining = _n_dirty(self.db, layer)
                        # Progress is denominated in dirty primitives. A shed can
                        # re-mark a primitive, so widen the total rather than let
                        # the bar go backwards.
                        settled_now = layer_start[layer] - remaining
                        if settled_now < layer_done:
                            growth = layer_done - settled_now
                            layer_start[layer] += growth
                            total += growth
                            settled_now = layer_done
                        done += settled_now - layer_done
                        layer_done = settled_now
                        progress.update(bar, completed=done, total=total)
        finally:
            self.persister.end_run()

        log.info(
            "Updated %d dirty faces in %.2f seconds: %d components, %d created, "
            "%d updated, %d deleted, %d shed, %d re-seeded, %d batches",
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


class ServerSideFaceUpdateLoop:
    """Drain `dirty_face` with the PL/pgSQL `update_dirty_faces` function.

    Same algorithm as `FaceUpdateLoop`, but each call to the database processes
    a whole chunk of components (dissolve, persist, un-mark), so a chunk costs
    one round trip instead of two. The loop commits after each chunk, which is what
    makes a chunk the checkpoint -- `update_dirty_faces` is a function and cannot
    commit on its own.

    The chunk size is **adaptive**. A component can cost anywhere from a
    millisecond to ten seconds depending on how much of the layer it spans, so a
    fixed count is wrong at both ends: 100 tiny components is a wasted round trip,
    100 continental ones is five minutes with no checkpoint and no progress. Each
    chunk is timed and the next is sized to land in `TARGET_SECONDS`, starting
    small so the first measurement costs little.

    This only pays off because a chunk's fixed cost is small: the identity cache
    is filled once per layer (`_refresh_identity`), not once per chunk.
    """

    # The band a chunk should land in. Long enough that one round trip and the
    # per-chunk bookkeeping are noise; short enough to checkpoint often and to
    # notice quickly when components get more expensive.
    TARGET_SECONDS = 5.0
    MIN_SECONDS = 1.0
    MAX_SECONDS = 10.0
    FIRST_CHUNK = 1
    # Never more than this in one step, so a run of trivial components cannot
    # overshoot into a chunk that then takes minutes.
    MAX_GROWTH = 4.0
    DEFAULT_MAX_CHUNK = 5000

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
        # An explicit batch size caps the chunk; the loop still starts small and
        # grows into it rather than opening with it.
        self.max_chunk = batch_size or self.DEFAULT_MAX_CHUNK
        self.progress = progress

    def _next_chunk(self, chunk: int, components: int, elapsed: float) -> int:
        """Size the next chunk from how long this one took."""
        if components <= 0:
            return chunk
        if self.MIN_SECONDS <= elapsed <= self.MAX_SECONDS:
            return chunk
        per_component = elapsed / components
        if per_component <= 0:
            return min(int(chunk * self.MAX_GROWTH), self.max_chunk)
        target = int(self.TARGET_SECONDS / per_component)
        ceiling = min(int(chunk * self.MAX_GROWTH) or 1, self.max_chunk)
        return max(1, min(target, ceiling))

    def run(self, seeds: Iterable[DirtyFace]) -> FaceUpdateStats:
        seeds = list(seeds)
        stats = self.persister.stats
        stats.seeds = len(seeds)
        layers = sorted({s.map_layer for s in seeds})
        # The bar is denominated in dirty primitives, so progress is read from the
        # layer's `remaining` count -- not from `components`, which counts a chunk
        # of at most `batch_size` however many primitives it settled.
        layer_start: dict[int, int] = defaultdict(int)
        for seed in seeds:
            layer_start[seed.map_layer] += 1

        t0 = perf_counter()
        self.persister.begin_run(seeds)
        try:
            with Progress(disable=not self.progress) as progress:
                total = len(seeds)
                done = 0
                bar = progress.add_task("Updating faces", total=total)
                for layer in layers:
                    layer_done = 0
                    chunk = min(self.FIRST_CHUNK, self.max_chunk)
                    first = True
                    while True:
                        t_chunk = perf_counter()
                        row = self.db.run_query(
                            "SELECT * FROM {topo_schema}.update_dirty_faces("
                            ":layer, :mode, :limit, :refresh_identity)",
                            dict(
                                layer=layer,
                                mode=self.persister.mode.value,
                                limit=chunk,
                                # Identity is invariant while faces are persisted,
                                # so one fill serves the whole layer.
                                refresh_identity=first,
                            ),
                        ).one()
                        elapsed = perf_counter() - t_chunk
                        # `update_dirty_faces` is a function, and a function cannot
                        # COMMIT -- the chunk runs inside this session's
                        # transaction. `run_query` does not commit either, so
                        # without this the whole run is one transaction and a cancel
                        # discards every chunk. This line is what makes a chunk a
                        # checkpoint.
                        self.db.session.commit()
                        first = False
                        stats.rounds += 1
                        stats.components += row.components
                        stats.created += row.created
                        stats.updated += row.updated
                        stats.deleted += row.deleted
                        stats.shed += row.shed
                        stats.reseeded += row.reseeded

                        settled_now = layer_start[layer] - row.remaining
                        if settled_now < layer_done:
                            # Sheds re-marked more primitives than this chunk settled;
                            # widen the denominator rather than going backwards.
                            growth = layer_done - settled_now
                            layer_start[layer] += growth
                            total += growth
                            settled_now = layer_done
                        done += settled_now - layer_done
                        layer_done = settled_now
                        progress.update(bar, completed=done, total=total)
                        if row.remaining == 0 or row.components == 0:
                            break

                        next_chunk = self._next_chunk(chunk, row.components, elapsed)
                        if next_chunk != chunk:
                            log.debug(
                                "Layer %d: %d components in %.2fs (%.3fs each); "
                                "chunk %d -> %d",
                                layer,
                                row.components,
                                elapsed,
                                elapsed / max(row.components, 1),
                                chunk,
                                next_chunk,
                            )
                        chunk = next_chunk
        finally:
            self.persister.end_run()

        log.info(
            "Updated %d dirty faces server-side in %.2f seconds: %d components, "
            "%d created, %d updated, %d deleted, %d shed, %d re-seeded, %d chunks",
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
