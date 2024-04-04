from pytest import mark
from shapely.geometry import LineString

from ..commands.update import _update, _update_contacts
from .helpers import (
    add_linework_type_to_layer,
    add_polygon_type_to_layer,
    insert_line,
    insert_polygon,
    intersecting_faces,
    map_layer_id,
    point,
    square,
)


class TestNestedLayers:
    def test_insert_multi_layers(self, db):
        """Insert two overlapping models that belong to nested layers"""
        # Check if map layer is integer

        # Wow, this is clunky. Maybe should update the Database module to
        # create a new model storage class.
        MapLayer = db.model.test_map_data_map_layer

        bedrock = db.session.query(MapLayer).filter_by(name="bedrock").one()

        # Create a new "Tectonic Block" map layer
        lyr = MapLayer(name="Tectonic Block", topological=True, parent=None)
        db.session.add(lyr)
        db.session.commit()

        # Mark bedrock as a child of the tectonic block layer
        bedrock.parent = lyr.id
        bedrock.topological = True
        db.session.add(bedrock)
        db.session.commit()

        # Check
        _id = db.run_query(
            "SELECT parent FROM {data_schema}.map_layer WHERE id = :id",
            dict(id=bedrock.id),
        ).scalar()
        assert _id == lyr.id

    def test_create_non_topological_layer(self, db):
        # Create a new "Tectonic Block" map layer
        MapLayer = db.model.test_map_data_map_layer
        lyr = MapLayer(name="Map Region", topological=False, parent=None)
        db.session.add(lyr)
        db.session.commit()

        tectonic_block = (
            db.session.query(MapLayer).filter_by(name="Tectonic Block").one()
        )
        tectonic_block.parent = lyr.id
        db.session.add(tectonic_block)
        db.session.commit()

        res = db.run_query(
            "SELECT * FROM {topo_schema}.parent_map_layers(:id)",
            dict(id=map_layer_id(db, "bedrock")),
        ).fetchall()
        assert len(res) == 2

        res = db.run_query(
            "SELECT * FROM {topo_schema}.parent_map_layers(:id, false)",
            dict(id=map_layer_id(db, "bedrock")),
        ).fetchall()
        assert len(res) == 3

    def test_select_child_layers(self, db):
        res = db.run_query(
            "SELECT * FROM {topo_schema}.child_map_layers(:id)",
            dict(id=map_layer_id(db, "Tectonic Block")),
        ).fetchall()
        assert len(res) == 2
        assert res[1][0] == map_layer_id(db, "bedrock")

        # Selecting non-topological layers should return nothing when
        # the topological flag is set to true, but not when it is false

    @mark.parametrize("topological", [True, False])
    def test_select_child_layers_topological(self, db, topological):
        res = db.run_query(
            "SELECT * FROM {topo_schema}.child_map_layers(:id, :topological)",
            dict(id=map_layer_id(db, "Map Region"), topological=topological),
        ).fetchall()
        if topological:
            assert len(res) == 0
        else:
            assert len(res) == 3
            assert res[2][0] == map_layer_id(db, "bedrock")

    @mark.parametrize("topological", [True, False])
    def test_find_parent(self, db, topological):
        res = db.run_query(
            "SELECT * FROM {topo_schema}.parent_map_layers(:id, :topological)",
            dict(id=map_layer_id(db, "bedrock"), topological=topological),
        ).fetchall()
        if topological:
            assert len(res) == 2
            assert res[0][0] == map_layer_id(db, "bedrock")
            assert res[1][0] == map_layer_id(db, "Tectonic Block")
        else:
            assert len(res) == 3
            assert res[0][0] == map_layer_id(db, "bedrock")
            assert res[1][0] == map_layer_id(db, "Tectonic Block")
            assert res[2][0] == map_layer_id(db, "Map Region")

    def test_insert_child_layers(self, db):
        # Insert a square in the bedrock layer
        # Truncate linework table
        db.run_query("TRUNCATE {data_schema}.linework CASCADE")

        lyr_id = map_layer_id(db, "Tectonic Block")
        add_linework_type_to_layer(db, lyr_id, "bedrock")

        insert_line(
            db,
            square(6, center=(3, 3)),
            type="bedrock",
            map_layer=map_layer_id(db, "Tectonic Block"),
        )

        # Solve the topology
        _update(db)

        n_edges = db.run_query("SELECT count(*) FROM {topo_schema}.edge").scalar()
        assert n_edges == 1

        # Check that the proper record has been added to the __edge_relation table
        res = db.run_query(
            "SELECT * FROM {topo_schema}.__edge_relation",
        ).fetchall()
        assert len(res) == 2
        # The tectonic block layer should have:
        # - Two edges for the outer part of the square
        assert len([r for r in res if r.map_layer == lyr_id]) == 1

    def test_insert_child_layers_with_bisecting_line(self, db):
        """
        Insert a bisecting line in the child layer, starting
        at the geometry wrap point of the enclosing square
        for the absolute minimum number of nodes (2) and edges (3)
         ____.
        |   /|
        | /  |
        .____|
        """
        insert_line(
            db,
            LineString(((0, 0), (6, 6))),
            type="bedrock",
            map_layer=map_layer_id(db, "bedrock"),
        )

        _update_contacts(db)

        # Two nodes
        n_nodes = db.run_query("SELECT count(*) FROM {topo_schema}.node").scalar()
        assert n_nodes == 2

        # We should now have three edges
        n_edges = db.run_query("SELECT count(*) FROM {topo_schema}.edge").scalar()
        assert n_edges == 3

        res = db.run_query(
            "SELECT * FROM {topo_schema}.__edge_relation",
        ).fetchall()
        # The bedrock layer should have:
        # - Two edges inherited from the parent layer
        # - One edge from the bisecting line
        assert len([r for r in res if r.map_layer == map_layer_id(db, "bedrock")]) == 3

        # The tectonic block layer should have:
        # - Two edges for the outer part of the square
        assert (
            len([r for r in res if r.map_layer == map_layer_id(db, "Tectonic Block")])
            == 2
        )

    def test_correct_face_count(self, db):

        # Check that we have three potential faces in the __dirty_face table
        res = dirty_faces(db)
        assert len(res) == 2
        assert len([r for r in res if r.map_layer == map_layer_id(db, "bedrock")]) == 2

        _update(db)

        res = adjacent_faces(db, "Tectonic Block")
        assert len(res) == 2
        for r0 in res:
            assert r0.face_id != 0
            assert 0 not in r0.adjacent
            assert len(r0.adjacent) == 2

        # Ensure that faces aren't marked as adjacent to the global face

        res = adjacent_faces(db, "bedrock")
        v1 = [r.face_id for r in res]
        assert len(res) == 2
        for r0 in res:
            assert r0.face_id != 0
            assert r0.face_id in v1
            assert r0.adjacent is None

        # Get all faces
        res = db.run_query(
            "SELECT map_layer, ST_Area(geometry) area FROM {topo_schema}.map_face"
        ).fetchall()
        assert len(res) == 3

        assert len(dirty_faces(db)) == 0

        # Check that we have two map faces in one location
        res = intersecting_faces(
            db,
            point(2, 3),
        )
        assert len(res) == 2

    def test_add_face_identity(self, db):
        # Create a new polygon type
        PolygonType = db.model.test_map_data_polygon_type
        poly = PolygonType(name="Tectonic Block 1", id="tectonic-block-1")
        db.session.add(poly)
        db.session.commit()
        lyr_id = map_layer_id(db, "Tectonic Block")
        add_polygon_type_to_layer(db, lyr_id, "tectonic-block-1")

        # Insert a polygon in the tectonic block layer
        insert_polygon(
            db,
            square(1, center=(4.5, 2)),
            type="tectonic-block-1",
            map_layer=lyr_id,
        )

        child_id = map_layer_id(db, "bedrock")
        # Insert a polygon in the bedrock layer
        insert_polygon(
            db,
            square(1, center=(4.5, 2)),
            type="lower-omkyk",
            map_layer=child_id,
        )

        # Solve the topology
        _update(db)

        # Check that we have two identified map faces

        res = db.run_query(
            "SELECT map_layer, ST_Area(geometry) area FROM {topo_schema}.map_face WHERE unit_id = :unit_id",
            dict(unit_id="tectonic-block-1"),
        ).fetchall()

        assert len(res) == 1
        assert res[0].map_layer == lyr_id
        assert res[0].area == 36.0

        res = db.run_query(
            "SELECT map_layer, ST_Area(geometry) area FROM {topo_schema}.map_face WHERE unit_id = :unit_id",
            dict(unit_id="lower-omkyk"),
        ).fetchall()

        assert len(res) == 1
        assert res[0].map_layer == child_id
        assert res[0].area == 18.0


def dirty_faces(db):
    return db.run_query(
        "SELECT * FROM {topo_schema}.__dirty_face",
    ).fetchall()


def adjacent_faces(db, map_layer):
    return db.run_query(
        "SELECT face_id, {topo_schema}.adjacent_faces(face_id, :map_layer) adjacent FROM {topo_schema}.face WHERE face_id != 0",
        dict(map_layer=map_layer_id(db, map_layer)),
    ).fetchall()


@mark.parametrize("topological", [False, True])
def test_layer_with_child(
    db,
    topological,
):
    """Test that faces are created for a layer with a child layer."""
    MapLayer = db.model.test_map_data_map_layer

    lyr = MapLayer(name="Layer with child", topological=True, parent=None)
    db.session.add(lyr)
    db.session.commit()

    lyr1 = MapLayer(name="Child layer", topological=topological, parent=lyr.id)

    db.session.add(lyr1)
    db.session.commit()

    add_linework_type_to_layer(db, lyr.id, "bedrock")

    insert_line(db, square(6, center=(3, 3)), type="bedrock", map_layer=lyr.id)

    # Insert a bisecting line in the child layer
    # insert_line(
    #     db, LineString(((3, 0), (3, 6))), type="bedrock", map_layer=bedrock_id
    # )
    # Solve the topology
    _update(db)

    # Check that the proper record has been added to the __edge_relation table
    res = db.run_query(
        "SELECT * FROM {topo_schema}.__edge_relation WHERE map_layer = :parent",
        dict(parent=map_layer_id(db, "Layer with child")),
    ).fetchall()
    assert len(res) == 1

    # Get all faces
    res = db.run_query(
        "SELECT map_layer, ST_Area(geometry) area FROM {topo_schema}.map_face"
    ).fetchall()
    if topological:
        expected_faces = 2
        assert res[0].area == res[1].area
    else:
        expected_faces = 1
        assert res[0].map_layer == map_layer_id(db, "Layer with child")

    assert len(res) == expected_faces

    # Check that we have no map faces at the center
    res = intersecting_faces(
        db,
        point(2, 3),
    )
    assert len(res) == expected_faces
