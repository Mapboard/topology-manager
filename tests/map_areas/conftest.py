from pytest import fixture

from mapboard.topology_manager import create_context
from mapboard.topology_manager.commands import create_tables
from mapboard.topology_manager.config import FaceUpdateMode

from .support import (
    DATA_SCHEMA,
    DIRECT_STRATEGY,
    TOPO_SCHEMA,
    create_data_tables,
    drop_map_area_schemas,
)


@fixture(scope="class", params=list(FaceUpdateMode), ids=lambda m: m.value)
def face_update_mode(request):
    """Every class in this suite runs once per face-update mode."""
    return request.param


@fixture(scope="class")
def ctx(empty_db, face_update_mode):
    """A fresh map-area topology for each test class (and each mode)."""
    drop_map_area_schemas(empty_db)
    ctx = create_context(
        empty_db,
        data_schema=DATA_SCHEMA,
        topo_schema=TOPO_SCHEMA,
        srid=4326,
        tolerance=0.0001,
        identity_strategy=DIRECT_STRATEGY,
        boundary_table="map_area",
        create_data_tables=create_data_tables,
        notify_triggers=False,
        face_update_mode=face_update_mode,
    )
    create_tables(ctx)
    yield ctx
    ctx.database.session.close()
