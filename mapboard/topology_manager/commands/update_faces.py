from rich.progress import Progress
from typer import Option
from time import perf_counter
from macrostrat.database import Database
from pydantic import BaseModel

from ..database import get_database, sql
from ..utilities import console

count_ = "SELECT count(*)::integer nfaces FROM {topo_schema}.__dirty_face"


def update_faces(
    reset: bool = Option(False, help="Rebuild from scratch"),
    fill_holes: bool = Option(False, help="Try to fill all holes"),
):
    """Update faces"""
    db = get_database()
    _update_faces(db, reset, fill_holes)


def _update_faces(db, reset: bool = False, fill_holes: bool = False):
    t0 = perf_counter()
    if reset:
        db.run_sql(sql("procedures/reset-map_face"))

    if fill_holes:
        db.run_sql(sql("procedures/set-holes-as-dirty"))

    db.run_sql(sql("procedures/prepare-update-face"))

    nfaces = db.run_query(count_).scalar()

    if nfaces == 0:
        console.print("No faces to update")

    t1 = perf_counter()

    console.print(f"Prepared to update {nfaces} faces in {t1 - t0:.2f} seconds")

    t0 = perf_counter()

    with Progress() as progress:
        bar = progress.add_task("Updating faces", total=nfaces)
        while nfaces > 0:
            update_map_face(db)
            next_count = db.run_query(count_).scalar()
            progress.update(bar, completed=nfaces - next_count)
            nfaces = next_count

    t1 = perf_counter()
    console.print(f"Updated {nfaces} faces in {t1 - t0:.2f} seconds")


def update_map_face_plpgsql(db: Database):
    try:
        db.run_query("SELECT {topo_schema}.update_map_face()").one()
    except Exception as e:
        console.print(f"Error updating faces: {e}", style="error")


class DirtyFace(BaseModel):
    id: int
    map_layer: int


def update_map_face(db: Database):
    res = db.run_query("SELECT * FROM {topo_schema}.__dirty_face LIMIT 1").one_or_none()
    if res is None:
        return
    face = DirtyFace(id=res.id, map_layer=res.map_layer)
    _update_face(db, face)


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

    if face.id == 0:
        db.run_sql(
            """
            DELETE
            FROM {topo_schema}.__dirty_face df
            WHERE df.map_layer = :map_layer
              AND df.id = 0;
            """,
            dict(map_layer=face.map_layer),
        )
        return face.id

    # Get adjoining faces
    dissolved_faces = db.run_query(
        """SELECT {topo_schema}.adjacent_faces(:face_id, :map_layer)""",
        {"face_id": face.id, "map_layer": face.map_layer},
    ).scalar()

    # Special case when adjoining the global face
    if dissolved_faces is None:
        dissolved_faces = [face.id]

    is_global = 0 in dissolved_faces
    if is_global:
        print("Adjacent to the global face")
        dissolved_faces = [f for f in dissolved_faces if f != 0]

    # Remove all topogeometries currently in the space
    # Disabled for now

    if is_global:
        db.run_sql(
            """DELETE FROM {topo_schema}.__dirty_face df
            WHERE df.map_layer = :map_layer
            AND (id = ANY(:dissolved_faces) OR id = 0)
            """,
            dict(map_layer=face.map_layer, dissolved_faces=dissolved_faces),
        )
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

    # Remove faces again
    unmark_dirty_faces(db, face.map_layer, dissolved_faces)


def unmark_dirty_faces(db, map_layer, faces):
    db.run_sql(
        """DELETE FROM {topo_schema}.__dirty_face df
        WHERE df.map_layer = :map_layer
        AND (id = ANY(:dissolved_faces) OR id = 0)
        """,
        dict(map_layer=map_layer, dissolved_faces=faces),
    )
