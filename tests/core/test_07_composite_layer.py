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
from mapboard.topology_manager.commands.update_faces import n_dirty_faces

grid_count_on_each_axis = 7


@fixture(scope="class")
def layers(db):
    return create_composite_layers(db)


class TestCompositeLayers:
    """Composite layers should be reproducible from a bounded dataset."""

    def test_create_bedrock_grid(self, mgr, db, layers):
        assert n_faces(db) == 0
        assert n_face_primitives(db) == 0

        build_bedrock_grid(mgr, layers)

        assert n_faces(db) == grid_count_on_each_axis**2
        assert n_face_primitives(db) == grid_count_on_each_axis**2

    def test_add_parent_layer(self, mgr, db, layers):
        build_bedrock_grid(mgr, layers)
        add_parent_layer(mgr, layers)

        assert n_face_primitives(db) == grid_count_on_each_axis**2 + 1
        assert n_faces(db) == grid_count_on_each_axis**2 + 2

    def test_composite_layers(self, mgr, db, layers):
        """Test the erasure and consolidation of faces."""

        db.run_sql(
            """
            UPDATE {data_schema}.linework
            SET geometry = ST_Difference(geometry, ST_MakeEnvelope(0.1, 0.1, 1.98, 1.98, :srid))
            WHERE TYPE = 'bedrock'
              AND map_layer = :child_lyr
            """,
            dict(child_lyr=layers.paleozoic),
        )

        mgr.update(composite_layers=False)

        n_child_faces = grid_count_on_each_axis**2 + 1 - 4 + 1

        assert n_faces(db, map_layer=layers.paleozoic) == n_child_faces
        assert n_faces(db, map_layer=layers["tectonic-block"]) == 1
        assert n_faces(db) == grid_count_on_each_axis**2 + 2 - 4 + 1

        expected_n_primitives = grid_count_on_each_axis**2 - 3 + 1
        assert n_face_primitives(db) == expected_n_primitives

        mgr.update(composite_layers=True)
        assert n_face_primitives(db) == expected_n_primitives
        assert n_faces(db, map_layer=layers.paleozoic) == n_child_faces
        assert n_faces(db, map_layer=layers.composite) == 0

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

        mgr.update(composite_layers=True)
        assert n_faces(db, map_layer=layers.composite) == n_child_faces

    def test_create_surficial_face(self, mgr, db, layers):
        """Create a surficial face that overlaps with the bedrock layer."""
        insert_line(
            db, square(4, (4.5, 4.5)), type="bedrock", map_layer=layers.surficial
        )

        mgr.update(composite_layers=True)

        _bedrock_count = grid_count_on_each_axis**2 + 1 - 4 + 1

        assert n_faces(db, map_layer=layers.surficial) == 1
        assert n_faces(db, map_layer=layers.paleozoic) == _bedrock_count
        assert n_faces(db, map_layer=layers.composite) == _bedrock_count

        insert_polygon(
            db, square(1, (4.5, 4.5)), type="unit0", map_layer=layers.surficial
        )

        mgr.update(composite_layers=True)

        assert n_faces(db, map_layer=layers.composite) == _bedrock_count - 9 + 1

    def test_remove_surficial_face(self, mgr, db, layers):
        db.run_sql(
            "UPDATE {data_schema}.polygon SET type='none' WHERE map_layer = :lyr",
            dict(lyr=layers.surficial),
        )

        mgr.update(composite_layers=True)

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

    def test_remove_surficial_face_and_add_smaller_one(self, mgr, db, layers):
        build_bedrock_overlay_state(mgr, layers)
        add_surficial_face(mgr, layers)

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

        mgr.update(composite_layers=True)
        assert n_faces(db, map_layer=layers.paleozoic) == 1
        assert n_faces(db, map_layer=layers.composite) == 1

        create_grid(db, layers.paleozoic, cells_on_each_axis=grid_count_on_each_axis)

        mgr.update(composite_layers=True)

        bedrock_count = grid_count_on_each_axis**2 + 1
        assert n_faces(db, map_layer=layers.composite) == bedrock_count
        assert n_faces(db, map_layer=layers.surficial) == 0
        assert n_dirty_faces(db) == 0

        insert_line(
            db, square(5, (3.1, 3.1)), type="bedrock", map_layer=layers.surficial
        )

        mgr.update_contacts()

        assert n_dirty_faces(db, map_layer=layers.surficial) > 0
        assert n_faces(db, map_layer=layers.surficial) == 0

        mgr.update(composite_layers=True)

        assert n_dirty_faces(db) == 0
        assert n_faces(db, map_layer=layers.surficial) == 1
        assert n_faces(db, map_layer=layers.composite) == bedrock_count

        insert_polygon(
            db, square(1, (4.1, 4.1)), type="unit0", map_layer=layers.surficial
        )

        mgr.update(composite_layers=True)

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


def identify_faces(db, mgr, *layers, unit_id="unit0"):
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
    mgr.update(composite_layers=True)


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


def build_bedrock_grid(mgr, layers):
    create_grid(mgr.db, layers.paleozoic, cells_on_each_axis=grid_count_on_each_axis)
    mgr.update(composite_layers=False)


def add_parent_layer(mgr, layers):
    _max = grid_count_on_each_axis + 1
    insert_line(
        mgr.db,
        [(-1, -1), (_max, -1), (_max, _max), (-1, _max), (-1, -1)],
        type="bedrock",
        map_layer=layers["tectonic-block"],
    )
    mgr.update(composite_layers=False)


def damage_child_grid(mgr, layers):
    db = mgr.db
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
    mgr.update(composite_layers=False)
    n_child_faces = grid_count_on_each_axis**2 + 1 - 4 + 1
    expected_n_primitives = grid_count_on_each_axis**2 - 3 + 1
    return n_child_faces, expected_n_primitives


def build_bedrock_overlay_state(mgr, layers):
    build_bedrock_grid(mgr, layers)
    add_parent_layer(mgr, layers)
    return damage_child_grid(mgr, layers)


def add_surficial_face(mgr, layers):
    """Create a surficial face that overlaps with the bedrock layer."""
    db = mgr.db
    insert_line(db, square(4, (4.5, 4.5)), type="bedrock", map_layer=layers.surficial)
    mgr.update(composite_layers=True)
    insert_polygon(db, square(1, (4.5, 4.5)), type="unit0", map_layer=layers.surficial)
    mgr.update(composite_layers=True)
