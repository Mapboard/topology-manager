from .helpers import (
    insert_line,
    map_layer_id,
    n_faces,
    square,
)
from ..commands.update import _update


def test_non_topological_lines(db):
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

    _update(db)
    assert n_faces(db) == 1

    # Add a bisecting line
    insert_line(db, ((-1, 1), (3, 1)), type="test0", map_layer=lyr)

    _update(db)

    # Check that the face is still the same
    assert n_faces(db) == 1
