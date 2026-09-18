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

from .dissolve import dissolve_component, prepare_layer_identity
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
        bulk_identity: bool = False,
    ):
        self.db = db
        self.persister = persister
        # None: dissolve everything before persisting (one batch per round).
        self.batch_size = batch_size
        self.progress = progress
        # Whether the identity strategy offers `resolve_layer_identity`, so the
        # walk can compare cached identities instead of calling
        # `faces_are_joinable` on every candidate edge.
        self.bulk_identity = bulk_identity

    def run(self, seeds: Iterable[DirtyFace]) -> FaceUpdateStats:
        seeds = list(seeds)
        queue: deque[DirtyFace] = deque(seeds)
        settled: dict[int, set[int]] = defaultdict(set)
        # Dirty primitives not yet settled, per layer. The bar counts these down
        # rather than counting seeds *popped*: one component settles every dirty
        # primitive it covers, which can be thousands, so a pop-counted bar reports
        # a fraction of a percent through a batch that has done real work.
        pending: dict[int, set[int]] = defaultdict(set)
        for seed in seeds:
            pending[seed.map_layer].add(seed.id)
        stats = self.persister.stats
        stats.seeds = len(seeds)
        # The layer `_layer_identity` currently holds, or None when unfilled.
        cached_layer: Optional[int] = None

        t0 = perf_counter()
        self.persister.begin_run(seeds)
        try:
            with Progress(disable=not self.progress) as progress:
                total = len(seeds)
                done = 0
                bar = progress.add_task("Updating faces", total=total)
                while queue:
                    batch: list[FaceUpdateResult] = []
                    while queue and (
                        self.batch_size is None or len(batch) < self.batch_size
                    ):
                        seed = queue.popleft()
                        if seed.id in settled[seed.map_layer]:
                            continue
                        # The cache holds for a whole layer, so it is refilled only
                        # when the queue moves to a different one. Seeds arrive in
                        # layer order and re-seeds stay in their own layer, so this
                        # is a handful of fills per run, not one per component.
                        if self.bulk_identity and seed.map_layer != cached_layer:
                            prepare_layer_identity(self.db, seed.map_layer)
                            cached_layer = seed.map_layer
                        component = dissolve_component(
                            self.db,
                            seed.id,
                            seed.map_layer,
                            use_identity_cache=self.bulk_identity,
                        )
                        settled[seed.map_layer].update(component.dissolved_faces)
                        covered = pending[seed.map_layer].intersection(
                            component.dissolved_faces
                        )
                        pending[seed.map_layer].difference_update(covered)
                        done += len(covered)
                        batch.append(component)
                        progress.update(bar, completed=done, total=total)

                    reseeds = self.persister.persist(batch)
                    stats.rounds += 1
                    # A batch sheds the same map face from several components, so one
                    # primitive can be re-seeded many times over; `pending` is also
                    # already holding everything still queued. Count each primitive
                    # into the denominator once, or the bar slides backwards and never
                    # reaches its total.
                    fresh: list[DirtyFace] = []
                    for r in reseeds:
                        if r.id in settled[r.map_layer] or r.id in pending[r.map_layer]:
                            continue
                        pending[r.map_layer].add(r.id)
                        fresh.append(r)
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


class ServerSideFaceUpdateLoop:
    """Drain `dirty_face` with the PL/pgSQL `update_dirty_faces` function.

    Same algorithm as `FaceUpdateLoop`, but each call to the database processes
    a whole chunk of components (dissolve, persist, un-mark), so a chunk costs
    one round trip instead of two per component. Every call commits, so a chunk
    is also the checkpoint.

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
