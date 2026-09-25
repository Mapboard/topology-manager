"""CRUD over `map_face` rows at the level of topology primitives.

Each method maps onto one SQL function from
`fixtures/07.1-map-face-elements.sql`, so a single call is atomic: a component is
either fully persisted or not at all, which keeps checkpointed (`--incremental`)
runs safe to resume.
"""

from collections import defaultdict
from typing import Iterable

from macrostrat.database import Database
from macrostrat.database.query import OutputMode

from ...database import sql

from .models import DirtyFace, FaceOverlap, FaceUpdateResult, MapFaceChange


class MapFaceStore:
    def __init__(self, db: Database):
        self.db = db

    # -- queries ---------------------------------------------------------------

    def overlaps(self, faces: list[int], map_layer: int) -> list[FaceOverlap]:
        """Existing map faces holding any of `faces`, with the per-face breakdown."""
        rows = self.db.run_query(
            "SELECT * FROM {topo_schema}.map_face_overlaps(:faces, :map_layer)",
            dict(faces=list(faces), map_layer=map_layer),
        ).all()
        return [FaceOverlap(**row._mapping) for row in rows]

    def containing_map_faces(self, faces: list[int], map_layer: int) -> list[int]:
        """Ids of the map faces in `map_layer` that hold any of `faces`."""
        return [o.map_face for o in self.overlaps(faces, map_layer)]

    def orphaned_relations(self) -> int:
        """Relation rows in the map_face layer that no map face refers to."""
        return self.db.run_query(
            "SELECT {topo_schema}.orphaned_map_face_relations()"
        ).scalar()

    # -- create / delete -------------------------------------------------------

    def create(self, faces: list[int], map_layer: int) -> int:
        """Create a map face over `faces`, resolving identity and geometry."""
        return self.db.run_query(
            "SELECT {topo_schema}.map_face_create(:faces, :map_layer)",
            dict(faces=list(faces), map_layer=map_layer),
        ).scalar()

    def delete_plain(self, map_faces: list[int]) -> int:
        """Delete map faces the way the original pipeline did: a plain DELETE,
        leaving their relation rows for `remove_empty_topogeometries`."""
        if len(map_faces) == 0:
            return 0
        return self.db.run_query(
            """
            WITH gone AS (
                DELETE FROM {topo_schema}.map_face WHERE id = ANY(:map_faces)
                RETURNING id
            )
            SELECT count(*) FROM gone
            """,
            dict(map_faces=list(map_faces)),
        ).scalar()

    def create_plain(
        self, faces: list[int], map_layer: int, *, use_identity_cache: bool = False
    ):
        """Create a map face exactly as the original pipeline did
        (`procedures/update-faces/insert-face-topogeom.sql`)."""
        self.db.run_query(
            sql("procedures/update-faces/insert-face-topogeom"),
            dict(
                map_layer=map_layer,
                faces=list(faces),
                topo_element_array=[[face_id, 3] for face_id in faces],
                use_identity_cache=use_identity_cache,
            ),
        )

    def delete(self, map_faces: list[int]) -> int:
        """Delete map faces, clearing their topogeometries first."""
        if len(map_faces) == 0:
            return 0
        return self.db.run_query(
            "SELECT {topo_schema}.map_face_delete(:map_faces)",
            dict(map_faces=list(map_faces)),
        ).scalar()

    # -- moving primitives -----------------------------------------------------

    def absorb(
        self, faces: list[int], map_layer: int, *, use_identity_cache: bool = False
    ) -> MapFaceChange:
        """Settle a component onto one surviving map face (creating one if needed).
        `use_identity_cache` only once `_layer_identity` holds this layer."""
        return self._change(
            "SELECT * FROM {topo_schema}.map_face_absorb(:faces, :map_layer, :cached)",
            dict(faces=list(faces), map_layer=map_layer, cached=use_identity_cache),
        )

    def release(self, faces: list[int], map_layer: int) -> MapFaceChange:
        """Take `faces` away from every map face of the layer holding them."""
        return self._change(
            "SELECT * FROM {topo_schema}.map_face_release(:faces, :map_layer)",
            dict(faces=list(faces), map_layer=map_layer),
        )

    def replace(
        self,
        faces: list[int],
        map_layer: int,
        *,
        create: bool = True,
        use_identity_cache: bool = False,
    ) -> MapFaceChange:
        """Delete every overlapping map face and (optionally) create a new one."""
        return self._change(
            "SELECT * FROM {topo_schema}.map_face_replace("
            ":faces, :map_layer, :create, :cached)",
            dict(
                faces=list(faces),
                map_layer=map_layer,
                create=create,
                cached=use_identity_cache,
            ),
        )

    def _change(self, query: str, params: dict) -> MapFaceChange:
        row = self.db.run_query(query, params).one()
        data = {k: v for k, v in row._mapping.items()}
        for key in ("added", "removed", "deleted", "shed", "reseeded"):
            if data.get(key) is None:
                data[key] = []
        return MapFaceChange(**data)

    # -- run bookkeeping -------------------------------------------------------

    def unmark_dirty(self, map_layer: int, faces: list[int]):
        """Remove primitives (and the universal face) from `dirty_face` for a layer."""
        self.db.run_sql(
            """DELETE
               FROM {topo_schema}.dirty_face df
               WHERE df.map_layer = :map_layer
                 AND (id = ANY(:faces) OR id = 0)
            """,
            dict(map_layer=map_layer, faces=list(faces)),
            output_mode=OutputMode.NONE,
        )

    def unmark_dirty_components(self, components: Iterable[FaceUpdateResult]):
        by_layer: dict[int, set[int]] = defaultdict(set)
        for comp in components:
            by_layer[comp.map_layer].update(comp.dissolved_faces)
        for layer, faces in by_layer.items():
            self.unmark_dirty(layer, sorted(faces))

    def dirty_faces(self) -> list[DirtyFace]:
        rows = self.db.run_query(
            "SELECT id, map_layer FROM {topo_schema}.dirty_face ORDER BY map_layer, id"
        ).all()
        return [DirtyFace(id=r.id, map_layer=r.map_layer) for r in rows]
