"""Compatibility re-exports for the historical `update_faces.helpers` module.

The implementation now lives in `dissolve`, `store`, and `persist`.
"""

from macrostrat.database import Database

from .dissolve import (
    DirtyFace,
    FaceUpdateResult,
    dissolve_component,
    dissolve_layer_groups,
    get_adjacent_faces,
    log,
    update_map_face,
)
from .persist import persist_map_face_updates
from .store import MapFaceStore

_get_adjacent_faces_core = dissolve_component


def delete_map_faces(db: Database, faces: list[int]):
    """Delete map faces (clearing their topogeometries)."""
    MapFaceStore(db).delete(faces)


def create_map_face(db: Database, map_layer: int, face_list: list[int]) -> int:
    """Create a map face over a list of primitives."""
    return MapFaceStore(db).create(face_list, map_layer)


def containing_map_faces(db: Database, faces: list[int], map_layer: int) -> list[int]:
    return MapFaceStore(db).containing_map_faces(faces, map_layer)


def unmark_dirty_faces(db: Database, updates: list[FaceUpdateResult]):
    MapFaceStore(db).unmark_dirty_components(updates)


def _unmark_dirty_faces_for_layer(db, map_layer, faces):
    MapFaceStore(db).unmark_dirty(map_layer, faces)


def get_topolayer_id(db: Database, table_name: str, feature_column: str):
    return db.run_query(
        """
        SELECT
            layer_id
        FROM
            topology.layer
        WHERE
              schema_name = :topo_name
          AND table_name = :table_name
          AND feature_column = :feature_column;
        """,
        dict(
            table_name=table_name,
            feature_column=feature_column,
        ),
    ).scalar()


__all__ = [
    "DirtyFace",
    "FaceUpdateResult",
    "log",
    "update_map_face",
    "persist_map_face_updates",
    "dissolve_layer_groups",
    "unmark_dirty_faces",
    "delete_map_faces",
    "create_map_face",
    "get_adjacent_faces",
    "containing_map_faces",
    "get_topolayer_id",
]
