from pytest import mark

from ..commands.update import _update
from .helpers import (
    add_linework_type_to_layer,
    insert_line,
    insert_polygon,
    intersecting_faces,
    map_layer_id,
    n_faces,
    n_face_primitives,
    point,
    square,
)
from ..database import sql
from ..update_faces import get_adjacent_faces

from pytest import fixture


def test_topo_face_no_identifier(db):
    """Test that a face with no identifier is created"""
    insert_line(
        db,
        square(1, center=(1, 1)),
        type="bedrock",
        map_layer=map_layer_id(db, "bedrock"),
    )
    _update(db)
    assert n_faces(db) == 1


def test_new_layer(db):
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
    _update(db)
    assert n_faces(db) == 1


@fixture(scope="class")
def layers(db):
    bedrock_id = map_layer_id(db, "bedrock")
    surficial_id = map_layer_id(db, "surficial")

    # Insert a square
    insert_line(db, square(6, center=(3, 3)), type="bedrock", map_layer=bedrock_id)

    # Insert a smaller square with the surficial type
    insert_line(
        db, square(2, center=(3, 3)), type="surficial", map_layer=surficial_id
    )

    # Add identifying units
    insert_polygon(
        db, square(1, center=(3, 3)), type="upper-omkyk", map_layer=bedrock_id
    )

    insert_polygon(
        db, square(1, center=(3, 3)), type="terrace", map_layer=surficial_id
    )

    # Solve the topology
    _update(db)

    return {
        "bedrock": bedrock_id,
        "surficial": surficial_id,
    }


class TestMultiLayers:
    def test_multi_layers(self, db, layers):
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

    @mark.skip("This does not work with savepoints")
    def test_remove_bedrock(self, db, layers):
        assert n_faces(db) == 2
        assert n_faces(db, map_layer=layers["bedrock"]) == 1

        # This works with savepoints but not nested transactions
        with db.savepoint(rollback="always"):
            _test_internals(db, layers)

    def test_remove_bedrock_no_nested_transaction(self, db, layers):
        _test_internals(db, layers)

    def test_remove_surficial(self, db, layers):
        assert n_faces(db) == 1
        faces = intersecting_faces(db, point(3, 3))
        assert len(faces) == 1
        assert faces[0].map_layer == layers["surficial"]
        assert n_faces(db, map_layer=layers["surficial"]) == 1
        with db.savepoint(rollback="always"):
            db.run_query("DELETE FROM {data_schema}.linework WHERE map_layer = :map_layer",
                         {"map_layer": layers["surficial"]})
            _update(db)
            assert n_faces(db) == 0


def _test_internals(db, layers):
    bedrock_id = layers["bedrock"]
    assert n_faces(db) == 2
    db.run_sql("DELETE FROM {data_schema}.linework WHERE map_layer = :map_layer", {"map_layer": bedrock_id})

    # TODO: The map face should be deleted during the update process but it isn't
    db.run_sql("DELETE FROM {topo_schema}.map_face WHERE map_layer = :map_layer", {"map_layer": bedrock_id})

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

    _update(db)
    _update(db)

    # We should also have deleted all edge relationships
    res = db.run_query("SELECT edge_id FROM {topo_schema}.__edge_relation WHERE map_layer = :map_layer",
                       {"map_layer": bedrock_id}).fetchall()
    assert len(res) == 0

    # assert n_face_primitives(db) == 1

    center = point(3, 3)

    # Check that we have only one face
    face_id = db.run_query(
        "SELECT face_id FROM {topo_schema}.face_data WHERE ST_Intersects(ST_GetFaceGeometry(:topo_name, face_id), :point) LIMIT 1",
        dict(point=center)).scalar()
    dissolved = get_adjacent_faces(db, face_id, map_layer=bedrock_id)
    assert 0 in dissolved

    faces = intersecting_faces(
        db,
        center
    )
    assert not any([f.map_layer == bedrock_id for f in faces])

    assert len(faces) == 1

    assert n_faces(db) == 1
    assert n_faces(db, map_layer=layers["surficial"]) == 1


def get_topology_state(db):
    """Get the topology state"""
    faces = db.run_query(
        "SELECT * FROM {topo_schema}.face"
    ).all()
    return faces
