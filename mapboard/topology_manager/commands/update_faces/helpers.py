from collections import defaultdict
from time import perf_counter

from macrostrat.database import Database
from macrostrat.utils import get_logger
from macrostrat.utils.timer import Timer
from pydantic import BaseModel

from ...database import sql

log = get_logger("mapboard.topology_manager.update_faces")


class DirtyFace(BaseModel):
    id: int
    map_layer: int
    adjacent_faces: set[int]


class FaceUpdateResult(BaseModel):
    dissolved_faces: list[int]
    existing_map_faces: list[int]
    map_layer: int


def update_map_face_python(db: Database, face, *, write=False) -> FaceUpdateResult:
    face_id = face.id
    map_layer = face.map_layer
    t0 = perf_counter()

    log.info(f"Updating face {face_id} in layer {map_layer}")

    face_list = get_adjacent_faces(db, face_id, map_layer)

    log.debug("Adjacent faces: %s", face_list)

    # Get map faces that contain any of the listed faces in the particular map layer
    # we are looking at.
    existing_map_faces = list(containing_map_faces(db, face_list, map_layer))

    res = FaceUpdateResult(
        dissolved_faces=face_list,
        existing_map_faces=existing_map_faces,
        map_layer=map_layer,
    )

    if write:
        persist_map_face_updates(db, [res])

    Timer.add_step("clean")

    t2 = perf_counter()
    log.info(f"Updated face {face_id} in {t2 - t0:.2f} seconds")

    return res


def persist_map_face_updates(
    db: Database, updates: list[FaceUpdateResult], *, unmark_dirty: bool = True
):
    """Persist updates to map faces to the database."""
    map_faces_to_delete: set[int] = set()

    for res in updates:
        map_faces_to_delete.update(set(res.existing_map_faces))
        # Dirty faces are stored per-layer, which we might want to change in the future?

    # For now, we delete any currently overlapping map faces.
    # We could choose to update/merge features instead, if we stored changesets
    # for each existing map face.
    if len(map_faces_to_delete) > 0:
        log.info("Deleting %s existing map faces", len(map_faces_to_delete))
        delete_map_faces(db, list(map_faces_to_delete))
    else:
        log.info("No existing map faces to delete")

    creation_stats = defaultdict(int)

    for res in updates:
        if 0 not in res.dissolved_faces:
            create_map_face(db, res.map_layer, res.dissolved_faces)
            creation_stats[res.map_layer] += 1

    log.info(
        "Created %s new map faces in layers: %s",
        sum(creation_stats.values()),
        "\n".join(f"{lyr}: {count}" for lyr, count in creation_stats.items()),
    )

    if unmark_dirty:
        unmark_dirty_faces(db, updates)


def unmark_dirty_faces(db: Database, updates: list[FaceUpdateResult]):
    dissolved_faces_index = defaultdict(list)
    for res in updates:
        dissolved_faces_index[res.map_layer].extend(res.dissolved_faces)
    for lyr, faces in dissolved_faces_index.items():
        _unmark_dirty_faces_for_layer(db, lyr, list(set(faces)))


def persist_map_face_updates_simple(db: Database, updates: list[FaceUpdateResult]):
    """Persist updates to map faces to the database.

    A simple version without batching updates.
    """

    for res in updates:
        if len(res.existing_map_faces) > 0:
            delete_map_faces(db, list(res.existing_map_faces))

        if 0 not in res.dissolved_faces:
            create_map_face(db, res.map_layer, res.dissolved_faces)

        _unmark_dirty_faces_for_layer(db, res.map_layer, res.dissolved_faces)


def delete_map_faces(db: Database, faces: list[int]):
    """Delete map faces"""
    db.run_query(
        """
        DELETE
        FROM {topo_schema}.map_face mf
        WHERE id = ANY (:map_faces)
        """,
        dict(map_faces=faces),
    )


def create_map_face(db: Database, map_layer: int, face_list: list[int]):
    """Create a topogeometry"""
    topo_element_array = [[face_id, 3] for face_id in face_list]
    # log.debug("Creating new topogeometry for %s faces", len(face_list))
    db.run_query(
        sql("procedures/update-faces/insert-face-topogeom"),
        dict(
            map_layer=map_layer,
            topo_element_array=topo_element_array,
        ),
    )


def get_adjacent_faces(db: Database, face_id: int, map_layer: int) -> list[int]:
    """Essentially a python wrapper around the get_adjacent_faces SQL function
    TODO: get adjacent faces for multiple map layers at once.
    """
    t0 = perf_counter()
    res = db.run_query(
        "SELECT * FROM {topo_schema}.get_adjacent_faces_core(:face_id, :map_layer)",
        dict(face_id=face_id, map_layer=map_layer),
    ).one()
    faces = list(set(res.faces))
    t1 = perf_counter()
    log.debug(
        f"Found {len(faces)} adjacent faces in {t1 - t0:.2f} seconds ({res.niter} iterations)"
    )
    return faces


def _unmark_dirty_faces_for_layer(db, map_layer, faces):
    db.run_sql(
        """DELETE
           FROM {topo_schema}.__dirty_face df
           WHERE
               df.map_layer = :map_layer
             AND (id = ANY(:dissolved_faces)
              OR id = 0)
        """,
        dict(map_layer=map_layer, dissolved_faces=faces),
    )


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


def containing_map_faces(db: Database, faces: list[int], map_layer: int) -> list[int]:
    return list(
        db.run_query(
            """
        SELECT
            f.id
        FROM {topo_schema}.map_face f
        JOIN {topo_schema}.relation r
          ON (f.topo).id = r.topogeo_id
          AND r.layer_id = (f.topo).layer_id
        WHERE r.element_id = ANY(:faces)
          AND r.element_type = 3
          AND f.map_layer = :map_layer
        """,
            dict(faces=faces, map_layer=map_layer),
        ).scalars()
    )


def get_face_primitives(db: Database, map_faces: list[int]) -> list[int]:
    return list(
        db.run_query(
            """
            SELECT DISTINCT ON (r.element_id)
                r.element_id
            FROM {topo_schema}.map_face f
            JOIN {topo_schema}.relation r
            ON (f.topo).id = r.topogeo_id
                AND r.layer_id = (f.topo).layer_id
            WHERE f.id = ANY(:map_faces)
              AND r.element_type = 3
            """,
            dict(map_faces=map_faces),
        ).scalars()
    )


def dissolve_adjacent_faces(faces: list[DirtyFace]) -> list[DirtyFace]:
    """Dissolve adjacent faces"""
    grouped_faces = []
    for face in faces:
        for group in grouped_faces:
            # If the face shares an adjacent face with any face in the group, add it to the group
            if (
                group.adjacent_faces & face.adjacent_faces
                and group.map_layer == face.map_layer
            ):
                group.adjacent_faces.update(face.adjacent_faces)
                break
        else:
            grouped_faces.append(face)
    return grouped_faces
