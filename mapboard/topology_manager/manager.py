"""TopologyManager: a convenient object-oriented interface to the topology manager."""

from .config import TopologyContext
from .commands.update_topology import update
from .commands.update_contacts import update_contacts
from .commands.clean_topology import clean_topology
from .commands.update_faces import update_faces
from .commands.update_composite_layers import update_composite_layers
from .commands.create_tables import create_tables


class TopologyManager:
    """Wraps a TopologyContext and exposes topology operations as methods,
    eliminating the need to pass ``ctx`` to every function call."""

    def __init__(self, ctx: TopologyContext):
        self._ctx = ctx

    # ------------------------------------------------------------------
    # Convenience accessors
    # ------------------------------------------------------------------

    @property
    def db(self):
        """The underlying Database instance."""
        return self._ctx.database

    @property
    def database(self):
        """Alias for :attr:`db` for backward compatibility."""
        return self._ctx.database

    @database.setter
    def database(self, value):
        """Allow replacing the underlying database (e.g. in tests)."""
        self._ctx.database = value

    @property
    def ctx(self) -> TopologyContext:
        """The underlying TopologyContext (for use with lower-level APIs)."""
        return self._ctx

    # ------------------------------------------------------------------
    # Commands
    # ------------------------------------------------------------------

    def update(self, **kwargs):
        """Run a full topology update (contacts → faces → clean → composite)."""
        update(self._ctx, **kwargs)

    def update_contacts(self, **kwargs):
        """Recalculate linework contacts."""
        update_contacts(self._ctx, **kwargs)

    def update_faces(self, **kwargs):
        """Recalculate map faces."""
        update_faces(self._ctx, **kwargs)

    def clean_topology(self):
        """Remove empty topogeometries and unused primitives."""
        clean_topology(self._ctx)

    def update_composite_layers(self):
        """Rebuild all composite layers from their source layers."""
        update_composite_layers(self._ctx)

    def create_tables(self):
        """Create the topology schema tables from SQL fixtures."""
        create_tables(self._ctx)
