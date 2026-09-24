# Piecewise noding

Noding a boundary row from several geometry pieces into one topogeometry, so that a
host with large or fragile boundaries does not need a second table of parts and a
second phase to assemble them. The host decides how to cut, simplify and retry; the
library nodes what it is given and reports the outcome per piece.

This is the library half of a contract worked out for Macrostrat's map
compilations (the reference workload: ~460 boundary rows of up to a million
vertices, cut into ~77,000 pieces of 256 vertices). The host-side reasoning lives
with that project; this note is what the library guarantees.

## Terms

- **Boundary layer** — the table named by `create_context(boundary_table=…)`, whose
  rows carry the `topo` topogeometry column and act as barriers in the dissolve.
  Fixed columns: `id`, `geometry`, `topo`, `map_layer`, `geometry_hash`,
  `topology_error`.
- **Piece** — a geometry the host supplies to be noded into a boundary row's
  topogeometry. A row may be noded as one piece (the whole-row form) or as many.
- **Accumulation** — PostGIS's `toTopoGeom(geometry, topogeometry, tolerance)`, which
  adds a geometry's primitives to an existing topogeometry, keeping its id.

## The two entry points

Both are forms of `<topo_schema>.update_boundary_topo`, both return the error text
of a failed `toTopoGeom` (NULL on success), and both take the snapping tolerance as
an argument, defaulting to the topology's precision.

**Whole row** — `update_boundary_topo(row, tolerance)`. Nodes the row's `geometry`.
This is what `update_contacts` runs for every pending row (`geometry_hash IS NULL`,
in a topological layer, no `topology_error`). On success `geometry_hash` records
that the topogeometry was built from this geometry and `topology_error` is cleared;
on failure `topology_error` is set and the row is otherwise untouched. An existing
topogeometry is emptied first (keeping its id), so the result holds exactly this
geometry's primitives.

**Piece** — `update_boundary_topo(row, piece, tolerance)`, or from Python
`update_boundary_piece(ctx, row_id, piece, tolerance=None)` /
`TopologyManager.update_boundary_piece`. The first piece creates the row's
topogeometry; later pieces accumulate into it under the same id. On failure the row
is unchanged and nothing is recorded on it — a piece is not a row. The host keeps
per-piece records if it wants them, and decides whether to simplify, subdivide or
retry at another tolerance. The host sets `geometry_hash` when it considers the row
complete:

```sql
UPDATE <boundary_table> SET geometry_hash = <topo_schema>.hash_geometry(geometry) WHERE id = …
```

Until then the row is *pending* to `update_contacts`, which would empty it and node
the whole geometry. A host mid-way through a row's pieces therefore runs the face
update alone (`update(ctx, boundaries=False)` / `update_faces`) or keeps such rows
out of `update_contacts` with a row filter.

## What the library guarantees

- **Tolerance is the caller's.** No entry point chooses a tolerance, retries, or
  alters a geometry before noding.
- **One geometry per topogeometry.** A row whose `geometry` changes has its
  topogeometry emptied (`clearTopoGeom`, id kept) by the `boundary_changed` trigger
  before anything is re-noded, and its `geometry_hash` and `topology_error` reset.
  A row that gives up its topogeometry (`topo` set to NULL) releases its relation
  rows the same way.
- **Every piece marks its faces dirty.** See below. `dirty_face` is the persistent
  queue the face update drains; an interrupted run — between pieces, or between a
  piece and the face update — resumes from it, and realized geometry
  (`map_face.geometry`) is refreshed from that queue, never by re-realizing and
  comparing.
- **Status is per row**: `topo IS NULL` / present, `geometry_hash` current or not,
  `topology_error`. The library does not know about pieces once a call returns.
- **Row selection is parameterized.** `update_contacts(ctx, tolerance=…,
  row_filter="l.map_layer = :layer", filter_params=…, include_failed=…,
  fix_failed=…)`: the filter is a SQL condition over the boundary table aliased
  `l`; `include_failed` also selects rows carrying a `topology_error` (attempted
  once, error replaced by the new outcome); `fix_failed` clears their errors first.
  `failed_boundaries(ctx)` lists the failed set. Each row is attempted exactly once
  per call. Failures are also logged to `<topo_schema>.__boundary_failures`.

## How faces get marked

A noding call is an `UPDATE` of the row's `topo`, so the `boundary_changed` trigger
fires — but an accumulating call keeps the topogeometry id, and in a BEFORE trigger
OLD and NEW resolve to the same relation rows, so the trigger cannot tell which
primitives are new. Two mechanisms in `fixtures/05-linework-triggers.sql` cover
what a piece can change, both marking for the row's dirty layers
(`dirty_layers_for(map_layer)`, as `mark_surrounding_faces` does):

- **Primitives the piece references** — a statement-level trigger on `relation`
  inserts (`mark_boundary_relation_faces`) marks the faces of new relation rows
  whose owner is still being noded (`geometry_hash IS NULL`). This catches a piece
  that adds no edges at all, such as a map whose bounds coincide with one already
  noded. Rows inserted into *complete* rows — an edge or face of theirs split by
  the new geometry — are skipped: PostGIS extends those topogeometries itself, and
  the faces involved border the new geometry and are marked by its own call.
- **Faces on either side of every edge the noding created or modified** — from a
  snapshot of the edges near the piece taken before the call (`mark_noded_faces`).
  When a new line ends on an existing edge at a point that is not exactly
  representable, PostGIS inserts a vertex into that edge, changing the shape of the
  faces on both sides without touching a relation row; the face across a
  T-junction borders no new edge, and this is the only way it gets marked.

The universal face is never marked by either. `update_line_edge_relation` no longer
recomputes a feature's whole `__edge_relation` entry on an update that keeps its
topogeometry: the relation-row triggers already follow the primitives a piece adds
(row by row for edges, through `__edge_relation_dirty` for faces), so a piece costs
what the piece touches, not what the row holds. The face-based cache is refreshed by
`update_faces` (or `rebuild_dirty_edge_relations`), not per piece.

## Tests

`tests/map_areas/test_piecewise_noding.py` (face-based boundaries, both face-update
modes) and `tests/core/test_13_piecewise_noding.py` (lineal boundaries) cover: a row
noded from pieces equals the row noded whole (same primitives, same relation rows);
a failing piece leaves the row and the other pieces intact; whole-row failure is
recorded, selectable and retried; a geometry change empties the topogeometry before
re-noding, keeping its id; a T-junction marks the face across the split edge; an
update interrupted between pieces resumes from `dirty_face`; the tolerance argument
is honoured.
