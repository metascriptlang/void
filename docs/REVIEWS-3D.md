# void3d milestone reviews

One section per milestone of `docs/VOID3D.md`, verdict first. Every milestone from M5 on ends
with two passes before the next one starts: a **defect pass** (`/code-review high` over the
milestone's diff) and a **design pass** (a fresh reviewer with no attachment to the code,
briefed as the principal engineer who owns this renderer for the next five years). Send-backs
are recorded here too — the point of this file is what was caught, not a clean story.

`docs/REVIEWS.md` is void2d's and is written on another branch; this file is void3d's so the
two never collide.

---

## M5 — MeshData, Bounds, index buffers, rebuild after context loss

**Verdict: SHIP WITH FOLLOW-UPS.** No send-back. Thirteen findings across the two passes were
confirmed and fixed; one was rejected on a measurement; the rest are carried into M6 below.

Reviewed: the defect pass saw `main..HEAD` at `f480da6`; the design pass saw the same range and
finished after `a8f75d0` had already landed, so four of its findings were fixed before it
reported. Both are recorded as they were raised.

### Defect pass — `/code-review high`

| # | Finding | What I did |
|---|---|---|
| 1 | `rebuildMeshes` deep-copies every `MeshData`, so the context-loss path allocates | **Rejected — measured.** 40 000 calls passing a struct holding a 200 000-element `Vec` by value ran in 0 ms (`out/tmp/copyProbe`); a deep copy would be ~16 GB of memcpy. CODE-STYLE §5: a struct value parameter over 24 bytes is emitted as `const T*`. The reviewer applied the "a `Vec<T>` **parameter** is a copy" rule to a struct that merely *contains* one. The only real copy is `Vec.push` in `addMeshData`, which is setup-time and documented. |
| 2 | A refused index buffer flips `GpuMesh.isIndexed()` to false, so an indexed mesh draws 194 garbage triangles with no diagnostic | Fixed in `a8f75d0`. `uploadMesh` returns `Result`; a refused buffer leaves the mesh drawing nothing and stale, so it is retried rather than reinterpreted. |
| 3 | `try` propagates out of a half-written quad, leaving orphan vertices and an over-reported bounds | Fixed. `hasRoomFor` is checked up front in `addQuad` and `addBox`; a test fills to the cap and asserts that a rejected `addBox` changes neither count. |
| 4 | The layout field is masked on decode but not on encode, so ordinal 8 forges the `indexed` bit | Fixed, with a test that the forgery no longer works. |
| 5 | `closestPoint` has no empty guard, unlike every other accessor, so it returns the +1e20 corner | Fixed; returns zero as `size` and `center` do. |
| 6 | The doc's pipeline-key bit budget sums to 60 — it omits the program's 4 bits | Fixed. |
| 7 | `gpu3d.c` cites `mesh.ms`, which this branch deletes | Fixed. |

Checked and cleared by that pass, worth keeping on the record: index and winding parity with the
deleted `mesh.ms`; the `MAX_MESH_VERTICES` off-by-one; `<<` versus `|` precedence in the new key
term; `describePipeline` writing all 19 descriptor words; the two mesh tables staying one index
space.

### Design pass — fresh principal-engineer reviewer

It independently re-ran the suite and the gate before reading, and verified the three sources
behind "frame 1 is always fresh" (`gpu3d.c` returns literal 1 off Android, `g_generation` starts
at 1, `Renderer.create` sets 0). It also ran its own probe and confirmed finding 1 above is not
a copy. Its blocking items, all now done:

1. **A compiler defect found in M5 was worked around with no card** — `CLAUDE.md` step 3. The
   rename of Heaps' `Bounds.add` to `addBounds` is a visible API change forced by the compiler,
   and the float32 card was written in the same commit, so the rule was live and applied
   selectively. Written: `~/metascript/.inbox/compiler/2026-09-20-ref-receiver-not-an-extension.md`,
   with both halves reproduced live (`ref this c: T` is a parse error; a `ref`-receiver free
   function does not arrive with the module import while a `this` extension in the same module
   does) and every site listed that gets Heaps' name back when it lands.
2. **`addMeshData` with an empty `MeshData` aborts the process.** sokol validates `size > 0` and
   `_SG_PANIC`s; nothing in this tree sets `SOKOL_VALIDATE_NON_FATAL`. Worse, a `drawCheck` test
   was *titled* "gives an empty mesh rather than a bad draw" while only testing `meshFor`.
   Fixed at both levels: `gpu3dMakeVertexBuffer` / `gpu3dMakeIndexBuffer` now guard `length <= 0`
   as `gpu3dMakeImage` already did, and `uploadMesh` refuses an empty mesh with
   `MeshUploadError.EmptyMesh`. The test is retitled to what it actually asserts.
3. **`GpuMesh` grew three fields and was still built by raw literal at four sites** — the exact
   shape of the silent-zero-field trap this project's own notes say bit it once. Added
   `GpuMesh.external(layout, vertexBuffer, instanceBuffer, vertexCount, instanceCount)`, which
   defaults the three fields an externally-owned mesh has no business setting; all four literals
   are gone.
4. **Fail rather than reinterpret when `makeIndexBuffer` returns 0** — already fixed as defect 4
   above.

Non-blocking items it raised, and what happened:

- **The rebuild path had never executed, anywhere.** Correct when written, and the sharpest
  finding in either pass. Now a standing gate configuration: `campfireRebuildCapture` marks every
  mesh stale at frame 3 and lets `rebuildMeshes` run — it re-uploads exactly the one mesh with CPU
  data onto new buffer ids, leaves the five without it alone, and frames 6, 11 and 16 captured
  after it are byte-identical to `before_*`. The opposite direction is measured too: the lit
  mesh's buffer ids are unchanged from `addMeshData` through frame 3, so the always-fresh first
  frame does not upload twice.
- **Three silent `Bounds` divergences from Heaps** (`transformed`'s OR versus Heaps' AND,
  `size`/`dimension` on empty) and an incomplete "not ported" list. All written into "M5 as
  built", and the one-axis-empty case is now tested.
- **`Bounds.all().boundingSphereRadius()` overflows float32 to infinity.** Real; Heaps gets away
  with it on 64-bit floats. Fixed by scaling the extent by its longest edge before squaring, and
  tested.
- **Untested error arms** — `TooManyVertices`, partial-builder failure, `addTriangle`'s negative
  arm. All three now tested.
- **The byte-identity contract rests on prose and on gitignored baselines.** Two answers: a few
  of the box's vertex floats are pinned to measured literals in `meshDataCheck.ms`, which catch
  the geometry moving (a `Mat4` rewrite in M6) though not a last-ulp change; and `gate3d.sh` now
  checks the twenty baselines against a committed `docs/baselines3d.sha256`.
- **The adopted-baseline disclosure was circular.** Correct, and now said in those words: the
  colour-count cross-check shows the three adopted images are *plausible* M4 images, not that they
  are the M4 images, and the non-circular evidence is gone. The two that carry the weight,
  `before_*` and `m3palette_*`, are untouched originals.
- **The gate exits 0 on SKIP.** Now distinguished in the doc; M5's numbers are from a zero-skip run.
- Also fixed: `meshFor` is an extension on `MeshData`; `addTriangle` returns a triangle index as
  `addVertex` returns a vertex index; the five over-100-column lines; the `-1` sentinel in a test
  helper; the words "pet" and "campfire" removed from `src/void3d` (the brief's list is absolute);
  the unparenthesised term in the key; the M9 re-upload leak and `addMeshData` not marking the
  renderer changed are both written into "Still missing".

### Carried into M6

- **`GpuMesh.generation` says the wrong thing for an externally-owned mesh.** It is 0 forever even
  when the buffer is current, and what makes that safe is `isStale`'s length check on a *sibling
  table*. The predicate is doing two jobs — "is this mine to rebuild" and "is it out of date" — and
  the first belongs in the type (`owner: Caller | Context`, or not putting caller-owned meshes in a
  table with a `meshData` column at all). M6 rewrites the example that owns four of the five such
  meshes, so it is the right moment.
- **`staleMeshes` is a hand-duplicated copy of `rebuildMeshes`' loop**, existing so a test has
  something to look at. Both go through the single `isStale` predicate, which is the part that
  matters and is tested, but two loops that must agree is one too many.
- **`LAYOUT_LIMIT` is held by three hand-written asserts**, which a fourth enum member does not
  join automatically.
- **"Exactly 4 pipelines" stops holding** the moment one mesh is non-indexed and another is indexed
  on the same program, state and targets. The indexed bit is a pipeline multiplier, not free.
- `Bounds` ships ten exported functions with no production caller — the M10 surface, landed in M5,
  held only by tests.
- `campfireScene` keeps a second ~23 KB copy of the geometry alive after `addMeshData` copies it.

### Numbers

| | |
|---|---|
| Gate | `sh scripts/gate3d.sh`, 10 stages, **zero SKIP** |
| Tests | 484 (437 before M5; 47 added) |
| Capture | six configurations, all four frames each, **byte-identical** |
| Baselines | 20, checked against `docs/baselines3d.sha256` |
| Campfire geometry | 876 non-indexed vertices → 584 vertices + 876 indices, same 292 triangles |
| Pipelines | 4, unchanged |
| Android | arm64 `libVoidAndroid.so`, 2 231 440 bytes |
