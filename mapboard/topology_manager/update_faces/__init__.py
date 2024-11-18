from macrostrat.database import Database
from macrostrat.utils import get_logger
from macrostrat.utils.timer import Timer
from pydantic import BaseModel

log = get_logger(__name__)


class DirtyFace(BaseModel):
    id: int
    map_layer: int


def update_map_face_python(db: Database):
    res = db.run_query("SELECT * FROM {topo_schema}.__dirty_face LIMIT 1").one_or_none()
    if res is None:
        return
    face = DirtyFace(id=res.id, map_layer=res.map_layer)
    timer = Timer()
    with timer.context():
        _update_face(db, face)
    log.info(timer.server_timings())


def _update_face(db: Database, face: DirtyFace):
    """Update a single face"""

    layer_id = db.run_query(
        """
    SELECT layer_id
      FROM topology.layer
     WHERE schema_name=:topo_name
       AND table_name='map_face'
       AND feature_column='topo';
    """
    ).scalar()

    # Get adjoining faces
    dissolved_faces = db.run_query(
        """SELECT {topo_schema}.adjacent_faces(:face_id, :map_layer)""",
        {"face_id": face.id, "map_layer": face.map_layer},
    ).scalar()

    Timer.add_step("adjacent_faces")

    # Special case when adjoining the global face
    if dissolved_faces is None:
        dissolved_faces = [face.id]

    is_global = 0 in dissolved_faces
    if is_global:
        unmark_dirty_faces(db, face.map_layer, dissolved_faces)
        return face.id

    # Delete map faces
    db.run_query(
        """
    DELETE FROM {topo_schema}.map_face mf
    WHERE id IN (
        SELECT DISTINCT
        ({topo_schema}.containing_face(
            unnest(:dissolved_faces),
            :map_layer)
        ).id
    )""",
        dict(dissolved_faces=dissolved_faces, map_layer=face.map_layer),
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
