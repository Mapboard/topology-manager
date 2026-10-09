from .update_faces.helpers import FaceUpdateResult, log
from ..config import TopologyContext
from ..database import sql
from psycopg.sql import Identifier


# Update faces for composite layers if requested
def update_composite_layers(ctx: TopologyContext):
    log.info("Updating composite layers")
    db = ctx.database
    layers = db.run_query(
        "SELECT id FROM {data_schema}.map_layer WHERE {data_schema}.is_composite_layer(id)"
    ).scalars()
    for layer in layers:
        log.info("Updating composite layer %s", layer)
        update_composite_layer(ctx, layer)


def update_composite_layer(ctx, map_layer: int, **kwargs) -> FaceUpdateResult:
    layers = get_composite_layers(ctx.database, map_layer)
    return _update_composite_layer(ctx, map_layer, layers, **kwargs)


def _update_composite_layer(
    ctx, map_layer: int, layers: list[int], *, manage_boundaries=True
) -> FaceUpdateResult:
    """Update a composite layer by merging faces from the specified layers."""
    db = ctx.database

    # Ensure that the composite layer has all the necessary linework/polygon types
    if ctx.manage_data_tables:
        add_composite_layer_types(db, map_layer, layers)

    # We can now trust that the composite layer is populated for each constituent layer.
    # For now we set all faces as dirty...

    # We may need to add the entire geometry of any dirty face to the dirty faces for the composite layer.

    # Insert the topmost layer's faces into the composite layer
    reversed_layers = list(reversed(layers))

    manage_boundaries = ctx.manage_data_tables

    if manage_boundaries:
        # Delete stray lines that have been dereferenced for some reason
        # Note: this is a slow way of doing things. It would be better solved with composite
        # lines/faces being stored in a separate table with added constraints.
        res = (
            db.run_query(
                """
            DELETE FROM {boundary_table} l
            WHERE l.map_layer = :composite_layer
            AND l.source_id IS null
            RETURNING l.id;
            """,
                dict(composite_layer=map_layer),
            )
            .scalars()
            .all()
        )
        log.info(
            "Deleted %d stray lines from composite layer %d", len(list(res)), map_layer
        )
        db.session.commit()

    # Get intersecting with dirty map faces...
    overlay_layers = []
    for layer in reversed_layers:
        log.info("Updating composite layer %s from layer %s", map_layer, layer)
        log.info("Overlay layers: %s", overlay_layers)
        ids = db.run_query(
            sql("procedures/update-faces/update-composite-face-elements"),
            dict(
                map_layer=layer,
                overlay_layers=overlay_layers,
                composite_layer=map_layer,
            ),
        ).scalars()
        _n_faces = len(list(ids))
        db.session.commit()
        log.info("Inserted %d map faces from layer %s", _n_faces, layer)

        if manage_boundaries:
            ids = (
                db.run_query(
                    sql("procedures/update-faces/update-composite-line-elements"),
                    dict(
                        map_layer=layer,
                        overlay_layers=overlay_layers,
                        composite_layer=map_layer,
                    ),
                )
                .scalars()
                .all()
            )
            _n_lines = len(ids)
            log.info(f"Inserted %d lines from layer %s", _n_lines, layer)

            db.session.commit()

        overlay_layers.append(layer)

    if manage_boundaries:
        ids = (
            db.run_query(
                sql("procedures/update-faces/update-type-change-elements"),
                dict(
                    composite_layer=map_layer,
                ),
            )
            .scalars()
            .all()
        )
        _n_lines = len(list(ids))
        log.info(f"Updated %d lines that changed type", _n_lines)
        db.session.commit()


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


def get_composite_layers(db, map_layer: int) -> list[int]:
    """Get the list of composite layers that a given map layer is part of."""
    layers = db.run_query(
        "SELECT {data_schema}.composite_layer_members(:map_layer)",
        dict(map_layer=map_layer),
    ).scalar()
    if layers is None:
        raise ValueError(
            f"Layer {map_layer} is not a composite layer or does not exist."
        )
    return layers
