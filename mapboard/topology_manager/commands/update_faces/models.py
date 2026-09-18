"""Data model for the face-update loop."""

from typing import Optional

from pydantic import BaseModel, Field


class DirtyFace(BaseModel):
    """A topology primitive (face) whose map face must be (re)computed in a layer."""

    id: int
    map_layer: int

    def __hash__(self):
        return hash((self.id, self.map_layer))


class FaceUpdateResult(BaseModel):
    """A dissolved component: the maximal set of joinable primitives around a seed.

    `dissolved_faces` is the component. `existing_map_faces` are the map faces that
    held any of its primitives *when the component was computed*; the persisters
    re-query this at persist time, so it is informational only.
    """

    dissolved_faces: list[int]
    existing_map_faces: list[int] = Field(default_factory=list)
    map_layer: int

    @property
    def faces(self) -> list[int]:
        return self.dissolved_faces

    @property
    def touches_universe(self) -> bool:
        """Components that include the universal face (0) never get a map face."""
        return 0 in self.dissolved_faces


class FaceOverlap(BaseModel):
    """An existing map face that holds some of a component's primitives."""

    map_face: int
    shared: list[int]
    outside: list[int]
    n_shared: int
    n_outside: int


class MapFaceChange(BaseModel):
    """What persisting one component did to the map faces of its layer."""

    map_face: Optional[int] = None
    created: bool = False
    added: list[int] = Field(default_factory=list)
    removed: list[int] = Field(default_factory=list)
    deleted: list[int] = Field(default_factory=list)
    shed: list[int] = Field(default_factory=list)
    reseeded: list[int] = Field(default_factory=list)

    def reseeds(self, map_layer: int) -> list[DirtyFace]:
        return [DirtyFace(id=f, map_layer=map_layer) for f in self.reseeded]


class FaceUpdateStats(BaseModel):
    """Counters accumulated over an update run."""

    seeds: int = 0
    components: int = 0
    created: int = 0
    updated: int = 0
    deleted: int = 0
    shed: int = 0
    reseeded: int = 0
    rounds: int = 0

    def add(self, change: MapFaceChange):
        self.components += 1
        if change.created:
            self.created += 1
        elif change.map_face is not None:
            self.updated += 1
        self.deleted += len(change.deleted)
        self.shed += len(change.shed)
        self.reseeded += len(change.reseeded)
