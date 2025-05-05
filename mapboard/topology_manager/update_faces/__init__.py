from time import perf_counter

from macrostrat.database import Database
from macrostrat.utils import get_logger
from macrostrat.utils.timer import Timer
from pydantic import BaseModel
from functools import lru_cache

from ..database import sql

log = get_logger(__name__)


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

    log.info("Adjacent faces: %s", face_list)

    # Get map faces that contain any of the listed faces in the particular map layer
    # we are looking at.
    existing_map_faces = list(containing_map_faces(db, face_list, map_layer))

    n_faces = len(existing_map_faces)
    if write:
        if n_faces > 0:
            # For now, we delete any currently overlapping map faces.
            # We could choose to update/merge features instead
            log.info("Deleting %s existing map faces", n_faces)
            delete_map_faces(db, existing_map_faces)
        else:
            log.info("No existing map faces to delete")

        if 0 not in face_list:
            create_map_face(db, map_layer, face_list)

    unmark_dirty_faces(db, map_layer, face_list)

    Timer.add_step("clean")

    t2 = perf_counter()
    log.info(f"Updated face {face_id} in {t2 - t0:.2f} seconds")

    return FaceUpdateResult(
        dissolved_faces=face_list,
        existing_map_faces=existing_map_faces,
        map_layer=map_layer,
    )


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
    log.info("Creating new topogeometry for %s faces", len(face_list))
    db.run_query(
        sql("procedures/update-faces/insert-face-topogeom"),
        dict(
            map_layer=map_layer,
            topo_element_array=topo_element_array,
        ),
    )


def get_adjacent_faces(db: Database, face_id: int, map_layer: int) -> list[int]:
    t0 = perf_counter()
    res = db.run_query("SELECT * FROM {topo_schema}.get_adjacent_faces_core(:face_id, :map_layer)",
                       dict(face_id=face_id, map_layer=map_layer)).one()
    faces = list(set(res.faces))
    t1 = perf_counter()
    log.info(f"Found {len(faces)} adjacent faces in {t1 - t0:.2f} seconds ({res.niter} iterations)")
    return faces


def unmark_dirty_faces(db, map_layer, faces):
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


@lru_cache(maxsize=None)
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
    return list(db.run_query(
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
    ).scalars())


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
