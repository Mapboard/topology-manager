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
        lyr = MapLayer(name="Tectonic Block")
        db.session.add(lyr)
        db.session.commit()

        # Mark bedrock as a child of the tectonic block layer
        bedrock.parent = lyr.id
        db.session.add(bedrock)
        db.session.commit()

        # Check
        _id = db.run_query(
            "SELECT parent FROM {data_schema}.map_layer WHERE id = :id",
            dict(id=bedrock.id),
        ).scalar()
        assert _id == lyr.id

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
        assert len(res) == 2
