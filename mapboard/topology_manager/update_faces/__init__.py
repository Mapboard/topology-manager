from collections import defaultdict
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


def update_map_face_python(db: Database, face):
    face_id = face.id
    map_layer = face.map_layer

    log.info(f"Updating face {face_id} in layer {map_layer}")
    t0 = perf_counter()

    res = db.run_query(sql("procedures/get-adjacent-faces"), dict(face_id=face_id, map_layer=map_layer)).one()

    t1 = perf_counter()
    log.info(f"Found {len(res.faces)} adjacent faces in {t1 - t0:.2f} seconds ({res.depth} iterations)")

    face = DirtyFace(
        id=face_id,
        map_layer=map_layer,
        adjacent_faces=set(res.faces),
    )
    _update_face(db, face)

    t2 = perf_counter()
    log.info(f"Updated face {face_id} in {t2 - t0:.2f} seconds")


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


def _update_face(db: Database, face: DirtyFace):
    """Update a single face"""

    layer_id = get_topolayer_id(db, "map_face", "topo")

    map_layer = face.map_layer

    # Weed out faces that include the global face
    next_faces = []
    face_list = list(face.adjacent_faces)
    if 0 in face.adjacent_faces:
        unmark_dirty_faces(db, face.map_layer, face_list)
    else:
        next_faces.append(face)

    # Get map faces that contain any of the listed faces in the particular map layer
    # we are looking at.
    existing_map_faces = list(containing_map_faces(db, face_list, face.map_layer))

    n_faces = len(existing_map_faces)
    log.info(f"Found %s existing faces", n_faces)
    if n_faces > 0:
        # For now, we delete any currently overlapping map faces.
        # We could choose to update/merge features instead
        db.run_query(
            """
            DELETE
            FROM {topo_schema}.map_face mf
            WHERE
                id = ANY (
                :map_faces)
            """,
            dict(map_faces=existing_map_faces),
        )

    if 0 not in face.adjacent_faces:
        log.info("Creating new topogeometry for %s faces", len(face_list))
        # We are not dealing with the global face, so we can actually
        # create a new topogeometry

        # Create a topogeometry
        topo_element_array = [[face_id, 3] for face_id in face_list]

        db.run_query(
            """
            WITH
                p0 AS (SELECT :topo_element_array AS topo_elements),
                p1 AS (SELECT
                           topology.createtopogeom(:topo_name, 3, :layer_id, p0.topo_elements) AS topo
                       FROM
                           p0),
                p2 AS (SELECT
                           topo,
                           st_setsrid(topo::geometry, :srid) AS geom
                       FROM
                           p1)
            INSERT
            INTO {topo_schema}.map_face (
                unit_id,
                topo,
                map_layer,
                geometry
            )
            SELECT
                {topo_schema}.unitForArea(p2.geom, :map_layer), p2.topo, :map_layer, p2.geom
            FROM
                p2
            """,
            dict(
                map_layer=face.map_layer,
                topo_element_array=topo_element_array,
                layer_id=layer_id,
            ),
        )

    unmark_dirty_faces(db, map_layer, face_list)

    Timer.add_step("clean")


def unmark_dirty_faces(db, map_layer, faces):
    db.run_sql(
        """DELETE
           FROM {topo_schema}.__dirty_face df
           WHERE
               df.map_layer = :map_layer
             AND (
               id = ANY (
               :dissolved_faces)
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
    return db.run_query(
        """
        SELECT
            f.id
        FROM
            {topo_schema}.relation r
            JOIN {topo_schema}.map_face f
        ON (f.topo).id = r.topogeo_id
            AND r.layer_id = (f.topo).layer_id
        WHERE
            element_id = ANY (
            :faces)
          AND element_type = 3
          AND f.map_layer = :map_layer
        """,
        dict(faces=faces, map_layer=map_layer),
    ).scalars()
