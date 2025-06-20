from ..update import _update
from .helpers import (
    FaceUpdateResult, log
)
from ...database import sql



def update_composite_layer(db, map_layer: int, layers: list[int]) -> FaceUpdateResult:
    """Update a composite layer by merging faces from the specified layers."""

    # Ensure that the composite layer has all the necessary linework/polygon types
    db.run_sql(
        """
        INSERT INTO {data_schema}.map_layer_linework_type (map_layer, "type")
        SELECT :map_layer, "type"
        FROM {data_schema}.map_layer_linework_type
        WHERE map_layer = ANY (:layers)
        ON CONFLICT DO NOTHING;

        INSERT INTO {data_schema}.map_layer_polygon_type (map_layer, "type")
        SELECT :map_layer, "type"
        FROM {data_schema}.map_layer_polygon_type
        WHERE map_layer = ANY (:layers)
        ON CONFLICT DO NOTHING;
        """,
        dict(map_layer=map_layer, layers=layers),
    )

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
