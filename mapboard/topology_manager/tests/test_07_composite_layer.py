"""Tests to ensure efficient calculations of map faces with overlays."""

from addict import Dict
from pytest import fixture

from .helpers import (
    add_linework_type_to_layer,
    add_polygon_type_to_layer,
    create_composite_layer,
    create_grid,
    create_map_layer,
    insert_line,
    insert_polygon,
    n_face_primitives,
    n_faces,
    square,
)
from ..commands.update import _update
from ..commands.update_contacts import _update_contacts
from ..commands.update_faces import n_dirty_faces

grid_count_on_each_axis = 7


@fixture(scope="class")
def layers(db):
    return create_composite_layers(db)


class TestCompositeLayers:
    """Composite layers should be reproducible from a bounded dataset."""

    def test_create_bedrock_grid(self, ctx, db, layers):
        assert n_faces(db) == 0
        assert n_face_primitives(db) == 0

        build_bedrock_grid(ctx, layers)

        assert n_faces(db) == grid_count_on_each_axis**2
        assert n_face_primitives(db) == grid_count_on_each_axis**2

    def test_add_parent_layer(self, ctx, db, layers):
        build_bedrock_grid(ctx, layers)
        add_parent_layer(ctx, layers)

        assert n_face_primitives(db) == grid_count_on_each_axis**2 + 1
        assert n_faces(db) == grid_count_on_each_axis**2 + 2

    def test_composite_layers(self, ctx, db, layers):
        """Test the erasure and consolidation of faces."""

        # Delete lines that cover the bottom right corner of the child layer
        # while leaving other lines intact. This should remove 4 faces from the
        db.run_sql(
            """
            UPDATE {data_schema}.linework
            SET geometry = ST_Difference(geometry, ST_MakeEnvelope(0.1, 0.1, 1.98, 1.98, :srid))
            WHERE TYPE = 'bedrock'
              AND map_layer = :child_lyr
            """,
            dict(child_lyr=layers.paleozoic),
        )

        _update(ctx, composite_layers=False)

        n_child_faces = grid_count_on_each_axis**2 + 1 - 4 + 1

        assert n_faces(db, map_layer=layers.paleozoic) == n_child_faces
        assert n_faces(db, map_layer=layers["tectonic-block"]) == 1

        assert n_faces(db) == grid_count_on_each_axis**2 + 2 - 4 + 1

        expected_n_primitives = grid_count_on_each_axis**2 - 3 + 1

        assert n_face_primitives(db) == expected_n_primitives

        _update(ctx, composite_layers=True)
        # Check that the composite layer has been updated correctly
        assert n_face_primitives(db) == expected_n_primitives
        assert n_faces(db, map_layer=layers.paleozoic) == n_child_faces

        # Composite layers should not have faces as they haven't been identified yet
        assert n_faces(db, map_layer=layers.composite) == 0

        # Identify faces in the unit layer
        for i in range(grid_count_on_each_axis):
            for j in range(grid_count_on_each_axis):
                insert_polygon(
                    db,
                    square(0.2, (i + 0.5, j + 0.5)),
                    type="unit0",
                    map_layer=layers.paleozoic,
                )

        insert_polygon(
            db,
            square(0.2, (-0.5, -0.5)),
            type="unit0",
            map_layer=layers.paleozoic,
        )

        _update(ctx, composite_layers=True)
        assert n_faces(db, map_layer=layers.composite) == n_child_faces

    def test_create_surficial_face(self, ctx, db, layers):
        """Create a surficial face that overlaps with the bedrock layer."""
        insert_line(
            db, square(4, (4.5, 4.5)), type="bedrock", map_layer=layers.surficial
        )

        # This square will overlap the bedrock layer. It should cover nine entire faces in the bedrock layer,
        # as well as part of 14 other faces.

        # The composite layer should have eight bedrock faces that have areas < 1.0

        # Solve the topology
        _update(ctx, composite_layers=True)

        _bedrock_count = grid_count_on_each_axis**2 + 1 - 4 + 1

        # Check that we have created a new face in the surficial layer
        assert n_faces(db, map_layer=layers.surficial) == 1
        assert n_faces(db, map_layer=layers.paleozoic) == _bedrock_count
        # The new surficial face should not be included in the composite layer yet
        assert n_faces(db, map_layer=layers.composite) == _bedrock_count

        insert_polygon(
            db, square(1, (4.5, 4.5)), type="unit0", map_layer=layers.surficial
        )

        _update(ctx, composite_layers=True)

        assert n_faces(db, map_layer=layers.composite) == _bedrock_count - 9 + 1

    def test_remove_surficial_face(self, ctx, db, layers):

        # Remove the identifier from the surficial face to ensure it is not included in the composite layer
        db.run_sql(
            "UPDATE {data_schema}.polygon SET type='none' WHERE map_layer = :lyr",
            dict(lyr=layers.surficial),
        )

        _update(ctx, composite_layers=True)

        uid = db.run_query(
            "SELECT unit_id FROM {topo_schema}.map_face WHERE map_layer = :lyr",
            dict(lyr=layers.surficial),
        ).scalar()
        assert uid == "none"

        bedrock_count = grid_count_on_each_axis**2 + 1 - 4 + 1
        assert n_faces(db, map_layer=layers.paleozoic) == bedrock_count
        assert n_faces(db, map_layer=layers.surficial) == 1
        assert (
            n_faces(db, map_layer=layers.composite, source_layer=layers.surficial) == 0
        )
        assert (
            n_faces(db, map_layer=layers.composite, source_layer=layers.paleozoic)
            == bedrock_count
        )
        assert n_faces(db, map_layer=layers.composite) == bedrock_count

    def test_remove_surficial_face_and_add_smaller_one(self, ctx, db, layers):
        build_bedrock_overlay_state(ctx, layers)
        add_surficial_face(ctx, layers)

        db.run_sql(
            """
                DELETE FROM {data_schema}.linework
                WHERE map_layer = :lyr;

                DELETE FROM {data_schema}.polygon
                WHERE map_layer = :lyr;
                """,
            dict(lyr=layers.surficial),
        )

        db.run_sql(
            """
            DELETE FROM {data_schema}.linework
            WHERE map_layer = :lyr;
            """,
            dict(lyr=layers.paleozoic),
        )

        _update(ctx, composite_layers=True)
        assert n_faces(db, map_layer=layers.paleozoic) == 1
        assert n_faces(db, map_layer=layers.composite) == 1

        create_grid(db, layers.paleozoic, cells_on_each_axis=grid_count_on_each_axis)

        _update(ctx, composite_layers=True)

        bedrock_count = grid_count_on_each_axis**2 + 1
        assert n_faces(db, map_layer=layers.composite) == bedrock_count
        assert n_faces(db, map_layer=layers.surficial) == 0
        assert n_dirty_faces(db) == 0

        insert_line(
            db, square(5, (3.1, 3.1)), type="bedrock", map_layer=layers.surficial
        )

        _update_contacts(ctx)

        assert n_dirty_faces(db, map_layer=layers.surficial) > 0
        assert n_faces(db, map_layer=layers.surficial) == 0

        _update(ctx, composite_layers=True)

        assert n_dirty_faces(db) == 0
        assert n_faces(db, map_layer=layers.surficial) == 1
        assert n_faces(db, map_layer=layers.composite) == bedrock_count

        insert_polygon(
            db, square(1, (4.1, 4.1)), type="unit0", map_layer=layers.surficial
        )

        _update(ctx, composite_layers=True)

        uid = db.run_query(
            """
            SELECT unit_id
            FROM {topo_schema}.map_face
            WHERE map_layer = :lyr
            """,
            dict(lyr=layers.surficial),
        ).scalar()
        assert uid == "unit0"

        assert n_faces(db, map_layer=layers.surficial) == 1
        assert n_faces(db, map_layer=layers.cenozoic) == 0
        assert n_faces(db, map_layer=layers["tectonic-block"]) == 1
        assert n_faces(db, map_layer=layers.paleozoic) == bedrock_count

        layers_counts = {
            layers.paleozoic: bedrock_count - 16,
            layers.surficial: 1,
            layers.cenozoic: 0,
            layers["tectonic-block"]: 0,
        }

        for layer, count in layers_counts.items():
            assert n_faces(db, map_layer=layers.composite, source_layer=layer) == count

        assert n_faces(db, map_layer=layers.composite) == bedrock_count - 16 + 1

def test_add_surficial_face_standalone(ctx, db, layers):
    assert n_faces(db, map_layer=layers.surficial) == 0
    insert_line(db, square(5, (3.1, 3.1)), type="bedrock", map_layer=layers.surficial)
    _update(ctx, composite_layers=True)
    assert n_faces(db, map_layer=layers.surficial) == 1

def identify_faces(db, ctx, *layers, unit_id="unit0"):
    db.run_sql(
        """
        UPDATE {topo_schema}.map_face
        SET unit_id = :unit_id
        WHERE map_layer = ANY(:layers)
        """,
        dict(
            layers=layers,
            unit_id=unit_id,
        ),
    )
    _update(ctx, composite_layers=True)



def _insert_identified(db, size, center, *, map_layer=None):
    id = insert_line(db, square(size, center), type="bedrock", map_layer=map_layer)
    insert_polygon(
        db,
        square(0.2, center),
        type="unit0",
        map_layer=map_layer,
    )
    return id


def create_composite_layers(db):
    grandparent_lyr = create_map_layer(db, "map-area")
    parent_lyr = create_map_layer(db, "tectonic-block", parent=grandparent_lyr)

    db.run_sql(
        """
        INSERT INTO {data_schema}.polygon_type (id)
        VALUES ('unit0'), ('none') ON CONFLICT DO NOTHING;
        """
    )

    _layers = Dict(
        {
            "map-area": grandparent_lyr,
            "tectonic-block": parent_lyr,
            "paleozoic": create_map_layer(db, "paleozoic", parent=parent_lyr),
            "cenozoic": create_map_layer(db, "cenozoic"),
            "surficial": create_map_layer(db, "surficial"),
        }
    )

    for lyr in [
        _layers["tectonic-block"],
        _layers.paleozoic,
        _layers.cenozoic,
        _layers.surficial,
    ]:
        add_linework_type_to_layer(db, lyr, "bedrock")
        add_polygon_type_to_layer(db, lyr, "none")
        add_polygon_type_to_layer(db, lyr, "unit0")

    _layers["composite"] = create_composite_layer(
        db,
        "composite",
        [_layers.paleozoic, _layers.cenozoic, _layers.surficial],
        parent=_layers["map-area"],
    )

    return _layers


def build_bedrock_grid(ctx, layers):
    create_grid(
        ctx.database, layers.paleozoic, cells_on_each_axis=grid_count_on_each_axis
    )
    _update(ctx, composite_layers=False)


def add_parent_layer(ctx, layers):
    _max = grid_count_on_each_axis + 1
    insert_line(
        ctx.database,
        [(-1, -1), (_max, -1), (_max, _max), (-1, _max), (-1, -1)],
        type="bedrock",
        map_layer=layers["tectonic-block"],
    )
    _update(ctx, composite_layers=False)


def damage_child_grid(ctx, layers):
    db = ctx.database
    db.run_sql(
        """
        UPDATE {data_schema}.linework
        SET geometry = ST_Difference(
            geometry,
            ST_MakeEnvelope(0.1, 0.1, 1.98, 1.98, :srid)
        )
        WHERE TYPE = 'bedrock'
          AND map_layer = :child_lyr
        """,
        dict(child_lyr=layers.paleozoic),
    )
    _update(ctx, composite_layers=False)
    n_child_faces = grid_count_on_each_axis**2 + 1 - 4 + 1
    expected_n_primitives = grid_count_on_each_axis**2 - 3 + 1
    return n_child_faces, expected_n_primitives


def build_bedrock_overlay_state(ctx, layers):
    build_bedrock_grid(ctx, layers)
    add_parent_layer(ctx, layers)
    return damage_child_grid(ctx, layers)


def add_surficial_face(ctx, layers):
    """Create a surficial face that overlaps with the bedrock layer."""
    db = ctx.database
    insert_line(db, square(4, (4.5, 4.5)), type="bedrock", map_layer=layers.surficial)
    _update(ctx, composite_layers=True)
    insert_polygon(db, square(1, (4.5, 4.5)), type="unit0", map_layer=layers.surficial)
    _update(ctx, composite_layers=True)
