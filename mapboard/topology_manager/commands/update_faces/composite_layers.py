from ..update import _update
from .helpers import FaceUpdateResult, log
from ...database import sql
from psycopg2.sql import Identifier
from functools import lru_cache

def update_composite_layer(db, map_layer: int) -> FaceUpdateResult:
    layers = get_composite_layers(db, map_layer)
    return _update_composite_layer(db, map_layer, layers)


def _update_composite_layer(db, map_layer: int, layers: list[int]) -> FaceUpdateResult:
    """Update a composite layer by merging faces from the specified layers."""

    # Ensure that the composite layer has all the necessary linework/polygon types
    add_composite_layer_types(db, map_layer, layers)

    # We can now trust that the composite layer is populated for each constituent layer.
    # For now we set all faces as dirty...

    db.run_sql(
        "DELETE FROM {topo_schema}.map_face WHERE map_layer = :map_layer",
        dict(map_layer=map_layer),
    )

    _update(db)

    # We may need to add the entire geometry of any dirty face to the dirty faces for the composite layer.

    # Insert the topmost layer's faces into the composite layer
    reversed_layers = list(reversed(layers))

    # Get intersecting with dirty map faces...
    overlay_layers = []
    for layer in reversed_layers:
        log.info("Updating composite layer with faces from layer %s", layer)
        ids = db.run_query(
            sql("procedures/update-faces/update-composite-face-elements"),
            dict(
                map_layer=layer,
                overlay_layers=overlay_layers,
                composite_layer=map_layer,
            ),
        ).scalars()
        _n_faces = len(list(ids))
        overlay_layers.append(layer)
        log.info("Inserted %s map faces from layer %s", _n_faces, layer)


def add_composite_layer_types(db, map_layer: int, layers: list[int]):
    """Add linework and polygon types from the specified layers to the composite layer."""
    for feature_type in ["linework", "polygon"]:
        table = Identifier(
            db.instance_params["data_schema_name"], f"map_layer_{feature_type}_type"
        )
        db.run_sql(
            """
            WITH source_types AS (
                SELECT "type"
                FROM {table}
                WHERE map_layer = ANY (:layers)
            ), a AS (
                DELETE FROM {table}
                WHERE map_layer = :map_layer
                AND "type" NOT IN (SELECT * FROM source_types)
            )
            INSERT INTO {table} (map_layer, "type")
            SELECT :map_layer, "type"
            FROM source_types
            ON CONFLICT DO NOTHING;
            """,
            dict(
                table=table,
                map_layer=map_layer,
                layers=layers,
            ),
        )

@lru_cache(maxsize=128)
def get_composite_layers(db, map_layer: int) -> list[int]:
    """Get the list of composite layers that a given map layer is part of."""
    layers = db.run_query(
        "SELECT composited_from FROM {data_schema}.map_layer WHERE id = :map_layer",
        dict(map_layer=map_layer),
    ).scalar()
    if layers is None:
        raise ValueError(f"Layer {map_layer} is not a composite layer or does not exist.")
    return layers
