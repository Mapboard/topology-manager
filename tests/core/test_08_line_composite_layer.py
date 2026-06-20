"""Tests to ensure efficient calculations of map faces with overlays."""

from pytest import fixture
from addict import Dict

from mapboard.topology_manager import update
from ..helpers import (
    add_linework_type_to_layer,
    create_composite_layer,
    add_polygon_type_to_layer,
    create_map_layer,
    insert_line,
    insert_polygon,
    n_lines,
    n_face_primitives,
    n_faces,
    square,
)


@fixture()
def db(base_db, pytestconfig):
    base_db.automap(schemas=["test_map_data"])

    commit = pytestconfig.getoption("--commit")
    if commit:
        yield base_db
        return

    with base_db.transaction(rollback="always"):
        yield base_db


@fixture()
def layers(db):
    """Fixture to create a composite layer for testing."""
    db.run_sql(
        """
        INSERT INTO {data_schema}.polygon_type (id)
        VALUES ('unit0'), ('none') ON CONFLICT DO NOTHING;
        """
    )

    _layers = Dict(
        {
            "basement": create_map_layer(db, "basement"),
            "surficial": create_map_layer(db, "surficial"),
            "external": create_map_layer(db, "external"),
        }
    )

    # Add a linework types and polygon types
    for lyr in [
        _layers.basement,
        _layers.surficial,
        _layers.external,
    ]:
        add_linework_type_to_layer(db, lyr, "bedrock")
        add_polygon_type_to_layer(db, lyr, "none")
        add_polygon_type_to_layer(db, lyr, "unit0")

    # Create a composite layer placeholder
    _layers["composite"] = create_composite_layer(
        db,
        "composite",
        [_layers.basement, _layers.surficial],
    )

    return _layers


def test_lines_in_composite_layer(layers, mgr, db):
    """Test that lines in composite layer are updated correctly."""
    mgr.database = db
    insert_line(
        db,
        square(2, (0, 0)),
        type="bedrock",
        map_layer=layers.surficial,
    )
    # Insert a polygon to identify the face
    insert_polygon(db, square(1, (0, 0)), map_layer=layers.surficial, type="unit0")

    # Create a slightly offset face in the basement layer
    insert_line(db, square(2, (1, 1)), map_layer=layers.basement, type="bedrock")
    insert_polygon(db, square(1, (1, 1)), map_layer=layers.basement, type="unit0")

    # Update faces
    update(composite_layers=True)

    # Check that the composite layer has two faces
    assert n_face_primitives(db) == 3
    assert n_faces(db, map_layer=layers.basement) == 1

    def check_layer(layer, area=None, length=None, covered=False):
        """Helper function to check the number of faces and area/length."""
        assert n_faces(db, map_layer=layer) == 1
        args = dict(
            map_layer=layers.composite,
            source_layer=layer,
            covered=covered,
        )
        if area is not None:
            _area = _get_area(db, **args)
        assert _area == area, f"Expected area {area}, got {_area}"
        if length is not None:
            _len = _get_length(db, **args)
            assert _len == length, f"Expected length {length}, got {_len}"

    check_layer(layers.surficial, area=4.0, length=8.0)
    check_layer(layers.basement, area=3.0, length=6.0)
    check_layer(layers.basement, area=1.0, length=2.0, covered=True)

    assert (
        _get_area(db, map_layer=layers.composite, source_layer=layers.surficial) == 4.0
    )

    # Check the length of the lines in the composite layer
    assert (
        _get_length(db, map_layer=layers.composite, source_layer=layers.surficial)
        == 8.0
    )

    assert (
        _get_length(db, map_layer=layers.composite, source_layer=layers.basement) == 6.0
    )
    assert (
        _get_length(
            db, map_layer=layers.composite, source_layer=layers.basement, covered=True
        )
        == 2.0
    )

    assert (
        _get_area(db, map_layer=layers.composite, source_layer=layers.basement) == 3.0
    )


def test_non_topological_lines_in_composite_layer(layers, mgr, db):
    """Test that non topological lines in the composite layer are updated correctly"""
    mgr.database = db
    # Create a non-topological line type
    db.run_sql(
        """
        INSERT INTO {data_schema}.linework_type (id, topological)
        VALUES ('non-topological', false);
        """
    )

    for lyr in [layers.basement, layers.composite]:
        add_linework_type_to_layer(db, lyr, "non-topological")
    # Insert a non-topological line in the basement layer

    insert_line(
        db,
        square(2, (0, 0)),
        type="non-topological",
        map_layer=layers.basement,
    )

    update(composite_layers=True)
    # Check that the line is in the composite layer
    assert n_lines(db, map_layer=layers.composite) == 1
    assert n_lines(db, map_layer=layers.basement) == 1

    # Remove the line from the basement layer
    db.run_query(
        """
        DELETE FROM {data_schema}.linework
        WHERE map_layer = :layer
        """,
        dict(layer=layers.basement),
    )

    update(composite_layers=True)

    # Check that the line is removed from the composite layer
    assert n_lines(db, map_layer=layers.composite) == 0
    assert n_lines(db, map_layer=layers.basement) == 0


def test_lines_removed_from_composite_layer(layers, mgr, db):
    """Test that lines in composite layer are updated correctly"""
    mgr.database = db
    _id = insert_line(
        db,
        square(2, (0, 0)),
        type="bedrock",
        map_layer=layers.surficial,
    )
    update(composite_layers=True)
    # Check that we have a single face primitive
    assert n_face_primitives(db) == 1

    insert_line(db, square(2, (1, 1)), map_layer=layers.basement, type="bedrock")

    # Update faces
    update(composite_layers=True)

    # Check that the composite layer has two faces
    assert n_face_primitives(db) == 3
    assert n_faces(db, map_layer=layers.basement) == 1
    assert n_faces(db, map_layer=layers.surficial) == 1

    assert n_lines(db, map_layer=layers.composite) == 2

    # Now move the line from the basement layer to the external layer, which is not part of the composite
    db.run_query(
        """
        UPDATE {data_schema}.linework
        SET map_layer = :new_layer
        WHERE id = :id
        """,
        dict(new_layer=layers.external, id=_id),
    )

    assert n_lines(db, map_layer=layers.external) == 1

    update(composite_layers=True)

    assert n_lines(db, map_layer=layers.composite) == 1


def test_non_topological_lines_removed_from_composite_layer(layers, mgr, db):
    """Non-topological lines should be carried into composite layers"""
    mgr.database = db
    # Create a non-topological line type
    db.run_sql(
        """
        INSERT INTO {data_schema}.linework_type (id, topological)
        VALUES ('non-topological', false);
        """
    )

    for lyr in [layers.basement, layers.composite]:
        add_linework_type_to_layer(db, lyr, "non-topological")
    # Insert a non-topological line in the basement layer

    line_id = insert_line(
        db,
        ((0, 0), (2, 2)),
        type="non-topological",
        map_layer=layers.basement,
    )

    update(composite_layers=True)
    # Check that the line is in the composite layer
    assert n_lines(db, map_layer=layers.composite) == 1
    _count = db.run_query(
        "SELECT count(*) FROM {data_schema}.linework WHERE source_id = :id AND map_layer = :layer",
        dict(id=line_id, layer=layers.composite),
    ).scalar()
    assert _count == 1


def _get_length(db, *, map_layer=None, source_layer=None, covered=False):
    """Get the total length of lines in a composite layer."""
    sql = """
    SELECT sum(ST_Length(geometry))
    FROM {data_schema}.linework
    WHERE map_layer = :map_layer
      AND source_layer = :source_layer
    """

    if covered:
        sql += " AND covered"
    else:
        sql += " AND NOT covered"

    return db.run_query(
        sql,
        dict(map_layer=map_layer, source_layer=source_layer),
    ).scalar()


def _get_area(db, *, map_layer, source_layer, covered=False):
    """Get the total area of polygons in a composite layer."""
    sql = """
          SELECT sum(ST_Area(geometry))
          FROM {topo_schema}.map_face
          WHERE map_layer = :map_layer
            AND source_layer = :source_layer
          """
    if covered:
        sql = """
            WITH base_area AS (
                SELECT sum(ST_Area(geometry)) AS area
                FROM {topo_schema}.map_face
                WHERE map_layer = :source_layer
            )
            SELECT (SELECT area FROM base_area) - sum(ST_Area(geometry))
            FROM {topo_schema}.map_face
            WHERE map_layer = :map_layer
              AND source_layer = :source_layer
        """

    return db.run_query(
        sql,
        dict(map_layer=map_layer, source_layer=source_layer),
    ).scalar()
