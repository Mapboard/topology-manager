from pytest import mark
from shapely.geometry import LineString

from ..commands.update import _update
from .helpers import (
    insert_line,
    insert_polygon,
    intersecting_faces,
    map_layer_id,
    n_faces,
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

    def test_find_parent(self, db):
        res = db.run_query(
            "SELECT * FROM {topo_schema}.parent_map_layers(:id)",
            dict(id=map_layer_id(db, "bedrock")),
        ).fetchall()
        assert len(res) == 2
        assert res[0][0] == map_layer_id(db, "bedrock")
        assert res[1][0] == map_layer_id(db, "Tectonic Block")

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

    def test_multi_layers_faces(self, db):

        tectonic_block_id = map_layer_id(db, "Tectonic Block")
        bedrock_id = map_layer_id(db, "bedrock")

        print(tectonic_block_id, bedrock_id)

        # Insert a square in the parent layer
        insert_line(
            db, square(6, center=(3, 3)), type="bedrock", map_layer=tectonic_block_id
        )

        # Insert a bisecting line in the child layer
        insert_line(
            db, LineString(((3, 0), (3, 6))), type="bedrock", map_layer=bedrock_id
        )
        # Solve the topology
        _update(db)

        # Check that we have no map faces at the center
        res = intersecting_faces(
            db,
            point(2, 3),
        )
        assert len(res) == 1
