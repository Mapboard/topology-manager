"""Dissolving: computing the joinable component around a seed primitive.

Thin wrappers around the server-side `dissolve_component` function
(`fixtures/07-get-adjacent-faces.sql`). The joinable graph depends only on the
boundary topogeometries and the identity strategy — never on `map_face` rows —
so a component can be computed before, and persisted independently of, any other.
"""

from time import perf_counter

from macrostrat.database import Database
from macrostrat.utils import get_logger

from .models import DirtyFace, FaceUpdateResult

log = get_logger("mapboard.topology_manager.update_faces")


def dissolve_component(db: Database, face_id: int, map_layer: int) -> FaceUpdateResult:
    """The maximal set of primitives joinable with `face_id` in `map_layer`."""
    t0 = perf_counter()
    res = db.run_query(
        "SELECT * FROM {topo_schema}.dissolve_component(:face_id, :map_layer)",
        dict(face_id=face_id, map_layer=map_layer),
    ).one()
    component = FaceUpdateResult(
        dissolved_faces=sorted(set(res.faces)),
        existing_map_faces=sorted(set(res.existing_map_faces or [])),
        map_layer=map_layer,
    )
    log.debug(
        "Dissolved %d faces around %d in layer %d in %.2f seconds (%d iterations)",
        len(component.dissolved_faces),
        face_id,
        map_layer,
        perf_counter() - t0,
        res.niter,
    )
    return component


def dissolve_layer_groups(
    db: Database, map_layer: int, *, max_groups: int | None = None
) -> list[FaceUpdateResult]:
    """Dissolve up to `max_groups` of a layer's dirty components in one round trip
    (server-side `dissolve_groups`). The loop itself uses `dissolve_component`
    per seed, or `update_dirty_faces` with the `plpgsql` engine; this is the
    batch form for callers that want the components without persisting them."""
    rows = db.run_query(
        "SELECT * FROM {topo_schema}.dissolve_groups(:map_layer, :barriers, :max_groups)",
        dict(map_layer=map_layer, barriers=[], max_groups=max_groups),
    ).all()
    return [
        FaceUpdateResult(
            dissolved_faces=sorted(set(r.faces)),
            existing_map_faces=sorted(set(r.existing_map_faces or [])),
            map_layer=r.map_layer,
        )
        for r in rows
    ]


def update_map_face(db: Database, face) -> FaceUpdateResult:
    """Compute the component for a dirty face (compatibility name)."""
    log.info("Updating face %s in layer %s", face.id, face.map_layer)
    return dissolve_component(db, face.id, face.map_layer)


def get_adjacent_faces(db: Database, face_id: int, map_layer: int) -> list[int]:
    """The primitives that dissolve together with `face_id` in `map_layer`."""
    return dissolve_component(db, face_id, map_layer).dissolved_faces


__all__ = [
    "DirtyFace",
    "FaceUpdateResult",
    "dissolve_component",
    "dissolve_layer_groups",
    "update_map_face",
    "get_adjacent_faces",
    "log",
]
