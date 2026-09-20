# PENDING3D — void3d's known divergences and gaps, read by the gate

One entry per known divergence from Heaps, deliberate deferral, or measurement this port does
not have yet. The rule is rexa's, unchanged, and is the same one
[tests/PENDING.md](PENDING.md) states for void2d:

> **A listed case that stops holding fails the run**, and its entry is deleted in the same
> commit as the fix.

That is what keeps the list from going stale, and it is why the list can be seeded
aggressively. void2d keeps its own list; this file is void3d's, so the two never collide the
way `docs/REVIEWS.md` and `docs/REVIEWS-3D.md` are kept apart.

**How a row is enforced.** Each row carries a **sentinel**: a `// PENDING3D: <id>` comment at
the site of the divergence, or a sentence in a doc that states the gap. The `pending` stage of
`scripts/gate3d.sh` checks both directions and fails on either:

- a row here whose sentinel is **gone** — the divergence was fixed and the row was not deleted;
- a sentinel in the tree with **no row** here — a divergence was marked and never written down.

So deleting the code comment without deleting the row turns the gate red, and so does the
reverse. A prose list has no forcing function; this one does.

## Rows

| id | what holds today, and why | sentinel | removed by |
|---|---|---|---|
| `bounds-transformed-or` | `transformed` treats a box empty on **any** axis as empty, where Heaps (`Bounds.hx:159`) tests all three with AND and transforms a one-axis-empty box anyway. The conservative reading, tested. | `src/void3d/bounds.ms` | deliberate — deleted only if Heaps parity is chosen over it |
| `bounds-empty-size-zero` | `size()` and `dimension()` answer zero on an empty box; Heaps (`Bounds.hx:329`, `:389`) answers −2e20 per axis. | `src/void3d/bounds.ms` | deliberate |
| `bounds-sphere-rescale` | `boundingSphereRadius` scales by the longest edge before squaring, because `Bounds.all()` spans 2e20 and its square is infinity in float32. Heaps squares directly and gets away with it on float64. | `src/void3d/bounds.ms` | deliberate |
| `mesh-generation-ownership` | `GpuMesh.generation` is 0 forever for a mesh whose buffers its owner keeps, so "is this mine to rebuild" is decided by `isStale`'s length check on a sibling table rather than by the type. | `src/void3d/draw.ms` | M7 |
| `stale-meshes-duplicate-loop` | `staleMeshes` hand-duplicates `rebuildMeshes`' loop so a test has something to count. Two loops that must agree is one too many. | `src/void3d/draw.ms` | M7 |
| `upload-mesh-leaks-on-replace` | `uploadMesh` never destroys the buffers it replaces. Correct for a real context loss, where they are already gone; a leak of two buffers per swap once something re-uploads a live mesh. | `src/void3d/draw.ms` | M9, which is the first to re-upload live meshes |
| `scene-flags-not-bitset` | Node flags are bits in an `int32` where CODE-STYLE §4 asks for `BitSet<E>`. A version floor: msc 0.2.53 has no `BitSet`. | `src/void3d/scene.ms` | whichever msc first ships `BitSet` |
| `mesh-node-name-collision` | The scene's mesh writer is `addMeshNode` rather than Heaps' name, because two `ref`-receiver free functions with one name resolve to the wrong one **silently** (compiler card `2026-09-20-ref-receiver-not-an-extension.md`). | `src/void3d/scene.ms` | when a `ref this` receiver parses |
| `example-billboards-not-rebuildable` | The campfire cannot rebuild its billboard corner buffer, grass and flame instance buffers, or its two generated textures after a context loss: regenerating them re-rolls the shared `nextRandom()` and changes the image. Needs kept pixels or a reset seed. | `src/examples/campfireScene.ms` | M7 |
| `baselines-adopted-circular` | `m3preview_*`, `m3direct_*` and `m3depth_*` were adopted at `16c6546` because the M4 worktree's copies were never carried over. Comparing against an adopted image is circular; the non-circular evidence is gone. | `docs/VOID3D.md` phrase `plausible* M4 images` | never — it is a permanent hole in the record, kept visible |
| `gles3-never-run` | The `android` stage **builds** the arm64 `.so` and has never run it. Every pixel claim in this port is D3D11 readback on one Windows box; GLES3, the backend most likely to contract floating-point differently, has no numbers at all. | `docs/VOID3D.md` phrase `has never run it` | the device checkpoint before M7 |

## Not covered here, deliberately

`docs/VOID3D.md` "Still missing" carries the narrative gaps that are milestones rather than
divergences — lights, glTF, animation, picking, particles. A milestone that has not happened is
not a pending divergence; it is the roadmap. The distinction matters because this list is meant
to be short enough that every row is read.
