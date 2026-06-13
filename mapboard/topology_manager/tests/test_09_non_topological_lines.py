from .helpers import (
    insert_line,
    map_layer_id,
    n_faces,
    square,
    insert_polygon,
)
from pytest import mark


def test_non_topological_lines(mgr, db):
    """Test that a face with no identifier is created"""

    lyr = map_layer_id(db, "bedrock")

    # Create a non-topological line type
    db.run_sql(
        """
        INSERT INTO {data_schema}.linework_type (id, topological)
        VALUES ('test0', false) ON CONFLICT DO NOTHING;

        INSERT INTO {data_schema}.map_layer_linework_type ("type", map_layer)
        VALUES ('test0', :map_layer) ON CONFLICT DO NOTHING;

        """,
        dict(map_layer=lyr),
    )

    insert_line(
        db,
        square(2, center=(1, 1)),
        type="bedrock",
        map_layer=lyr,
    )

    mgr.update()
    assert n_faces(db) == 1

    # Add a bisecting line
    insert_line(db, ((-1, 1), (3, 1)), type="test0", map_layer=lyr)

    mgr.update()

    # Check that the face is still the same
    assert n_faces(db) == 1


def test_non_topological_polygons(mgr, db):
    """Test that a face with no identifier is created"""

    lyr = map_layer_id(db, "bedrock")

    # Create a non-topological polygon type
    db.run_sql(
        """
        INSERT INTO {data_schema}.polygon_type (id, topological)
        VALUES ('test0', false) ON CONFLICT DO NOTHING;

        INSERT INTO {data_schema}.map_layer_polygon_type ("type", map_layer)
        VALUES ('test0', :map_layer) ON CONFLICT DO NOTHING;

        """,
        dict(map_layer=lyr),
    )

    # Create a basic face
    insert_line(
        db,
        square(2, (1, 1)),
        type="bedrock",
        map_layer=lyr,
    )

    # Add a polygon, theoretically to identify the face
    # but it won't work because the polygon type is non-topological
    insert_polygon(
        db,
        square(1, (1, 1)),
        type="test0",
        map_layer=lyr,
    )

    mgr.update()

    # Check that the face isn't identified
    assert n_faces(db, identified=True) == 0

    # Add another polygon that's actually topological
    insert_polygon(
        db,
        square(0.5, (1, 1)),
        type="basement",
        map_layer=lyr,
    )

    mgr.update()

    assert n_faces(db, identified=True) == 1


@mark.parametrize("line_type", ["watercourse", "bedrock"])
def test_non_topological_layer(db, line_type):
    """Test that layers are correctly identified as non-topological"""

    # Create a non-topological layer
    lyr = db.run_query(
        """
        INSERT INTO {data_schema}.map_layer (name, topological)
        VALUES ('Non-Topological Layer', false)
        RETURNING id;
        """,
    ).scalar()

    # Allow bedrock lines in this layer

    #
    # Insert a line in the non-topological layer, for both a topological and non-topological type
    db.run_sql(
        """
        INSERT INTO {data_schema}.map_layer_linework_type ("type", map_layer)
        VALUES (:type, :map_layer);
        """,
        dict(type=line_type, map_layer=lyr),
    )

    line_id = insert_line(
        db,
        square(2, center=(1, 1)),
        type=line_type,
        map_layer=lyr,
    )

    # Check that the get_topological_map_layers function returns null for this line
    layer = db.run_query(
        """
        SELECT {topo_schema}.get_topological_map_layer(l)
        FROM {data_schema}.linework l
        WHERE l.id = :line_id;
        """,
        {"line_id": line_id},
    ).scalar()

    assert layer is None, "Non-topological layer should not be returned as topological"
