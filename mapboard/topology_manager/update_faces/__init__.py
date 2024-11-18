from macrostrat.database import Database
from macrostrat.utils import get_logger
from macrostrat.utils.timer import Timer
from pydantic import BaseModel
from functools import lru_cache

log = get_logger(__name__)


class DirtyFace(BaseModel):
    id: int
    map_layer: int
    adjacent_faces: list[int]


def update_map_face_python(db: Database):
    timer = Timer()
    with timer.context():
        res = db.run_query(
            """
            SELECT id,
                map_layer,
                {topo_schema}.adjacent_faces(id, map_layer)
            FROM {topo_schema}.__dirty_face
            LIMIT 1
            """
        ).one_or_none()
        if res is None:
            return

        adjacent = res.adjacent_faces
        if adjacent is None:
            adjacent = [res.id]

        face = DirtyFace(id=res.id, map_layer=res.map_layer, adjacent_faces=adjacent)

        _update_face(db, face)
    log.info(timer.server_timings())


def _update_face(db: Database, face: DirtyFace):
    """Update a single face"""

    layer_id = get_topolayer_id(db, "map_face", "topo")

    # Get adjoining faces
    dissolved_faces = face.adjacent_faces

    Timer.add_step("adjacent_faces")

    is_global = 0 in dissolved_faces
    if is_global:
        unmark_dirty_faces(db, face.map_layer, dissolved_faces)
        return face.id

    map_faces = list(containing_map_faces(db, dissolved_faces, face.map_layer))
    log.info(f"Found {len(map_faces)} containing faces")
    if len(map_faces) > 0:
        # Delete map faces
        db.run_query(
            """
        DELETE FROM {topo_schema}.map_face mf
        WHERE id = ANY(:map_faces)
        """,
            dict(map_faces=map_faces),
        )

    Timer.add_step("delete_existing")

    # Create a topogeometry
    topo_element_array = [[face_id, 3] for face_id in dissolved_faces]

    # Insert the topogeometry
    db.run_query(
        """
    WITH p1 AS (
      SELECT topology.createtopogeom(:topo_name, 3, :layer_id, :topo_element_array) AS topo
    ), p2 AS (
        SELECT
            topo,
            st_setsrid(topo::geometry, :srid) AS geom
        FROM p1
    )
    INSERT INTO {topo_schema}.map_face (unit_id, topo, map_layer, geometry)
    SELECT {topo_schema}.unitForArea(p2.geom, :map_layer), p2.topo, :map_layer, p2.geom
    FROM p2
    """,
        dict(
            map_layer=face.map_layer,
            topo_element_array=topo_element_array,
            layer_id=layer_id,
        ),
    )

    Timer.add_step("insert_new")

    # Remove faces again
    unmark_dirty_faces(db, face.map_layer, dissolved_faces)

    Timer.add_step("clean")


def unmark_dirty_faces(db, map_layer, faces):
    db.run_sql(
        """DELETE FROM {topo_schema}.__dirty_face df
        WHERE df.map_layer = :map_layer
        AND (id = ANY(:dissolved_faces) OR id = 0)
        """,
        dict(map_layer=map_layer, dissolved_faces=faces),
    )


@lru_cache(maxsize=None)
def get_topolayer_id(db: Database, table_name: str, feature_column: str):
    return db.run_query(
        """
    SELECT layer_id
      FROM topology.layer
     WHERE schema_name=:topo_name
       AND table_name=:table_name
       AND feature_column=:feature_column;
    """,
        dict(
            table_name=table_name,
            feature_column=feature_column,
        ),
    ).scalar()


def containing_map_faces(db: Database, faces: list[int], map_layer: int) -> list[int]:
    return db.run_query(
        """
            SELECT f.id
            FROM {topo_schema}.relation r
            JOIN {topo_schema}.map_face f
              ON (f.topo).id = r.topogeo_id
             AND r.layer_id = (f.topo).layer_id
            WHERE element_id = ANY(:faces)
              AND element_type = 3
              AND f.map_layer = :map_layer
            """,
        dict(faces=faces, map_layer=map_layer),
    ).scalars()
