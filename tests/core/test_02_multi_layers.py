from pytest import mark

from mapboard.topology_manager import update
from mapboard.topology_manager.test_helpers import (
    add_linework_type_to_layer,
    insert_line,
    insert_polygon,
    intersecting_faces,
    map_layer_id,
    n_faces,
    n_lines,
    get_face_id,
    point,
    square,
    prepare_geometry,
)
from shapely.geometry import Polygon
from mapboard.topology_manager.commands.update_faces.helpers import get_adjacent_faces

from pytest import fixture


def test_topo_face_no_identifier(db, mgr):
    """Test that a face with no identifier is created"""
    insert_line(
        db,
        square(1, center=(1, 1)),
        type="bedrock",
        map_layer=map_layer_id(db, "bedrock"),
    )
    update()
    assert n_faces(db) == 1


def test_new_layer(mgr, db):
    MapLayer = db.model.test_map_data_map_layer
    lyr = MapLayer(name="Test1", topological=True, parent=None)
    db.session.add(lyr)
    db.session.commit()

    add_linework_type_to_layer(db, lyr.id, "bedrock")

    assert n_faces(db) == 0

    """Test that a new layer can be added"""
    insert_line(
        db,
        square(1, center=(1, 1)),
        type="bedrock",
        map_layer=lyr.id,
    )
    update()
    assert n_faces(db) == 1


@fixture(scope="class")
def layers(db):
    bedrock_id = map_layer_id(db, "bedrock")
    surficial_id = map_layer_id(db, "surficial")

    return {
        "bedrock": bedrock_id,
        "surficial": surficial_id,
    }


@fixture(scope="class")
def basic_polys(mgr, db, layers):
    bedrock_id = layers["bedrock"]
    surficial_id = layers["surficial"]
    # Insert a square
    insert_line(db, square(6, center=(3, 3)), type="bedrock", map_layer=bedrock_id)

    # Insert a smaller square with the surficial type
    insert_line(db, square(2, center=(3, 3)), type="surficial", map_layer=surficial_id)

    # Add identifying units
    insert_polygon(
        db, square(1, center=(3, 3)), type="upper-omkyk", map_layer=bedrock_id
    )

    insert_polygon(db, square(1, center=(3, 3)), type="terrace", map_layer=surficial_id)

    # Solve the topology
    update()


class TestMultiLayers:
    def test_multi_layers(self, db, layers, basic_polys):
        """Insert two overlapping squares that belong to different sub-topologies"""
        # Check if map layer is integer

        # Check that we have two map faces at the center
        res = intersecting_faces(
            db,
            point(3, 3),
        )
        assert len(res) == 2
        has_bedrock = False
        has_surficial = False
        for r in res:
            if r.map_layer == layers["bedrock"]:
                has_bedrock = True
                assert r.area == 36.0
            if r.map_layer == layers["surficial"]:
                has_surficial = True
                assert r.area == 4.0
        assert has_bedrock
        assert has_surficial

    def test_remove_bedrock(self, mgr, db, layers, basic_polys):
        assert n_faces(db) == 2
        assert n_faces(db, map_layer=layers["bedrock"]) == 1

        # This works with savepoints but not nested transactions
        with db.savepoint(rollback="always"):
            _test_internals(mgr, layers)

    def test_remove_bedrock_no_nested_transaction(self, mgr, layers, basic_polys):
        _test_internals(mgr, layers)

    def test_remove_surficial(self, mgr, db, layers, basic_polys):
        assert n_faces(db) == 1
        faces = intersecting_faces(db, point(3, 3))
        assert len(faces) == 1
        assert faces[0].map_layer == layers["surficial"]
        assert n_faces(db, map_layer=layers["surficial"]) == 1
        with db.savepoint(rollback="always"):
            db.run_query(
                "DELETE FROM {data_schema}.linework WHERE map_layer = :map_layer",
                {"map_layer": layers["surficial"]},
            )
            update()
            assert n_faces(db) == 0


def _test_internals(mgr, layers):
    db = mgr.database
    bedrock_id = layers["bedrock"]
    assert n_faces(db) == 2
    db.run_sql(
        "DELETE FROM {data_schema}.linework WHERE map_layer = :map_layer",
        {"map_layer": bedrock_id},
    )

    # TODO: The map face should be deleted during the update process but it isn't
    db.run_sql(
        "DELETE FROM {topo_schema}.map_face WHERE map_layer = :map_layer",
        {"map_layer": bedrock_id},
    )

    # Check that the delete went successfully
    res = db.run_query(
        "SELECT id FROM {topo_schema}.map_face WHERE map_layer = :map_layer",
        {"map_layer": bedrock_id},
    ).fetchall()
    assert len(res) == 0

    # Check that we have actually deleted the bedrock line
    res = db.run_query(
        "SELECT id FROM {data_schema}.linework WHERE map_layer = :map_layer",
        {"map_layer": bedrock_id},
    ).fetchall()
    assert len(res) == 0

    # Delete edge relationships
    # db.run_sql(
    #     "DELETE FROM {topo_schema}.__edge_relation"
    # )
    # db.run_sql(sql("procedures/post-update-contacts"))

    update()
    update()

    # We should also have deleted all edge relationships
    res = db.run_query(
        "SELECT edge_id FROM {topo_schema}.__edge_relation WHERE map_layer = :map_layer",
        {"map_layer": bedrock_id},
    ).fetchall()
    assert len(res) == 0

    # assert n_face_primitives(db) == 1

    center = point(3, 3)

    # Check that we have only one face
    face_id = get_face_id(db, center)
    dissolved = get_adjacent_faces(db, face_id, map_layer=bedrock_id)
    assert 0 in dissolved

    faces = intersecting_faces(db, center)
    assert not any([f.map_layer == bedrock_id for f in faces])

    assert len(faces) == 1

    assert n_faces(db) == 1
    assert n_faces(db, map_layer=layers["surficial"]) == 1

    # Check that we have a single face
    assert n_faces(db) == 1


def test_mixed_edge_winding(mgr, db, layers):
    """Test that faces and edges can be negatively/differently wound"""

    assert n_faces(db) == 0

    # Insert half a square going clockwise
    insert_line(
        db, ((-1, -1), (-1, 1), (1, 1)), type="bedrock", map_layer=layers["bedrock"]
    )

    # Join it with half a square going counter-clockwise
    insert_line(
        db, ((-1, -1), (1, -1), (1, 1)), type="bedrock", map_layer=layers["bedrock"]
    )

    update()

    assert n_faces(db) == 1


@mark.parametrize("incremental", [False, True])
def test_incremental_face_updates(mgr, db, layers, incremental):
    """Test that we can incrementally update faces without deleting them"""

    assert n_faces(db) == 0
    lyr = layers["bedrock"]

    def _insert_lines(ix):
        """Helper function to insert lines in a grid pattern."""
        insert_line(db, [(0, ix), (10, ix)], type="bedrock", map_layer=lyr)
        # Insert vertical lines
        insert_line(db, [(ix, 0), (ix, 10)], type="bedrock", map_layer=lyr)

    for i in range(5):
        _insert_lines(i)

    update(incremental=incremental)

    assert n_faces(db) == 16

    for i in range(6):
        _insert_lines(i + 5)

    update(incremental=incremental)

    assert n_faces(db) == 100
    assert n_lines(db) == 22

    # Delete all but one (outermost) face
    eraser = Polygon(square(9, center=(5, 5)))

    db.run_sql(
        """
        DELETE FROM {data_schema}.linework
        WHERE map_layer = :map_layer AND ST_Intersects(geometry, :eraser)
        """,
        dict(eraser=prepare_geometry(eraser, srid=32612), map_layer=lyr),
    )

    update(incremental=incremental)
    # We should have four lines in the database
    assert n_lines(db) == 4
    assert n_faces(db) == 1
