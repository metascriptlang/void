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
---

## M6 — the Object3D tree, the model matrix, and the campfire rebuilt on it

**Verdict: SHIP WITH FOLLOW-UPS.** No send-back. Both passes ran before M7 was started. Between
them they confirmed twenty findings; three were blocking and all three are closed; the rest are
listed below with the milestone that pays.

**Why this is not a send-back, stated so a reader can disagree.** The shape of this milestone is
uncomfortably close to one that earned a send-back on a neighbouring arc: two passes, both
confirming a run of real defects, including a gate stage that could not fail on the claim it was
written to prove. The distinction I am drawing is between a gate that *measures nothing* and a
gate that *measures less than its description*. The bench gates `now - base` over lengths read
out of the live structures, and the control run — reporting `stack` as `length + frameIndex` —
fails it at `growth.stack=300`, so the numbers it gates can move. What was wrong was the
sentence next to it, which said that constituted "nothing in `frame` allocates". It did not, and
an allocation was hiding in exactly that blind spot. The remedy was not to soften the sentence:
it was a second stage, `allocation`, that reads the emitted C for `msArrayCopy` inside the three
frame-path functions, and which fails — verified by putting the copy back — naming the function.
Both reviewers judged the design itself sound, which is what a send-back is for. If a later
reader thinks shipping a green gate beside a false claim for the length of one commit cycle is
itself the send-back, that judgement is defensible and this paragraph is the evidence for it.

### Defect pass

Read the diff, ran the gate and the suite, wrote eight probes, and read the emitted C out of
`out/debug/.cache/`. Thirteen findings.

| # | Finding | What I did |
|---|---|---|
| 1 | `collect` and `refresh` bind each node's children to a `Vec` local — CODE-STYLE §5's copy trap — so the steady frame does 34 `msArrayCopy` + `msArrayDestroy` pairs. **The central "nothing in `frame` allocates" claim was false, and the bench could not see it.** | Fixed in `f945e4b`. Both walks index through the field. Confirmed from the emitted C: `msArrayCopy` per function is now `syncWorld` 0, `collectDrawList` 0, `refresh` 0, and `detach` 1 — deliberate, it pops, and it is not in the frame path. Frame cost fell 0.0727 → 0.0643 ms and the variance with it. The claim now has its own gate stage. |
| 2 | `refresh` returns `items.length` rather than what it wrote, never truncates and never bounds-checks: a node culled after collection leaves a stale duplicate in the list, and un-culling it writes past the end. | Fixed in `f945e4b` — **and the first fix was half of one.** I added truncation only; the test written immediately after, "un-culling a node puts it back without writing past the end", crashed and bisected to exactly the direction I had missed. `refresh` now grows as well as shrinks, and rewrites `material` too, which `collect` already did and it did not. |
| 3 | A retired slot is withheld from the free list but its **id is never invalidated**, so `isLive` answers true forever: every guarded entry point lets a caller through, including adopting a child under a node unreachable from the root. | Fixed. The generation is zeroed on retirement, which no id is ever issued with, and `nodeCount` no longer counts a retired slot as live. |
| 4 | `scene.meshes` is never reclaimed: `remove` frees the node slot but leaves the `MeshInstance` row, so churning *n* mesh nodes grows that table by *n* forever. | **Open**, documented. Written into "Two things `remove` does not do" with why compaction needs a remap pass. No caller churns nodes yet. |
| 5 | `refresh` is missing the `root == NO_NODE` guard that both other walks have. | Fixed. |
| 6 | Four new exported names collide with existing exports — `at`, `collect`, `sync`, `toMatrix` — including `collect` against `passList.collect`, both `ref`-receiver free functions inside void3d. This is the hazard `addMesh` → `addMeshNode` was renamed to avoid, reintroduced four times with the most generic names available. | Fixed: `collectDrawList`, `syncWorld`, `transformAt`. `toMatrix` is a `this`-receiver extension and dispatches on its receiver, so it stays. |
| 7 | Dead error surface: `SlotsExhausted` and `CycleWouldForm` are never constructed, `newSlot` cannot fail so three `try`/`if (ok)` arms are dead, and `UnknownNode` names two unrelated conditions. | Fixed. `newSlot` returns a `NodeId`, the enum is `StaleNode` / `RootCannotBeRemoved` / `NotAMeshNode`. |
| 8 | Untested arms: `setMeshOf` entirely, the stale-id arm of five entry points, `setVisible(true)`, middle-sibling removal, `collect` after `remove`. | Fixed — eight tests added, 524 total. The culled-node pair is what caught finding 2's incomplete fix. |
| 9 | 14 lines over 100 columns, in files the M5 review had just fixed for the same reason. | Fixed, and made a gate stage rather than a third review comment. |
| 10 | The `entries` stage greps and does not build; `src/examples/mainCampfire.ms` **does not compile from `src/`** — only the gate's sed-patched copy in `out/tmp` does. | Fixed in `c9ed332`. The `as int32` moved into the source, the sed clause is gone, and the stage now builds the host entries. |
| 11 | The bench's six counters are near-tautological in this workload; `uniforms` can never grow because `reserveUniforms` returns `PoolFull` rather than pushing. | Accepted as correct. It is a trip-wire against a future regression, not a measurement of allocation — the `allocation` stage is. Said so in the doc. |
| 12 | Nothing checks that `shader3d.glsl.h` was regenerated from `shader3d.glsl`; `purge_stale_shader_objects` guards the objects downstream, not the header. The reviewer re-ran `sokol-shdc` and confirmed the committed header is current. | **Open.** Two-line check, M7. |
| 13 | Every early `return` in `setupDraws` leaves `flameNode` at `{-1, 0}`, after which `frameCampfire` returns before rendering on every frame — full speed, blank screen, no diagnostic. | **Open**, M7 with the billboard rebuild work that touches the same function. |

Checked and cleared, worth the record: the descent stack sizing is correct and could not be broken
(a 201-deep chain, then all 201 slots recycled into a 201-wide fan); `sync`'s `local * parent`
row-vector order; the free list really is LIFO; `detach` preserves sibling order; and the whole
model-matrix wiring — row-major against column-major, slot 2, `mat3(model)` given `litFs`
normalizes, and the HLSL `mul(float4(position,1.0f), _13_model)` with `row_major float4x4`.

### Design pass — fresh principal-engineer reviewer

Ran the gate, re-ran both probes, ran the bench eight more times, wrote two probes of its own.
Its three blocking items, all now closed:

1. **The allocation claim.** Same as defect 1. Its instruction was "either the bench must be able
   to fail on an allocation, or every claim must be downgraded to what the bench gates — pick
   one; today the doc claims the strong version and the gate proves the weak one." Both were
   done: the copy is gone, and `allocation` is the stage that proves it.
2. **The FMA paragraph counted the wrong thing.** "29 real rotation matrices" — but every stone
   has `tilt: 0.0` and 22 of 26 have `yaw: 0.0`, so 22 stones and the ground carry an
   exactly-identity 3×3, which by the doc's own argument settle nothing about contraction. The
   discriminating set is **7 boxes**: 3 logs with yaw and tilt, and 4 stones at yaw 0.02, 0.05,
   0.10 and 0.12 rad — 140 of 584 vertices. Rewritten to claim only that, which is narrower than
   "the compiler does not contract" and is what the evidence supports.
3. **"about 4 ulps" is 2 ulps.** The cited pair is bit patterns 1040376648 and 1040376646; every
   differing component in the probe is 1 or 2 ulps. Wrong by 2–4×, in the document whose posture
   is that numbers are measured. Corrected in both places.

It also caught that the ten-run variance was one sample: its own eight runs gave CV 6.9% and
spread 23.6% against my 4.38% and 14.9%. Both are now in the doc, with the point that one sample
of ten is not a variance and the figure is not yet a licence for a threshold.

### Carried into M7 and later

- **M7.** `GpuMesh.generation` still says the wrong thing for an externally-owned mesh; the
  campfire still cannot rebuild its billboard buffers or its two generated textures; `staleMeshes`
  still duplicates `rebuildMeshes`' loop; the scene emits tree order and uses neither `Phase` nor
  `sortBackToFront`, which lights and any transparency break first; `FLAG_CULLED` hides its whole
  subtree where Heaps only does that under `inheritCulled`, and M7 is the first to set the flag;
  `refresh` walks the whole tree even when `sync` returned 0; the shader-header freshness check;
  `setupDraws`' silent permanent failure.
- **M8.** `Object3D` has no `name` and there is no lookup, while glTF nodes and the Blender
  exporter's contract are name-keyed. `Transform3D.scale` exists, is never set, has no test, and
  the shader's `mat3(model)` is wrong for non-uniform scale — `normalMatrix` exists unused. One
  material per mesh node, where glTF primitives will want one node per primitive.
- **M9.** No `defaultTransform`, so animation must overwrite the authored transform or add the
  second slot then. `uploadMesh` still never destroys what it replaces.
- **M10.** No bounds on a node, so nothing culls and picking has nothing to test against;
  `Bounds` has now had no production caller for two milestones.
- **M11 / any time.** No reparenting. `scene.meshes` leak (defect 4).
- **Re-carried from M5, undone by neither milestone:** `LAYOUT_LIMIT` held by three hand-written
  asserts; "exactly 4 pipelines" stops holding once indexed and non-indexed share a program; and
  the duplicate geometry copy, which M6 made worse — `pieces` and `placements` are module-scope
  and hold 30 `MeshData` copies forever after `setupDraws` has handed them over.
- **Dead API.** `Box.base`/`.yaw`/`.tilt`, `BoxFrame`, `toWorld` and `rotate` now have no
  production caller: the campfire passes `unplaced(block)` and lets the node place it. Either
  delete them or say they are test-only.
- **The `pending` stage's own fragilities.** Two rows are enforced by grepping an exact English
  phrase out of `VOID3D.md`, so rewording turns the gate red for no reason; the row-id regex is
  `[a-z0-9-]+`, so an id with an underscore is a row that is never enforced; two rows name an msc
  feature as their exit condition and nothing checks the compiler version.
- **The android stage's entry** is a hand-kept copy in gitignored `out/tmp`, not regenerated by
  `prepare` — the failure mode M5's doc argued against for capture entries.

### Numbers

| | |
|---|---|
| Gate | `sh scripts/gate3d.sh`, **16 stages**, zero SKIP |
| Tests | 524 (499 before M6; 25 added) |
| Capture | seven configurations, four frames each, byte-identical; `m6spin` is a new baseline, not a re-baseline |
| Baselines | 24, checked against `docs/baselines3d.sha256` |
| Scene | 34 nodes, 36 meshes of which 30 rebuildable, 32 draw items per frame (was 3), 4 pipelines (unchanged) |
| Geometry | 584 vertices, 876 indices — the same totals the merged mesh had |
| Frame cost | 0.0643 ms of CPU, sd 0.0017 over ten runs; the 6.06 ms wall clock is vsync at 165 Hz, not a cost |
| Android | arm64 `libVoidAndroid.so`, 2 318 952 bytes, still never run |
