# void3d milestone reviews

One section per milestone of `docs/VOID3D.md`, verdict first. Every milestone from M5 on ends
with two passes before the next one starts: a **defect pass** (`/code-review high` over the
milestone's diff) and a **design pass** (a fresh reviewer with no attachment to the code,
briefed as the principal engineer who owns this renderer for the next five years). Send-backs
are recorded here too — the point of this file is what was caught, not a clean story.

`docs/REVIEWS.md` is void2d's and is written on another branch; this file is void3d's so the
two never collide.

**A "### Numbers" table names the tree it was measured at, and the milestone's last commit
re-takes it.** A verdict is written before its milestone's last commits, so its numbers are
stale by construction and not by anyone's mistake — M6's table said 16 stages and 524 tests for
five commits after it stopped being true, in the one document the next milestone reads to
decide the previous one is done.

**The anchor is a tree hash with the commit's subject beside it, and not a commit sha.** A gate
run reads a *working tree*: the tree is the thing the numbers were measured on, and naming the
commit was always one indirection more than the measurement needed. It is also the only anchor
that survives — this arc lost its commit references twice in one day, first to a rebase and then
to a force-pushed history, while the tree hash came through both unchanged: the rewritten commit
and the dead one it replaced name the same tree, `75df15b6`. Find the commit again with
`git log --format='%h %T %s' main | grep <tree>`; the subject is written beside the hash because
`git show <tree>` gives a directory listing and no story.

---

## M5 — MeshData, Bounds, index buffers, rebuild after context loss

**Verdict: SHIP WITH FOLLOW-UPS.** No send-back. Thirteen findings across the two passes were
confirmed and fixed; one was rejected on a measurement; the rest are carried into M6 below.

Reviewed: the defect pass saw `main..HEAD` at `fdbfb8b`; the design pass saw the same range and
finished after `003bdb8` had already landed, so four of its findings were fixed before it
reported. Both are recorded as they were raised.

### Defect pass — `/code-review high`

| # | Finding | What I did |
|---|---|---|
| 1 | `rebuildMeshes` deep-copies every `MeshData`, so the context-loss path allocates | **Rejected — measured.** 40 000 calls passing a struct holding a 200 000-element `Vec` by value ran in 0 ms (`out/tmp/copyProbe`); a deep copy would be ~16 GB of memcpy. CODE-STYLE §5: a struct value parameter over 24 bytes is emitted as `const T*`. The reviewer applied the "a `Vec<T>` **parameter** is a copy" rule to a struct that merely *contains* one. The only real copy is `Vec.push` in `addMeshData`, which is setup-time and documented. |
| 2 | A refused index buffer flips `GpuMesh.isIndexed()` to false, so an indexed mesh draws 194 garbage triangles with no diagnostic | Fixed in `003bdb8`. `uploadMesh` returns `Result`; a refused buffer leaves the mesh drawing nothing and stale, so it is retried rather than reinterpreted. |
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

Measured at tree `b09f44a2`, the tree of *docs: the M5 review, its findings, and what they
changed*, this section's own commit. One void3d commit followed it inside M5 —
`1009e33`, which strips line endings before comparing the manifest — and it moved none of these
rows. Read them as M5's numbers and not as today's: the gate has grown eight stages and the
suite has grown by 120 since, for reasons that have nothing to do with M5.

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
| 1 | `collect` and `refresh` bind each node's children to a `Vec` local — CODE-STYLE §5's copy trap — so the steady frame does 34 `msArrayCopy` + `msArrayDestroy` pairs. **The central "nothing in `frame` allocates" claim was false, and the bench could not see it.** | Fixed in `0442f7c`. Both walks index through the field. Confirmed from the emitted C: `msArrayCopy` per function is now `syncWorld` 0, `collectDrawList` 0, `refresh` 0, and `detach` 1 — deliberate, it pops, and it is not in the frame path. Frame cost fell 0.0727 → 0.0643 ms and the variance with it. The claim now has its own gate stage. |
| 2 | `refresh` returns `items.length` rather than what it wrote, never truncates and never bounds-checks: a node culled after collection leaves a stale duplicate in the list, and un-culling it writes past the end. | Fixed in `0442f7c` — **and the first fix was half of one.** I added truncation only; the test written immediately after, "un-culling a node puts it back without writing past the end", crashed and bisected to exactly the direction I had missed. `refresh` now grows as well as shrinks, and rewrites `material` too, which `collect` already did and it did not. |
| 3 | A retired slot is withheld from the free list but its **id is never invalidated**, so `isLive` answers true forever: every guarded entry point lets a caller through, including adopting a child under a node unreachable from the root. | Fixed. The generation is zeroed on retirement, which no id is ever issued with, and `nodeCount` no longer counts a retired slot as live. |
| 4 | `scene.meshes` is never reclaimed: `remove` frees the node slot but leaves the `MeshInstance` row, so churning *n* mesh nodes grows that table by *n* forever. | **Open**, documented. Written into "Two things `remove` does not do" with why compaction needs a remap pass. No caller churns nodes yet. |
| 5 | `refresh` is missing the `root == NO_NODE` guard that both other walks have. | Fixed. |
| 6 | Four new exported names collide with existing exports — `at`, `collect`, `sync`, `toMatrix` — including `collect` against `passList.collect`, both `ref`-receiver free functions inside void3d. This is the hazard `addMesh` → `addMeshNode` was renamed to avoid, reintroduced four times with the most generic names available. | Fixed: `collectDrawList`, `syncWorld`, `transformAt`. `toMatrix` is a `this`-receiver extension and dispatches on its receiver, so it stays. |
| 7 | Dead error surface: `SlotsExhausted` and `CycleWouldForm` are never constructed, `newSlot` cannot fail so three `try`/`if (ok)` arms are dead, and `UnknownNode` names two unrelated conditions. | Fixed. `newSlot` returns a `NodeId`, the enum is `StaleNode` / `RootCannotBeRemoved` / `NotAMeshNode`. |
| 8 | Untested arms: `setMeshOf` entirely, the stale-id arm of five entry points, `setVisible(true)`, middle-sibling removal, `collect` after `remove`. | Fixed — eight tests added, 524 total. The culled-node pair is what caught finding 2's incomplete fix. |
| 9 | 14 lines over 100 columns, in files the M5 review had just fixed for the same reason. | Fixed, and made a gate stage rather than a third review comment. |
| 10 | The `entries` stage greps and does not build; `src/examples/mainCampfire.ms` **does not compile from `src/`** — only the gate's sed-patched copy in `out/tmp` does. | Fixed in `cf27364`. The `as int32` moved into the source, the sed clause is gone, and the stage now builds the host entries. |
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
  exporter's contract are name-keyed. `Transform3D.scale` still has no production caller that
  sets it, and the shader's `mat3(model)` is still wrong for non-uniform scale —
  `normalMatrix` exists unused. **"Has no test" stopped being true at `82ab440`**, after this
  list was written: `local-scale-on-the-diagonal`, `scale-is-prepended-to-rotation` and
  `non-uniform-scale-under-rotated-parent` hold it against real Heaps, and the second is what
  established that the local is `S * R`. One material per mesh node, where glTF primitives will
  want one node per primitive.
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

Re-taken at tree `75df15b6`, the tree of *docs(void3d): the pending list enforces a sentinel,
and only three rows enforce the divergence*, from one `sh scripts/gate3d.sh` run — because the
table was first written at the M6 review itself, five commits earlier, and four of its eight
rows had stopped being true by the time the milestone ended. What moved each one is in the row.

| | |
|---|---|
| Gate | `sh scripts/gate3d.sh`, **18 stages**, GREEN with **1 SKIP** (`device`). Was 16 and zero SKIP: `23c5534` added `device`, a loud SKIP unless `GATE_DEVICE=1`, and `ff239d5` added `oracle` |
| Tests | **604**, and none of the 80 over the review's 524 are this milestone's. Every test file that changed across the rebase onto `da36060` is void2d's — `tests/displayList/snapshot.ms`, `tests/harness/benchRows.ms`, `tests/harness/parse.ms`, `src/test/nodeCheck.ms` — and no test file of either arc changed after `9c72aaa`, which bounds M6's own post-review contribution at zero. M6 added 25, unchanged |
| Capture | seven configurations, four frames each, byte-identical; `m6spin` is a new baseline, not a re-baseline |
| Baselines | 24, checked against `docs/baselines3d.sha256` |
| Oracle | 30 cases agree with real Heaps and 3 diverge as declared, over 2 files — a row the review could not have had, since `ff239d5` and `82ab440` are both after it |
| Scene | 34 nodes, 36 meshes of which 30 rebuildable, 32 draw items per frame (was 3), 4 pipelines (unchanged) — the `bench` stage prints `drawItems=32 nodes=34 meshes=36 rebuildable=30 pipelines=4` every run |
| Geometry | 584 vertices, 876 indices — the same totals the merged mesh had |
| Frame cost | **not re-taken, and deliberately.** This run printed 0.0596 ms; one reading is not a variance, and 0.0643 ms sd 0.0017 is a figure stated more precisely than it was measured. The interleaved A/B that would settle it is open and is not a session's to open. Nothing gates on milliseconds — `bench` gates growth at zero |
| Android | arm64 `libVoidAndroid.so`, **2 319 400 bytes**, and **it has run**: `23c5534` executed the GLES3 path on the Android emulator, `tests/device/gles3Campfire.png`. Not on a device, and against no baseline |

## M7 — lights as scene nodes, the 44-float block, and the billboards rebuilt from CPU copies

**Verdict: SHIP WITH FOLLOW-UPS.** No send-back. Both passes ran before this section was
written. Between them they confirmed one measured code defect (fixed in the review's own
commit, `c3bc215`) and two debts M6 had scheduled for M7 that the milestone's commits did not
pay — one of the two was paid by the review instead (the `shaders` freshness stage), the other
(`setupDraws`' silent failure) is paid as fail-loud `console.log` arms in the same commit and
re-scheduled below only for the remaining `frameCampfire` arms.

Reviewed: the defect pass saw `git diff 8ed7b76^..12e96c7`; the design pass saw the same range
plus the docs commit. The review's fixes land as `c3bc215` and `965a7cd`.

### Defect pass

| # | Finding | What I did |
|---|---|---|
| 1 | **`quatBetween` returns an all-NaN quaternion for near-opposite unit vectors** — a float32 dot can round below −1 (~1% of near-opposite normalized pairs, measured by simulation: 4 892 of 500 000), the negative radicand square-roots to NaN, and `NaN < EPSILON` is false so the 180° fallback never fires | Clamped by branch (`radicand > 0.0 ? sqrt : 0.0`), added the regression test that fails on the old form (`math3dCheck`, 617th test) |
| 2 | `setupDraws`' six silent `return` arms still leave `flameNode` at `{-1, 0}` — M6 defect 13, scheduled for M7 | Every arm now prints `campfire: setupDraws bailed at <step>`. The arms in `frameCampfire` remain silent and are carried below |
| 3 | The shader-header freshness check (M6 defect 12, "two-line check, M7") was not paid | Paid: the `shaders` gate stage regenerates all three `.glsl.h` into `out/tmp` and compares byte-exact after dropping the two lines shdc echoes the output path into. Verified failing: `step(0.35→0.36)` in the GLSL reddens it; a comment does not, because shdc strips comments — the control that failed first |
| 4 | `scene.lights` rows are never reclaimed by `remove` — the documented `scene.meshes` leak, existing a second time undocumented | Added `scene-side-tables-never-shrunk` to PENDING3D, covering both tables, scheduled for M11's compaction |
| 5 | "M7 as built" first misattributed the tie-break to `sortLight` and named `computeLighting`, which does not exist | Corrected: `computeLight`, priority-descending is Heaps', declaration-order ties are this port's (Heaps ties on `objectDistance`), and the cut `cullLights`/dir-priority items are now said |

### Design pass

Independently verified, by reading the emitted C and the generated header rather than trusting
the docs: `collectLights`' frame path contains zero `msArrayCopy` (24 array reads, 20 span
writes, one push and one pop into a scratch drained at entry); the 44-float layout matches
`lightParams_t` exactly; `norm(0.35, 0.9, 0.25) = 0.9974968`; `225 928 / 921 600 = 24.51%`;
the 12-test count and the 9-then-10 PENDING3D rows; both rebuild shapes honestly written down.
Its findings and their dispositions:

| # | Finding | What I did |
|---|---|---|
| 1 | The allocation stage did not cover `collectLights`, a new per-frame function — the exact shape by which M6 shipped a copy with a green gate | Added to `FRAME_PATH_FUNCTIONS`; the stage line now reads `syncWorld collectDrawList refresh collectLights` |
| 2 | `forceRebuild`'s mesh half leaked ~60 live buffers per rebuild run (pool ceiling ~127/128 corroborated by the `BUFFER_POOL_EXHAUSTED` anecdote), and `upload-mesh-leaks-on-replace`'s "M9 is the first to re-upload live meshes" premise was false since this milestone | `forceRebuild` now destroys each stale mesh's vertex and index buffer before resetting its generation; the PENDING3D row keeps its `uploadMesh` claim and its exit is re-worded |
| 3 | Two M6 debts scheduled for M7 were silently unpaid and "M7 as built" did not say so | Paid both here (findings 2 and 3 above); this section is the record that says so |
| 4 | "Front" is local +Z here; Heaps' `Matrix.front()` is the +X row — undocumented, and a verbatim Heaps rotation aims a directional 90° off | Written into "M7 as built" and the `light-params-divergence` context |
| 5 | The 225 928 px control had no in-tree recipe | The sed/capture/magick one-liner is now in "M7 as built" |
| 6 | `moon` survived as a local name in the library shader on a line the patch renamed | Renamed `lambert` (`965a7cd`); header unchanged, pixels unchanged |
| 7 | Nothing statically ties `LIGHT_UNIFORM_LENGTH` to the generated block size | `_Static_assert(sizeof(lightParams_t) == 44 * 4)` in `gpu3d.c`, the established pattern |

### Carried into M8 and later

- **M8.** `Object3D` has no `name` and no lookup (glTF nodes are name-keyed); `Transform3D.scale`
  has no production caller and `mat3(model)` stays wrong for non-uniform scale; one material
  per mesh node where glTF primitives want one node per primitive. All carried from M6, still true.
- **M9.** No `defaultTransform`; `uploadMesh` still never destroys what it replaces (now only
  reachable by a path that destroys first — the row says which).
- **M10.** No bounds on a node, so nothing culls and picking has nothing to test against.
- **M11.** `scene.meshes` and now `scene.lights` both grow forever under churn
  (`scene-side-tables-never-shrunk`); the instance-CPU-owner question, sharpened by M7's
  kept-copy pattern, is in Open questions.
- **Any time.** `frameCampfire`'s own silent `return` arms (the setup arms are paid; the frame
  arms print nothing); `refresh` walks the whole tree even when `sync` returned 0, and a steady
  frame is now three walks (sync, collectDrawList path, collectLights); the tree emits in tree
  order with `Phase` and `sortBackToFront` unused, which transparency will break first; the
  `android` stage's entry is still a hand-kept copy in `out/tmp`.
- **Re-carried from M5, undone by neither milestone:** `LAYOUT_LIMIT` held by three hand-written
  asserts; "exactly 4 pipelines" stops holding once indexed and non-indexed share a program; the
  duplicate geometry copy (`pieces`/`placements` module-scope).

### Numbers

Re-taken at tree `3507f613`, the tree of *refactor(void3d): the lit shader's moon local names
the lambert term it holds*, from one `sh scripts/gate3d.sh` run.

| | |
|---|---|
| Gate | `sh scripts/gate3d.sh`, **19 stages**, GREEN with **1 SKIP** (`device`). Was 18: `c3bc215` added `shaders` |
| Tests | **617**, 13 of them M7's (10 scene, 3 quaternion — the third is the review's own regression test) |
| Capture | seven configurations, four frames each, byte-identical to the M6 baselines; **no baseline replaced**, and the campfire's lights provably drive the image (control in "M7 as built") |
| Baselines | 24, checked against `docs/baselines3d.sha256` |
| Oracle | 30 cases agree with real Heaps and 3 diverge as declared, over 2 files |
| Scene | 36 nodes (+2 lights), 36 meshes of which 30 rebuildable, 32 draw items, 4 pipelines |
| Frame cost | 0.0616 ms CPU this run; the interleaved A/B is still open and still not a session's to open; `bench` gates growth at zero and passed at 300 frames |
| Android | arm64 `libVoidAndroid.so`, **2 376 056 bytes**; still emulator-only, still no device |

## M8 — strict glTF subset, scene materialization, and scale-correct normals

**Verdict: SHIP WITH FOLLOW-UPS.** No send-back. The defect pass and a separate design pass
reviewed `git diff 2a067a4..9e6f0e2`, then re-read the live review fixes before issuing their
verdicts. The original audit was right: its six M8-local findings were real, and all six are
closed. The review itself found additional fail-open cases; `9e6f0e2` closes them rather than
describing malformed or unsupported content as loaded.

### Defect pass

| # | Finding | What I did |
|---|---|---|
| 1 | The first decoder accepted a missing index accessor and returned a mesh with vertices but no triangles; it also ignored node matrices | uint16 indices are mandatory for this subset, and matrix nodes are rejected |
| 2 | JSON integer coercion accepted fractional values and could wrap an int64 node, mesh or scene ordinal into int32; accessors also accepted zero counts, bad alignment and an escaped declared view | One range-checked integer path now owns every ordinal and byte field; array kind, count, stride, alignment, declared view and actual buffer bounds fail before decode |
| 3 | Skins, morph weights/targets and required extensions were ignored, returning undeformed or incomplete geometry as success | The unsupported deformation fields and every non-empty `extensionsRequired` list now fail loud |
| 4 | Non-finite payloads, zero/non-unit normals and quaternions, mirrored or degenerate local scale, and out-of-range float `COLOR_0` could reach the renderer | The content boundary validates finite float32 payloads, unit directions/rotations, supported scale parity and colour range |
| 5 | `normalMatrix` returned zero once a composed determinant fell below epsilon, so individually valid downscales could produce `normalize(0)` in the shader | It now uploads the signed cofactor direction: proportional to inverse transpose after normalization, division-free for tiny determinants, and meaningful for rank-two transforms |
| 6 | `addGltfNodes` checked only binding count, so a negative mesh/material id survived into draw-list indexing | Every binding is preflighted before the first scene mutation; upper bounds remain caller-owned because the adapter deliberately does not own `DrawContext` |
| 7 | `findByName` used recursive descent over a hierarchy whose depth comes from content | The same self-first, child-order traversal is iterative, so valid deep content cannot consume the C stack |

### Design pass

- **Ownership remains one-way.** `gltf.ms` produces CPU `MeshData` and value-only nodes;
  `gltfScene.ms` is the only adapter into caller-owned mesh/material ids and the existing
  `Scene`. Neither file creates a GPU handle, resource cache, asset registry or second tree.
- **The renderer remains a consumer.** M8 adds no frame-loop collection or allocation.
  Imported meshes use the M5 CPU copy and generation rebuild path; node transforms use M6's
  lazy world sync and flat draw list; scale normals use the existing per-object uniform.
- **The ABI is held at both sides.** The model block is 32 floats in `draw.ms`, two generated
  matrices at c0–c7, and a C static assertion over `modelParams_t`. The seven existing captures
  did not move when the normal transform changed.
- **The implementation is larger than the milestone's rough estimate.** The four loader files
  are 599 lines, 499 of them in `gltf.ms`, not about 200. The review did not replace explicit
  rejection paths with a schema abstraction: that would be a new decoder mechanism while the
  compiler still needs localized `Result` and ref-receiver workarounds. The file is long, but
  its accepted surface remains smaller than glTF; no extension dispatch, file I/O, material,
  animation, skin, texture or renderer ownership entered it.
- **The missing real export remains an honest follow-up.** The hand-built buffer proves bytes,
  hierarchy and scene insertion, not Blender compatibility or the on-disk path. Its PENDING3D
  row is the exit condition. The audit's clean-checkout corpus, shared 2D/3D commit lifecycle,
  scene-diversity/oracle and physical-device findings remain valid QC work outside M8.

### Numbers

Re-taken at reviewed tree `6d40d930e7a647731af48e0ad36d08f0c6df1028` from one
`sh scripts/gate3d.sh` run.

| | |
|---|---|
| Gate | GREEN with **1 SKIP** (`device`); the CPU-only glTF entry builds and runs without sokol |
| Tests | **627**, 10 added by M8 (3 name/tree, 7 glTF); 617 before M8 |
| Capture | seven configurations × four frames, byte-identical; no baseline replaced |
| Baselines | 24, checked against `docs/baselines3d.sha256` |
| Oracle | 30 cases agree with real Heaps and 3 diverge as declared |
| Allocation | zero frame-state growth over 300 frames; the guarded frame functions contain no `msArrayCopy` |
| Android | arm64 `libVoidAndroid.so`, **2 385 624 bytes**; physical device still skipped |

## M9 — animation clock, object keyframes and vertex-baked mesh frames

**Verdict: SHIP WITH FOLLOW-UPS, after two send-backs on different causes.** The defect pass
(`/code-review high`) and a fresh design reviewer read `git diff 3ce8c9b..303c785`. The design
pass sent it back on three blockers. The re-review of `0dbc6a6`/`fbe9227` closed those three
and sent it back again on a regression that the fix had introduced; `c632173` closed that one.
The causes differ, so the brief's rule for two consecutive send-backs (the design is wrong) does
not apply. Each fix below was verified in the main session with a mutation control or an oracle
case, not taken from the reviewers' word.

### Defect pass

| # | Finding | What I did |
|---|---|---|
| 1 | `bindTracks` wrote each target as it went, so a failed rebind returned an error and left the animation bound across two subtrees | Every name is resolved first; targets are written only when all resolve. Test "a rebind that fails keeps the previous binding whole" goes red when the old shape is restored |
| 2 | `update` accepted a non-finite `dt`, and the NaN frame reached `as int32` and a `Vec` index | `update` returns `Result` and refuses a non-finite advance, leaving the clock where it was (tested) |
| 3 | `addBakedFrames` had no caller, and a partial upload failure left orphan slots whose indices the caller never learned | The frames always take `frames.length` contiguous slots, and a refused frame keeps its CPU data for the rebuild. One campfire stone now runs upload, swap and the mid-run rebuild in every capture |
| 4 | A zero-frame clock divided by zero in `keys()` and read `keys[0]` of an empty `Vec`; the campfire's placeholder was one | `keys()` holds key 0 for fewer than two frames; `addTrack`, `forMeshes` and `syncPose` refuse `NoFrames` (tested) |
| 5 | `forMeshes` accepted negative mesh indices, and `-1` collided with the "nothing shown" sentinel | `BadMesh`; the sentinel is a private `NO_MESH` (tested) |
| 6 | The spin freezes after 32 keys, and no gate ran `syncPose` at runtime | Kept, and the doc now says the spin holds its last key (the captures end at frame 16). The bench now turns the spin on, so `syncPose` runs across its 300 frames |
| 7 | The gate's pending-stage comment still counted three enforced rows | Rewritten without a count |
| 8 | Comments over the playbook's length, including narrative history in the allocation stage | Trimmed to the external facts |
| 9 | A local `isFinite` duplicated std | `Number.isFinite` |
| 10 | `bound` and `hasSynced` duplicate derivable state; the allocation stage skipped the callees | The flags stay, because each has one writer and a test. The stage now also covers `keys`, `blendTo`, `setLocal` and `setMeshOf` |

### Design pass

**First pass: SEND BACK.**

- **Partial rebind.** The same bug as defect 1, verified independently by a probe.
- **Two divergences from Heaps were not written down.** `setFrame(8)` on four keys gave frame 0
  where Heaps' `while` loops stop on 4. A frame in (−1, 0) held key 0 where Heaps' truncating
  `Std.int` extrapolates backwards. Fixes: `setFrame` now matches the loops, and the one-shot
  case agrees with Heaps at 30 where the old port gave key 0. The row is renamed to
  `anim-never-extrapolates` and now covers both ends, with a new oracle case,
  `negative-speed-below-first-key` (Heaps −5, port 0).
- **`addBakedFrames` was untested.** Closed at the capture level, as defect 3.
- **Follow-ups the pass raised, all taken:**
  - The `syncPose` cache hid a target removed after a sync. Targets are now checked with
    `isLive` before the cache.
  - The cache could not be cleared when another writer moved a node. `forgetSync` does that
    now.
  - A one-key linear clip reported a change on every tick.
  - `blendPose` is now the extension `blendTo`.

  Each has a test, and the stale-target test goes red when the `isLive` check is removed.

**Second pass: SEND BACK, one regression.** While fixing `setFrame` I had made a loop at
`frameCount` show key 0, and I explained the oracle's 0 as "weight 1 blends into key 0". That
was wrong. `LinearAnimation.sync` clamps `frame >= frameCount` to the last key whether or not
the clip loops (`LinearAnimation.hx:153`). The oracle read 0 only because its helper's
`update` wrapped the frame first (`Animation.hx:340`). The reviewer showed it with a speed-0
case: Heaps 30, port 0. `c632173` restores the clamp and keeps that case as
`loop-at-frame-count-shows-last-key`. It now agrees with Heaps, and the comment on the other
case names the real mechanism.

**What the passes found sound:**

- No Hibernal vocabulary in `src/void3d`.
- The frame path allocates nothing. The gate checks it, and the reviewer also scanned the
  emitted C of the callees.
- Baked frames rebuild through the M5 path by construction.
- The byte-identity claim comes from a readback the reviewer re-ran.
- The tests that discriminate: the hemisphere flip, the cache, and the 12-changes count.

### Carried into M10 and later

- There is no headless test of `addBakedFrames`' first-index contract or of its refused-upload
  path. Both need a GPU, and today they are covered only by the captures.
- The stepped clock decides a key boundary with `floor` on an accumulated float. A rate that
  is not a binary fraction can show a key one update late (measured: 1/3 per frame).
- No glTF animation is decoded. The exporter's encoding is an open question in
  `docs/VOID3D.md`.
- `libVoidAndroid.so` grew 110 416 bytes over M8. The growth is not attributed.

### Numbers

Taken at code tree `98781380` from one `sh scripts/gate3d.sh` run.

| | |
|---|---|
| Gate | GREEN with **1 SKIP** (`device`) |
| Tests | **654**, 27 added by M9; 627 before M9 |
| Capture | seven configurations × four frames, byte-identical; no baseline replaced |
| Baselines | 24, checked against `docs/baselines3d.sha256` |
| Oracle | 41 cases agree with real Heaps and 6 diverge as declared, over three files |
| Allocation | zero frame-state growth over 300 frames with the spin animating; no `ArrayCopy` in the eleven guarded frame functions, read from freshly emitted C |
| Android | arm64 `libVoidAndroid.so`, **2 496 040 bytes**; physical device still skipped |

## M10 — rays, bounds and triangle hits, and the nearest pickable object under a tap

**Verdict: SHIP WITH FOLLOW-UPS, after one send-back.** Two passes read `git diff ab237d1..a3c30ae`: the defect pass
(`/code-review high`) and a fresh design reviewer. The design pass sent the milestone back on two
blockers, and both were in the fidelity record, not in the code. `3c4bec7` and `a55ba60` close
them together with the defect findings. The re-review of `a3c30ae..a55ba60` then gave
SHIP WITH FOLLOW-UPS. Every fix below was verified in the main session with a mutation control, an
oracle case or a gate run, not taken on the reviewers' word.

### Defect pass

| # | Finding | What I did |
|---|---|---|
| 1 | `campfireTap` passed host rows to `rayFromScreen` with `originTopLeft()`. On GL that function counts rows from the bottom, while touch rows count from the top | `campfireTap` and `campfirePixelOf` take and return host pixels, rows from the top, and flip the row on GL. The `pick` stage runs only the D3D11 branch, and the doc says so |
| 2 | A mirroring world matrix turns the winding over on screen, so the pick kept exactly the faces the GPU culls | `seenThrough` swaps `Back` and `Front` when the world 3×3 determinant is negative. The mirror test goes red when the swap is removed |
| 3 | The scale-0 test guarded dead code: a zero direction already fails every triangle's determinant | The guard is gone. The test stays as behaviour, and the doc gives the real mechanism |
| 4 | A mesh or material index outside the tables was skipped as a miss | `PickError.MeshOutOfRange` / `MaterialOutOfRange`, tested |
| 5 | `campfirePixelOf` indexed without checking that the node is live or is a mesh | It returns `Result<Vec3, SceneError>`, and the gate entry fails loudly on an error |
| 6 | The culling divergence was argued as forced by the inward-wound box builders, when those should be fixed instead | **Fixed at the root.** `addBox`'s top, right and left quads and `addPlane` were wound clockwise from outside; front and back already faced out. They are rewound, and the 28 capture frames stay byte-identical. The culling row now stands on its own: pick what the pass draws |
| 7 | The status line claimed M10 reviewed before a review existed | Closed by this section |
| 8 | `run_pick` FAILed without the gitignored readback harness | It SKIPs, as `run_captures` does |
| 9 | The owner walk is O(nodes × depth) | Kept and written under "Still missing". At tens of nodes and a tap per second it is not measurable, and carrying the owner down would take a second stack in `Scene` |
| 10 | Comments that restate the code | Removed. `PickHit.node` is renamed `owner`, which makes its comment unnecessary |

### Design pass

**First pass: SEND BACK.**

1. **A divergence was presented as Heaps behaviour.** `getCollider()` always yields an
   `ObjectCollider` or a `GroupCollider` (`Object.hx:679-710`), so `rayCastEventTargets`'
   downcast to `OptimizedCollider` is null and `checkInside` is never set (`Scene.hx:331`).
   I verified this in source. Measured against real Heaps, a ray starting inside a mesh's
   bounds gives Heaps −1 and the port 1, and the same collider with the flag set by hand
   agrees with the port. That is `pick-origin-inside-bounds`, with a `diverges=` case and a
   control case. Three more consequences of a flag in place of a collider are
   `pick-owner-is-a-flag`: hidden children, nested pickable nodes, and live geometry against
   a snapshot. Each is pinned by a test.
2. **The ordering argument was false.** The M4 eye is the target, in the middle of the depth
   range, so Heaps' distance from `camera.pos` does not order hits along the ray.
   `pick-distance-from-ray-origin` pins the port's order with two triangles 0.8 apart
   across the eye.

**Follow-ups the pass raised, taken:**

- The gate's `allocation` stage now also checks the pick entry's C. Control: an injected
  `Vec` copy in `meshHit` fails it (`meshHit=1`).
- The `pick` stage no longer claims to tap the drawn image. It says each tap is aimed
  through `project`, and the doc says what that leaves unproved.
- `pickableOwner` and `meshHit` are extensions.
- The compiler card's `Parked at:` names `cameraCheck.ms` too.
- The first-person history is out of the doc.

**Follow-ups the pass raised, not taken:** a readback in the `pick` stage, a hit-proxy shape
table, a `DrawContext` overload, the two thresholds stricter than Heaps', and one `BitSet` for
all scene flags. Each is written under "Still missing after M10" or already has its
PENDING3D row.

**Re-review of `a3c30ae..a55ba60`: SHIP WITH FOLLOW-UPS.** The reviewer re-ran the gate and
one mutation of its own: dropping the mirror swap reddens exactly one test. It checked the
rewound quads' cross products by hand and found all five sides and the plane facing outward.
Each rewound quad keeps its a–c diagonal, so the set of triangles is unchanged, which is why
the captures did not move. It confirmed the GL row flip against `texelAt` and `ndcOf`, and
confirmed that the fail-loud errors cannot fire in the campfire, because every external mesh
has an empty `MeshData` slot. Of its seven follow-ups, `c30e7d6` takes five:

- a test with a mirroring parent over a `Face.Front` child, and a second mirror cancelling it;
- `triangle-back-two-sided`, a `diverges=` case that puts `pick-culling-follows-material`
  under the oracle (Heaps −1, port 5);
- the outward-faces test pinned to exact entry and exit distances;
- a mesh-index check in `campfirePixelOf`;
- `pick.ms` added to the receiver-rule compiler card's list of sites.

It also noted that Heaps' own `new Interactive(obj.getCollider(), obj)` transforms the ray
twice; that note is now in `pick-owner-is-a-flag`. One follow-up is left: the GL row flip
lives in the example, and nothing runs it.

**What the passes found sound:** each piece is the Heaps function it names, and 20 oracle
cases agree. No Hibernal vocabulary is in `src/void3d`. There is no new GPU resource. The
frame path is unchanged, and the gate now also holds the pick path to no array copy. The
headless tests work at the arithmetic level.

### Carried into M11 and later

- There is no hit proxy (`Interactive.shape`): a thin model picks only by exact triangles.
- The `pick` stage never reads a pixel back. GL's row flip lives in the example and has never
  run.
- Owners cost O(nodes × depth), and nothing is timed.
- `pickNearest` takes two spans, and nothing stops a caller mixing two contexts' tables.
- Two thresholds are stricter than Heaps': `inverseAffine` 1e-10 against `EPSILON2` 1e-20.

### Numbers

Taken at tree `25796ff5` (*test(void3d): pin mirrored parents and two-sided picks against Heaps*) from one `sh scripts/gate3d.sh` run.

| | |
|---|---|
| Gate | GREEN with **1 SKIP** (`device`) |
| Tests | **767**, 22 added by M10; 745 before M10 on this rebased tree |
| Capture | seven configurations × four frames byte-identical, the rewound builders included; no baseline replaced |
| Oracle | 61 agree with real Heaps and 10 diverge as declared, over four files; `ray3d.cases` 20 + 4 |
| Pick | 3 taps through the drawn view with a snap remainder, all right; control red |
| Allocation | no `ArrayCopy` in the 11 frame-path functions or the 7 pick-path functions |
| PENDING3D | 19 rows (14 before M10: +5 new, and the builder row opened and closed) |
| Android | arm64 `libVoidAndroid.so`, **2 508 392 bytes** (+12 096 over M9); physical device still skipped |

## M11 — CPU particles on stream meshes, saturation in the look, and the side tables compacted

**Verdict: SHIP WITH FOLLOW-UPS, with no send-back.** Two passes read `git diff bbbd73e..79102bb`: the defect pass (`/code-review high`) and a fresh design reviewer. The design reviewer re-ran the gate at `79102bb` (GREEN) and measured one of its findings against real Heaps with an oracle case of its own. The fixes are `fd521d3`, `45ef7e3` and `6902a37`. Each was verified in the main session by a test, an oracle case or a gate run.

### Defect pass

| # | Finding | What I did |
|---|---|---|
| 1 | After a context loss, the rebuild remakes a stream empty with zero instances; a paused emitter whose owner writes nothing shows no particles | Kept, and written down: a stream keeps no CPU copy by design, and its owner holds the state to write it from. The contract (write every frame you draw) is in M11 as built; the campfire writes every frame |
| 2 | `gpu3dUpdateBuffer` returned quietly on an invalid or oversized buffer, and `writeStream` still reported the count | It returns 0 on refusal; `writeStream` answers `StreamError.BufferRefused` and draws nothing |
| 3 | `_Static_assert` against a `static const` is not an integer constant expression in portable C | The table length is `#define GPU3D_PROGRAM_TABLE_LENGTH`, which the assert reads; the `static const` msc imports is defined from it |
| 4 | `writeStream` never marks the renderer changed, so an on-demand host would freeze the snow | Not taken as code: the draw context has no renderer, and deciding to redraw is the host's, as with M9's `update`. A live emitter changes every step, and a host that runs one draws |
| 5 | `remakeStream` leaked the buffer it did get when the other was refused | It destroys it |
| 6 | The campfire's frame-clock comment ended up above `setupParticles` | Moved back above `setupAnimations` |
| 7 | `rebuildableMeshes` does not count streams | Not taken: "rebuildable" is "comes back with its contents", and a stream comes back empty |
| 8 | `addStreamMesh` repeated `addMesh` | It calls `addMesh` |
| 9 | Every stream makes its own corner buffer | Not taken: six vertices per emitter, and a shared buffer would be one more context-owned handle to rebuild |
| 10 | Comments naming the milestone in the gate and the campfire | Reworded to say what the configuration is |

### Design pass

**SHIP WITH FOLLOW-UPS.** The pass found the port faithful function by function, including the order of every random draw in each shape and the force draw order after the y/z exchange. It found nothing named for Hibernal in `src/void3d`, no allocation in the emitted C of the particle path, and every new GPU resource rebuilt. It judged both deferred decisions sound (closed effects as look fields, stream meshes with no CPU copy) and the compaction correct in each case asked: row equals last, subtree, stale id, draw order, lights and pick.

**Its findings, and what I did:**

1. **An undeclared divergence, measured.** `Burst.time` was `float32` against a `float64` cycle, so a burst at 0.1 fired one update late (Heaps 3 particles, port 0). `Burst.time`, `ColorKey.time` and `globalLife` are now `float64`. `burst-at-a-tenth` pins it, and putting the field back in `float32` mismatches it.
2. **A false claim about Heaps in a comment.** `Emitter.draw` evaluates `globalSize` before `Particles.draw` returns on an empty list. The port now does the same, which is tested (the sequence moves on an empty write), and the comment is gone.
3. **Stream meshes cannot be released.** Written under "Still missing after M11". The draw context has no mesh removal of any kind.
4. **Capacity lived in mutable state.** It is now `ParticleEmitter.capacity`, fixed at `create` and tested.
5. **Silent failures.**
   - The buffer update fails loud (defect 2).
   - The campfire logs a particle failure in the frame and names setup failures with its own `ParticleSetupError`.
   - Sokol's one-update-per-frame rule is written under "Still missing", not enforced.
6. **Comments.** The particles header is two lines, and the block over `updateEmitter` and the comments that restated code are gone.
7. **Evidence.**
   - `particle-random-per-life` now says why it is deliberate.
   - The program-count test stays: it is what reddens when a member is added past the table.
   - `rebuildableMeshes` is kept (defect 7).

**Follow-ups the pass raised, not taken here:** a per-material saturation for a single fading object, and a CPU reference of `colorSaturate` tested against Heaps. Both are under "Still missing after M11".

### Carried into M12 and later

- Stream meshes cannot be released, and nothing enforces one update per buffer per frame.
- Saturation is screen-wide and has no CPU reference.
- Particles are alpha-tested; nothing is translucent.
- A palette swap is a 2.4 ms refill; a cross-fade needs kept LUTs.
- `m11particles_*` and `m11look_*` were adopted from this port's own run, like the M3 images: they hold the port to itself.
- From M10: no hit proxy; the GL row flip has never run. Particles are not pickable.

### Numbers

Taken at tree `16e9bcbb` (*fix(void3d): name the campfire's particle failures and put its comments back where they belong*) from one `sh scripts/gate3d.sh` run.

| | |
|---|---|
| Gate | GREEN with **1 SKIP** (`device`) |
| Tests | **792**, 25 added by M11 |
| Capture | ten configurations × four frames byte-identical against 32 baselines; the seven standing ones unmoved; `capture look` holds frames 1 and 16 to `m3palette_*` |
| Oracle | 69 agree with real Heaps and 11 diverge as declared, over five files; `particles3d.cases` 8 + 1 |
| Allocation | no `ArrayCopy` in the frame path, the particle functions and `writeStream` included; control red |
| Bench | zero frame-state growth over 300 frames with particles on; 0.070–0.109 ms CPU per frame over five single runs |
| PENDING3D | 22 rows: one removed, four new |
| Android | arm64 `libVoidAndroid.so`, **2 682 840 bytes** (+174 448 over M10, not attributed); physical device still skipped |

## M12 — saturation as a lit-material parameter, held to Heaps' colorSaturate

**Verdict: SHIP WITH FOLLOW-UPS, after one send-back.** Two passes read `git diff ea4b620..3a0b2be` (the first cut): the defect pass (`/code-review high`) and a fresh design reviewer. The design pass sent it back. The rework is `ec6d800..6f6b26f`, and the same reviewer re-reviewed it. Every finding below was checked in the main session before anything was changed.

### Defect pass

| # | Finding | What I did |
|---|---|---|
| 1 | `run_grey_reference` could PASS having compared nothing: an error from `magick compare` parsed as 0 levels, and the images of the previous frame were reused | Fixed, then made moot. The first fix checked every `magick` status, cleared the images per frame and required a numeric PAE (checked on real frames, and it failed at −0.9). The rework then deleted the function (design finding 1) |
| 2 | A failed build or run left the previous gate's frames for a later comparison | `run_capture` clears its frames before it builds and after a failed run (`6b3c4c4`) |
| 3 | The shader comment and the as-built said a headless test tied the GLSL to the matrix; the test ties an MS copy of the formula | The test is named for the scalar form, and the as-built says it checks the formula, not the GLSL. The GLSL is now held to the CPU byte for byte (below) |
| 4 | The mask covered only changed pixels, so a stone that was never greyed would drop out silently | Moot after the rework. It was covered anyway: a stone not greyed changes the frame, and the frame hash fails |
| 5 | The acceptance named `<TREE>` | Filled with the tree hash |
| 6 | The example picks the greyed piece by index | Not taken: the example already chooses each piece's parent by the same index ranges. The rework greys piece 0, the ground, alone |
| 7 | Three `-fx` passes per frame are slow | Not taken, measured: 0.24 to 0.31 s per pass. The rework removed them |
| 8 | The luma weights appear in four places; `within` repeats `approx` | Not taken: the test keeps its own weights on purpose, so that it is not checking the code against itself, and the oracle pins them to Heaps. `approx` allows 0.005, which is more than one 8-bit level; `within` allows 1e-6 |
| 9 | Two tests log even when they pass | They log only when the assertion fails |
| 10 | Six lines of design prose above `run_grey_reference` | Cut to the one external fact, then deleted with the function |

### Design pass

**First review: SEND BACK.** The code was sound. The blocking findings were claims and evidence:

1. **An undeclared divergence from Heaps, written up as agreement.** The first cut greyed the lit colour *after* the lights. Heaps' `ColorMatrix` added to a pass greys `pixelColor` *before* `AmbientLight` multiplies the light in:
   - `LightSystem.computeLight` puts the light shaders at the head of the list;
   - `Cache.compileRuntimeShader` reverses it.

   I checked this in the source at the pin; it has not been run. The first cut had been argued from one app's readability (a fading object stays grey by the fire). The human decided that a general renderer takes Heaps' position. The saturation now greys `baseColor` before the lights (`ec6d800`), and the three false texts are gone.
2. **The acceptance named no tree.** It names one now.
3. **Only an adopt run had produced the new baselines.** A plain gate run reproduced them: the gate at `76c4665b` with `GATE_DEVICE=1` is GREEN with no SKIP, and all three new configurations match their committed hashes.
4. **The reference check could pass without checking.** It is gone. The GPU is now held to `colorSaturated` byte for byte: the ground greyed in its vertex colours on the CPU must draw the frames its material draws at the same amount (`campfireGreyCpuCapture` against `m12greydirect_*`). With −0.7 on the CPU the frames differ in every ground pixel.

**Follow-ups it raised:**
- Named offsets: `TOON_LEVELS` and `TOON_SATURATION`, done, used by the example.
- The pixel check tested only the luma half at −1: moot. The amount is now −0.75 and the check is byte identity.
- Style: `luma` is an extension, and the WHAT comment and the long gate comment are gone.
- The test count: fixed to four more than the 824 before M12.

**Re-review: SHIP WITH FOLLOW-UPS.** All four blocking items closed. The reviewer rebuilt the change mask of frame 11 (only the ground between the grass blades changed) and re-measured every pixel count in the as-built. It noted that two independent paths agreeing byte for byte is what shows the ground greyed and where. Its follow-ups, all taken:
1. The Milestones row still said "after lighting". Fixed.
2. The shader comment named the deleted grey reference. It names `campfireGreyCpuCapture`.
3. **An old gap M12 brings to light.** `litFs` adds the point lights without multiplying them by the material's colour; Heaps multiplies every light in. Checked in the shader. It is M7's, and no row recorded it. `light-params-divergence` now says so, and the as-built says a greyed object keeps a warm tint from the fire. The lighting is not changed here: that would move every baseline, and it is not this milestone's.
4. The as-built told the send-back as history. It keeps the measurement, and the story is here.
5. The GPU is held to the CPU for one colour at one amount. Written under "Still missing after M12".

It did not re-measure the −0.7 control or the emulator counts, whose shots are not committed.

**It confirmed, with its own runs:**
- the port of `colorSaturate`, including `multiply3x4`;
- all four shader backends keep the `amount == 0` skip and the same expression;
- nothing Hibernal-shaped in `src/void3d`;
- no per-frame work;
- nothing new to rebuild after a context loss.

### Carried into M13 and later

- A greyed object reads as grey only under a palette with a grey ramp. The campfire palette turns a grey brown. Under that palette, greying the ground at −0.75 moves only about 13 300 pixels, against 162 800 with the palette off.
- Only lit materials have a saturation.
- No fade over time has run.
- The order against Heaps has been read in the source but not run.
- The point lights are added without the material's colour (M7's, now in `light-params-divergence`).
- The GPU is held to the CPU for one colour at one amount.
- The rest of M11's list, less its two saturation items.

### Numbers

Taken at tree `76c4665b` (*docs(device): record the ground greyed by its material on the GLES3 emulator*) from one plain `sh scripts/gate3d.sh` run. The commits after it change a shader comment and documents only; the shader header is unchanged.

| | |
|---|---|
| Gate | GREEN, no SKIP, with `GATE_DEVICE=1` (the device stage on the `pixellight` emulator) |
| Tests | **828**, 4 added by M12 |
| Capture | ten standing configurations byte-identical; three new, 8 new baselines (40); the CPU-greyed ground byte-identical to the material's |
| Oracle | 75 agree and 11 declared, over six files; `color3d.cases` 6 + 0 |
| GLES3 emulator | ground greyed: 20 789 pixels against the same build at 0; 274 between two shots of that build |
| PENDING3D | 23 rows, one new |
| Android | arm64 `libVoidAndroid.so`, **2 704 216 bytes** (+16 368 over the 2 687 848 before M12, not attributed) |

## Audit before M13 — the whole of `src/void3d`, read against the porting and decision rules

**Verdict: no defect in the running paths; three design findings that no milestone review could
see, because they came with the spike before M5.** Read in the main session at tree `7913307e`
(*docs(void3d): M12 review, a send-back for the light order and the ship*), after the human
reframed void3d at M12 as a renderer for any game. Read line by line: `scene`, `draw`,
`renderer`, `passList`, `pipelineCache`, `pixelArtRenderer`, `camera` (its head), `pick` and
`shader3d.glsl`. The other modules were checked by the cross-cutting searches and measurements
below. Most of them are held to real Heaps by the oracle.

### Findings

| # | Layer | Finding | What was done |
|---|---|---|---|
| 1 | core | The directional light is a step, `step(0.35, n·l) × power`, where Heaps' `DirLight` is Lambert, `color × max(n·l, 0)` (read, not run). It ignores the material's toon levels, and the point lights' quantization adds a fixed 0.35 bias. From the spike (`a394a82`), with no row | Row `dir-light-stepped`. M13, which rewrites that formula, decides it |
| 2 | core | `Program.Billboard` is the campfire's grass-and-flame shader: a `grassColor` uniform, a `texel.r` mask, a four-cell atlas written as `* 0.25`, the light sampled `0.25` above the root, `mix(…, emissive)` for the flame. The decision rule forbids app vocabulary in `src/void3d` | Carried, for the milestones that make void3d general |
| 3 | core | Every scene program writes the pixel-art preset's two targets (normal, depth packed in alpha), and colour alpha is the outline mask. Core and preset are split in MetaScript but not in the shaders: a plain forward preset could not reuse `Program.Lit` | Carried |
| 4 | core | Nothing is ever released from a `DrawContext`: meshes, materials and the uniform pool only grow. The M11 follow-up named streams only | Carried, widening follow-up 1 |
| 5 | core | No frustum culling: nothing outside a test sets `NodeFlag.Culled`, and no "Still missing" said so | Carried |
| 6 | gate | The `allocation` stage held scene, animation and particles, not the render path. Measured by hand on the emitted C of the bench entry: 26 render-path functions, no array copy | Added to the stage (`377de90`). Control: a written `Vec` copy in `drawItem` fails it (`drawItem=1`) |
| 7 | example | `frameCampfire` returns silently at eight sites. A fifth point light is refused by the core and then dropped by the example with no message; in a host view the same return would abort as "returned without commit()" | Fixed (`fb9a2ca`): every failure site logs its error by name. In a host view the return after it still aborts on the missing `commit()`, now after the log |
| 8 | docs | "Data types" said billboard atlases rebuild from CPU data like meshes; they are the caller's | Corrected |
| 9 | compiler | Workarounds re-probed on msc 0.2.55 (`8cdd91c6`): `BitSet`, `==` on large structs, `distinct` and a simple generic `ref` now work; `ref this` and returning a `Span` still do not | Flags and colour mask are `BitSet`s (`1c86c56`, `3493cfa`), row `scene-flags-not-bitset` deleted, `sameState` gone, Compiler notes re-dated |
| 10 | docs | The "Device" open question still said the `.so` had only been built; the compiler notes were headed 0.2.53; the glTF comment scoped the loader by the customer's exporter | Corrected |
| 11 | style | 727 comment lines against 4 550 code lines; 49 blocks longer than three lines, most written before the comment rule was narrowed on 2026-09-21 | Not swept: the comment playbook forbids cleaning a file as a side effect. A pass of its own if the human wants one |
| 12 | style | `refresh` is mis-indented at `scene.ms` 617–630; `uploadMesh` keeps a half-made buffer pair where `remakeStream` destroys it; `writeUniforms` truncates or leaves values silently | Fixed. The indentation (`40a9f2d`). `uploadMesh` destroys the buffer it made when its pair is refused (`e9458b6`), not pinned: no headless test can make the driver refuse. `writeUniforms` refuses a length that is not its block's, so `beginFrame` and `renderFrame` answer a `Result`, and the camera and light writes run before a new context is adopted (`0f89fed`; control: truncation back reddens `pipelineCheck` and crashes the suite in the new renderer test) |
| 13 | gate | Found by that control: `msc test` exits 0 when the test binary crashes, and the `tests` stage passed any log that lacked the word "failed" | The stage fails without the summary line (`0d4f70c`). Second sighting on `~/metascript/.inbox/compiler/2026-09-23-crash-exit-status-lost.md` |

**Confirmed, with the check named:**
- nothing in an API name or behaviour is Hibernal's, beyond the defaults the brief allows and finding 2 (grep over `src/void3d`);
- the frame and render paths copy no array (the `allocation` stage, now with the render path);
- everything the library owns has a way back after a context loss: meshes with CPU data, streams, pipelines, shaders, targets, the LUT, the sampler (read in `beginFrame`, `adoptContext`, `sweepStaleMeshes`);
- too many lights is an error, not a silent drop, and a stale `NodeId` is caught by its generation.

**Also found:**
- A gate from 2026-09-23 had been orphaned for over a day, its `msc` running from a binary since renamed by a toolchain sync. It held nothing a later gate needed. The kill was refused by the harness and is the human's.
- Building under the long session scratch path fails; the second sighting is in `~/metascript/.inbox/compiler/2026-09-23-emit-c-long-path-windows.md`.

### Numbers

Taken at tree `9c6e03d4` (*docs(void3d): record the audit before M13*) by the land gate with
`GATE_DEVICE=1`, after the rebase onto void2d's P3. The follow-up column is the plain gate at tree
`15a91e87` (*test(void3d): fail the tests stage when msc test prints no summary*).

| | at the land | after follow-up 11 |
|---|---|---|
| Gate | GREEN, no SKIP | GREEN, one SKIP (device) |
| Tests | **863**, 35 of them void2d's P3 | **864**, one refused-frame test added |
| Capture | 52 frames byte-identical to the 40 committed hashes | the same |
| Oracle | 75 agree and 11 declared, over six files | the same |
| Allocation | frame, render and pick paths, no array copy | the same |
| Device | `pixellight` emulator, 23 colours, largest 40%, after a cold start of the app | not run |
| PENDING3D | 23 rows: `scene-flags-not-bitset` deleted, `dir-light-stepped` added | the same |
| Android | arm64 `libVoidAndroid.so`, **2 702 880 bytes** (2 704 216 at M12) | **2 740 448 bytes**, the example's error messages |

The first land attempt failed at `device`: the emulator resumed the app from its quickboot
snapshot, and it drew black at 30 fps with no `EGL_CONTEXT_LOST` reaching Void. A cold start drew
the campfire.

## M13 — every light multiplies the material's colour, the directional light is Heaps' Lambert

**Verdict: SHIP WITH FOLLOW-UPS, after one send-back on the docs.** Both passes read
`git diff e070605..3eafa2c`: the defect pass (`/code-review high`) and a fresh design reviewer.
The design pass sent it back on two false statements; the shader it would have merged as it
was. The rework is `3906bcc..c7570af`, and the same reviewer re-read it and shipped it.

### Defect pass

| # | Finding | What I did |
|---|---|---|
| 1 | `billboardFs` still adds the point lights unmultiplied, and M13 deleted the only row text that recorded it | Row `billboard-points-added`, sentinel in `billboardFs` (`3906bcc`) |
| 2 | The `LightInstance` comment still justified a separate `power` by "quantizes total energy", untrue for the directional light since M13 | The reason is per point light; the directional `power` is recorded as a field Heaps lacks with the same product (`3906bcc`) |
| 3 | The same stale reason in `light-params-divergence` | Same fix, same commit |
| 4 | The status line said "reviewed" before any M13 review existed | Written with this section |
| 5 | The multiply was held only by a probe in scratch space, so the next retake could lose it | Gate stage `multiply` (`5d1f4f6`): 0 off in the four M13 frames, 2 016 to 2 304 off in the four pre-M13 frames |
| 6 | The GLES3 noise control was two shots of one build in one boot, the comparison across two boots | Redone in one boot, both builds, with the boot-to-boot noise measured (`611fe9a`) |
| 7 | The device recipe named only a gitignored entry | The configuration calls are quoted inline |
| 8 | `pointLightAt` divides by the material's toon levels, and nothing checks them: 0 draws NaN | Not fixed here: it came with M7 and is part of the ramp that leaves the core. Written into `point-light-toon-quantized` |
| 9 | "Carried into M13" still points at `light-params-divergence` for the added point lights | The lit half is fixed; the billboard half has its own row now. The carried list below replaces the pointer |

### Design pass

**First review: SEND BACK, docs only.** The shader is Heaps' additive model; the refusals were two claims:

1. **"A greyed object takes no tint from them" was false.** Under `saturated(base) × light` a grey ground of luma L takes `L × (1.0, 0.45, 0.16)` from the fire: the fire's hue at the ground's own brightness. The probe's premise says the same. What M13 removed is the fire's colour on a dark object. The row and "M13 as built" now say a light scales with the object's colour.
2. **The reason in `light-params-divergence` described the lighting before M13.** Defect findings 2 and 3.

Follow-ups it listed, and what happened:
- the billboard row (defect finding 1);
- tracked docs cited "follow-up 10", an item number of the machine-local arc card: they now cite this file's "Audit before M13" findings 2–3;
- the multiply as a gate stage (defect finding 5);
- the stale-library `grep` could not fail: the pre-M13 header spells the step `step(0.3499999940395355`, and `max(dot(` is in `pointLightAt` either way. It greps the full literal now: 6 hits in the pre-M13 library, 0 in M13's;
- "the shader text is shorter" was not measured: it says "not attributed";
- per-pixel lighting and `normalWeight 0 = isAmbient` had no line: one sentence each.

**Re-review: SHIP WITH FOLLOW-UPS.** It checked that the `multiply` stage cannot fail on 8-bit rounding alone (the worst rounding is about 1.56 levels, the threshold 1.53, and a whole-number difference of 1 always passes) and that the purge fix matches the cache on disk. What it still found:
- the acceptance mixed two trees: it now names the tree of the last gate;
- the stage would blame the multiply for a clipped channel: it now fails first on a ground pixel at 255 in the plain frame or its prediction, naming the clip (`c7570af`; 0 in the M13 frames, 72 to 96 near the fire before M13; a brightened control trips it);
- a sentence in "M13 as built" had drifted after another: moved back;
- the eviction's glob matched nothing until `c5d4bcf`, yet every retake changed pixels, so the compiler card `2026-09-20-object-cache-ignores-headers.md` may no longer reproduce. Not measured: every build here also cleared the checkout's own cache, which is enough to explain it, and `out/tmp/cacheRepro` is not in this worktree. Carried.

**Found while reworking.** `purge_stale_shader_objects` globbed `cache/objects/*.o`, a layout the cache no longer has; objects sit in per-stamp directories. It greps them recursively now (`c5d4bcf`).

### Carried into M14 and later

- The point lights are stepped and their levels unchecked (`point-light-toon-quantized`), and the billboard adds them unmultiplied (`billboard-points-added`): the pixel-art look in the core, with "Audit before M13" findings 2–3.
- No specular and no non-additive model.
- The palette-on campfire takes Lambert in steps the palette never had to express: shaded stone sides fall to its blues. Content, and the caller's.
- Whether the object cache still ignores headers, on the installed msc.
- The rest of the audit's carried list, unchanged.

### Numbers

Taken at tree `03c134d` (*test(gate): name a clipped channel before the multiply's ratio*) from
one `GATE_DEVICE=1 sh scripts/gate3d.sh` run; the commits after it are docs.

| | |
|---|---|
| Gate | GREEN, no SKIP |
| Tests | **864**, none added: the formula lives only in the GLSL |
| Capture | 52 frames byte-identical to the 40 hashes retaken in `a170d81`; the rebuilt, CPU-greyed and look-restored configurations still byte-identical to the ones they share hashes with |
| Multiply | 0 of 162 824 to 162 836 ground pixels off the ratio, 0 clipped, in four frames |
| Oracle | 75 agree and 11 declared, over six files |
| Device | `pixellight` emulator running the M13 build, 24 colours, largest 38% |
| GLES3 emulator | pre-M13 against M13 in one boot: 13 306 / 13 540 pixels; noise at most 1 245 |
| PENDING3D | 24 rows: `dir-light-stepped` deleted, `point-light-toon-quantized` and `billboard-points-added` added |
| Android | arm64 `libVoidAndroid.so`, **2 791 992 bytes** on msc `2925176a`; 2 795 728 before M13 was on `145f4a08`, so the difference is not M13's |

## M14 — the core's programs and the pixel-art preset's, a program map, a forward preset

**Verdict: SHIP.** Both passes read `git diff 53dd526..d692df8`. The defect pass (`/code-review high`) found ten issues. The design reviewer gave SHIP WITH FOLLOW-UPS: it would have merged the code as it was, but refused two claims in the docs. The human asked for the version that is not redone later. So the design reviewer's follow-ups 1–3 were fixed in M14 rather than carried into M15, and that turned into a change of design, so the same reviewer read the rework (`8d41e7f..0dd99fb`) again. That re-review gave SHIP, with four notes, all fixed in the last commits.

### Defect pass

| # | Finding | What I did |
|---|---|---|
| 1 | The forward frame never recorded the view it drew, so `campfireTap` and `campfirePixelOf` read the zero view | The frame records it, with a one-to-one blit view (`3f53c34`). This is read, not run: the `pick` stage taps the pixel-art path |
| 2 | A `Lit` material without its block goes through the forward preset, and slot 3 keeps the previous item's values | `beginFrame` refuses a block the drawn program does not read, decided from the shader desc (`8d41e7f`) |
| 3 | `copyFs` fetches with no clamp | Clamped, as `blitFs` is (`b408563`). The forward baseline did not move |
| 4 | Nothing holds `ProgramMap`'s four bits to the program count | `_Static_assert(GPU3D_PROGRAM_TABLE_LENGTH <= 16)` (`e3f2008`) |
| 5 | The ramp check keys on the named program, ignores the block's slot, and lets NaN through | It keys on the drawn program. The slot and length are the core's check. NaN fails `>= 1` (`8d41e7f`) |
| 6 | The program is resolved twice, `drawPassList` has a `ProgramNotDrawn` path nothing can reach, and that path needed the compiler workaround | Resolved once in `beginFrame`. `drawPassList` cannot fail. The workaround and its row are gone (`8d41e7f`) |
| 7 | The example builds a forward renderer for every configuration | Not taken. The example is the harness of both presets, and the extra mesh and material are written down in "M14 as built" |
| 8 | Forward ignores pan and snap | It takes both. Read, not run (`3f53c34`) |
| 9 | Three comments longer than three lines | Cut (`6d321f5`) |
| 10 | The shared-block assert missed `vertexParams` and the slots | All four blocks, by size and by slot (`e3f2008`) |

### Design pass

**First review: SHIP WITH FOLLOW-UPS.** It would not land two claims in the docs as written:

1. **"Core `Lit` is Heaps' forward shading", and the point light "is Heaps' product with the power folded in".** Heaps' `PointLight.calcLighting` divides by `params · (d, d², d³)`. The core keeps the spike's window, `(1 − d/radius)²`. The row, "M14 as built" and `light-params-divergence` now say so.
2. **"Inside the range of same-build noise".** 1 577 is above every same-build figure. The claim now rests on where the differences fall: in the three pairs located, they are inside one box around the flickering fire, and nothing differs outside it.

Its follow-ups, and what happened:
- **The map swaps programs but not the data they read.** `beginFrame` refuses a material whose block is not the one the drawn program reads (`RendererError.MaterialBlock`). "The one it reads" is taken from the shader desc through `uniformBlockLength`, not from a hand table, and a test holds every length the CPU writes.
- **A lit material without a block, in the forward preset.** The same check.
- **The map's capacity.** The static assert.
- **`Copy` and the map's Heaps counterpart were half named.** `Copy` is written down as a same-size fetch with alpha 1. The map is written against `Output.setupShaders`, which composes the material's shaders, the outputs and the light system's.
- **The ramp check.** It became an exhaustive `match` over the drawn program; MetaScript refuses a non-exhaustive enum match (measured).
- **Two cores on one `DrawContext` would forget each other's pipelines after a context loss.** `PipelineCache.generation` (`5f34ce2`). Read, not run.
- **The compiler card's parked site would vanish with the worktree.** Moot: nothing is parked.
- **The test count's origin.** 882 is eleven more than the 871 of the M13 land. Of those 871, seven are void2d's P3.5, which landed in between.

**Re-review of the rework: SHIP.** It confirmed every follow-up closed, and recounted 492 test declarations and the size arithmetic. Its four notes:
1. A refused `beginFrame` had already grown and written `Renderer.drawn`. It now checks every item and both block lengths before it writes anything; only then does it write the blocks and record the programs. That also closes an older gap it did not name: a good camera with bad lights used to leave the camera block written. `drawPassLists` states that it takes the span `beginFrame` accepted.
2. The ramp check's `_ => true` would miss M15's billboard. The `match` names every program now, and reads the map the core holds.
3. `renderer:blockFits` runs per item per frame; it is in the `allocation` list now.
4. Forward pan, snap and picking are marked "read, not run".

**Found along the way.** `return Result.err(…)` inside a statement `match` arm does not take the function's return type: compiler card `2026-09-26-return-in-match-arm-loses-function-type.md`. Nothing in void is parked on it now.

### Carried into M15 and later

- **The core billboard, and the preset's form of it.** Its block will not be the core one's, and `beginFrame` refuses a mismatch. So the M15 row first decides how a material carries the preset's floats.
- No program can come from outside `src/void3d`.
- The forward preset has no sRGB, no MSAA and no scaling, and its context-loss rebuild has never run.
- The core point light keeps the spike's window. Porting Heaps' `params` is open (`light-params-divergence`).
- The rest of the audit's carried list.

### Numbers

Taken at tree `1869a4c` (*test(gate): the render path list covers blockFits*, `ab43adc`) from one plain `sh scripts/gate3d.sh` run; the commits after it are docs.

| | |
|---|---|
| Gate | GREEN, one SKIP (device) |
| Tests | **882**: eleven added by M14, seven of the 871 before it were void2d's P3.5 |
| Capture | 13 standing configurations, 52 frames byte-identical to M13's 40 hashes; `campfireForwardCapture` new, 4 hashes (44) |
| Multiply | 0 ground pixels off the ratio, 0 clipped |
| Oracle | 75 agree and 11 declared, over six files |
| Allocation | frame, render (now with `drawnFor`, `blockFits`, the ramp check and the forward preset) and pick paths, no array copy |
| GLES3 emulator | the forward preset drawn (`gles3Forward.png`); the pixel-art frames unmoved outside the fire's flicker box |
| PENDING3D | 23 rows: `point-light-toon-quantized` deleted, `billboard-points-added` moved |
| Android | arm64 `libVoidAndroid.so`, **2 903 984 bytes** on msc `2925176a` (+111 992 over M13; +32 828 of it embedded shader sources) |

## M15 — a core billboard in Heaps' textured-particle shape, and the pixel-art preset's form of it

**Verdict: SHIP.** Both passes read `git diff fc8a712..c76047d`. The defect pass (`/code-review high`) found ten issues. The design reviewer gave SHIP WITH FOLLOW-UPS, with nothing blocking. The human's instruction since M14 is the version that is not redone later, so every follow-up that touches the mechanism was fixed in M15 (`5f2df53..30f33e0`). One was left to the human, because it moves pixels. The rework added two refusals to `beginFrame`, which changes its contract, so the same reviewer read the rework again. That re-review gave SHIP.

Before the row, three decisions were the human's, taken with measurements:
- **The preset's floats** are reserved in the core billboard block, not in a block per preset (a new mechanism for two floats).
- **The grass and flame stay byte-identical.** A probe of the preset's form on the new layout measured it first: 52 frames identical, with a reassociation control and a 1.002 control.
- **The forward capture shows the grass**, and `m14forward_*` is re-baselined in its own commit.

A fourth fact came from the probe: sokol-shdc refuses a block read by both stages, so the frame is a uv rect per instance, as Heaps' CPU `Particles.draw` writes it.

### Defect pass

| # | Finding | What I did |
|---|---|---|
| 1 | Nothing checks that a mesh's vertex layout is the one its program reads; `Particle` and `Billboard` are two instanced layouts on the same corners | `beginFrame` refuses it, `RendererError.VertexLayout`, through an exhaustive `vertexLayoutOf` (`5f2df53`) |
| 2 | `beginFrame` takes a `Billboard` material with no texture or sampler, and sokol aborts | `RendererError.MaterialTexture`, read off the shader desc (`05acd4d`) |
| 3 | The billboard discards on the texel's alpha only; the instance and material alpha never hide it | Both programs discard on the whole alpha. The pixel-art frames did not move (`7ab2487`) |
| 4 | `AtlasTile.ofFrame` takes a negative width | Refused (`a341e6c`) |
| 5 | `pipelineCache.ms` still says `VertexLayout` has three members | Four (`3171f28`) |
| 6 | `BILLBOARD_INSTANCE_STRIDE` is a hand copy of `describeLayout` | Attribute order asserted in `gpu3d.c`; `layoutFloats` holds every writer's stride in a test (`020a930`) |
| 7 | The campfire recomputes a tile per tuft and keeps a literal `4.0` | `AtlasTile.split` once, `ATLAS_CELLS` (`a969b11`) |
| 8 | A flame frame with no tile builds a mesh over an empty buffer | The flame's instances are built once and kept; there is no fallback (`a969b11`) |
| 9 | `AtlasTile` repeats void2d's `Tile` (`src/void2d/types.ms`) | Not taken. void3d has never imported void2d, and a shared `h2d.Tile` crosses into that lane; void2d's computes its uv in float32 where Heaps uses Float. Written under "Still missing after M15" |
| 10 | The ramp check's short-block path has no test | A test: a short billboard block is refused by the core through the preset (`c6ab510`) |

### Design pass

**First review: SHIP WITH FOLLOW-UPS.** It checked each piece against Heaps by file and line (`Particles.hx`, `Tile.hx`, `BaseMesh.hx`, `Texture.hx`, `VertexColorAlpha.hx`, `GpuParticle.hx`, `Material.hx`), the normal's direction against `camera.ms`, the thirteen floats against `describeLayout`, and the five items of "Audit before M13" finding 2 (gone from `src/void3d`). It ran the tests (888) and looked at `m14forward_1`.

Its follow-ups, and what happened:
1. **The quad's anchor is the caller's and was not written down.** Heaps centres a particle on its position; the campfire's corners start at the root. Written down as `billboard-anchor-is-the-callers` (`2f9bfbb`). Whether the core owns centred corners is the human's call, because it moves the campfire's pixels.
2. **Instance and material alpha had no effect.** Defect 3.
3. **Nothing tied the instance layout to `gpu3d.c`.** Defect 6.
4. **Nothing checked that a program and a mesh layout go together.** Defect 1.
5. **Nothing checked the core billboard's colour.** A gate stage, `unlit` (`6e1f1be`). The flame is unlit with colour 1, so its three texel colours must be in every forward frame; none of them is in the frame without billboards. Lighting the flame fails it. The lit path is held by the baseline alone, and that is written down.
6. **Style.** The campfire's long lines, the style stage's path list, the block written by position, the empty-`Vec` fallback. `2036949`, `a969b11`; the campfire is inside `style` now.
7. **Doc accuracy.** The positive control's range was quoted from three configurations; it is 213 208 to 228 616 and 3 228 to 3 488 across all of them. The probe is not kept. Both are corrected (`30f33e0`).
8. **`ofFrame` refuses what Heaps tolerates.** Written down. The negative width is defect 4.
9. **A zeroed block, and the tile's aspect.** A zeroed block draws nothing (alpha 0). Heaps' height from the tile's aspect is not ported (`particle-size-world-units`).
10. **`pushTo` was reachable from the simulated context loss.** The rebuild replays the kept flame instances now.

**Re-review of the rework (`c76047d..30f33e0`): SHIP.** It confirmed every finding closed, or written down where it belongs.
- It reran the tests (892).
- It regenerated the shader header after the last comment and found it identical to the committed one.
- It recounted the GLES3 frame.

Its notes, none blocking:
1. **The device builds' sizes were in no kept log.** They are in `tests/device/README.md` now (`4536231`). The emulator pixel counts are not kept, as the README says.
2. **`vertexLayoutOf` is a hand table.** The static asserts tie each preset program to the core program of its layout, not a program to its layout. A wrong entry would refuse the captures' own items, so the gate would catch it.
3. **A bad mesh index panics.** A mesh index outside `context.meshes` panics instead of being refused by name, as `drawItem` did before M15.
4. **The first refusal wins.** A lit billboard without levels and on the wrong layout reports `RampLevels`, because the preset's check runs first. Both refuse before anything is written.
5. **The texture check sees presence only.** After a context loss it counts stale handles as bound. That is the protocol that has the caller remake its handles.

**Found along the way.**
- A `Result` narrowed by an early return is not narrowed two loops deep: compiler card `2026-09-26-narrowing-lost-two-loops-deep.md`, row `nested-loop-narrowing-bound`.
- msc was synced from `2925176a` to `598ca62e` during the milestone, so the gate's `.so` delta is not M15's. The size is given on one msc from the device builds instead.

### Carried into M16 and later

- **Who owns a billboard's corners**, centred as Heaps' or the caller's (`billboard-anchor-is-the-callers`). This is the human's call, before any emitter writes billboards.
- An emitter that draws textured particles (`Data.frame` over `frames`).
- Two ports of `h2d.Tile`, void2d's and `AtlasTile`.
- An exact check of the lit billboard.
- M14's carried list: programs from outside `src/void3d`, the forward preset's sRGB, MSAA and scaling, the point light's window.

### Numbers

Taken before the rebase below, at the commit that landed as `4536231` (*docs(device): record the two pixel-art builds' sizes*), from one `GATE_DEVICE=1 sh scripts/gate3d.sh` run; the commits after it are docs. The code is that of `6e1f1be`, gated the same way without the device.

| | |
|---|---|
| Gate | GREEN, no SKIP (`GATE_DEVICE=1`, the M15 pixel-art build running on the emulator) |
| Tests | **892**: ten added by M15 |
| Capture | 14 configurations; 52 pixel-art frames byte-identical to their hashes; `m14forward_*` retaken by design (4 hashes, 44 in the manifest) |
| Unlit | the forward flame's 3 texel colours in all 4 frames, 10 to 87 pixels each |
| Multiply | 0 ground pixels off the ratio |
| Oracle | 75 agree and 11 declared, over six files |
| Allocation | frame, render (now with `vertexLayoutOf`, `texturesFit`, `slotBound` and `billboardLevels`) and pick paths, no array copy |
| Device | `pixellight` emulator, 23 colours, largest 38% |
| GLES3 emulator | the forward billboards drawn (`gles3Billboard.png`); the pixel-art frames unmoved outside the fire's flicker box |
| PENDING3D | 25 rows: `billboard-points-added` deleted; `billboard-normal-toward-camera`, `billboard-anchor-is-the-callers` and `nested-loop-narrowing-bound` added |
| Android | arm64 `libVoidAndroid.so`, **2 990 464 bytes** on msc `598ca62e`. On one msc, the pixel-art device entry is +68 360 over M14, of which +24 943 are embedded shader sources |

**Rebased before landing.** `main` had moved to `fc8a712`, void2d's P4. The rebase had one conflict, `src/test/index.ms`, where both sides added an import, and gave every M15 commit a new hash; the hashes above are the landed ones. The rebased tip (`971eebf`, before this note) gated GREEN with no SKIP:
- 952 tests: the 892 above, and 60 of void2d's P4;
- the same 44 hashes byte for byte, and `unlit` with the same pixel counts;
- the device stage;
- the same 2 990 464-byte `.so`.

## M16 — the core's quad from the vertex index, and a billboard's anchor

**Verdict: SHIP WITH FOLLOW-UPS, after one send-back.** The defect pass (`/code-review high`) read the first cut and found nine issues. A fresh design reviewer then read the cut with those fixed and gave SEND BACK with two blocking defects. The same reviewer read the rework and gave SHIP WITH FOLLOW-UPS. The follow-ups that touch the mechanism were fixed in M16. What is left needs a device, a browser or a decision (below). The whole milestone is `967c6b7..7f944d0`: the compiler sweep, the row, the mechanism, the gate stage and the new baseline.

Before the row, three decisions were the human's:
- **void3d is ordered for any game**, not for Hibernal. Heaps owns the shape; where Heaps has no answer, a reference engine does, Bevy first.
- **The core owns the quad, and a billboard carries Bevy's anchor per instance.** Heaps always centres; Bevy's `Anchor` defaults to the centre.
- **The corners come from the vertex index**, Bevy's way, not from a shared corner buffer: a **NEW MECHANISM**, approved on its own.

The compiler moved under the milestone. msc was synced to `c54a8671`, which refuses a write through a `const` binding, and the whole repository stopped building. The sweep is its own commit (`967c6b7`) and gated GREEN alone: 952 tests, the 44 hashes byte for byte, so the compiler moved no pixel.

### Defect pass

| # | Finding | What I did |
|---|---|---|
| 1 | The pixel-art light point is taken above the instance's position, which is now the anchor's point, and nothing says so | Written at `BILLBOARD_LIGHT_HEIGHT` and in "M16 as built"; no test holds it (carried) |
| 2 | `GpuMesh.external(layout, buffer, count)` read `count` as vertices or instances by layout | `external` is gone; each constructor fixes its layout (`fullscreen`, `billboards`, `streamMesh`, `meshFor`) |
| 3 | `QUAD_VERTEX_COUNT` is a hand copy of the GLSL table's length | Kept, with the one-line pointer: no assert can see the table, and the captures fail if the two drift |
| 4 | `drawsQuads` is a hand copy of `describeLayout` | A test holds it against `layoutPerInstance`, read off `describeLayout` |
| 5 | Nothing checks an anchor's x; every capture anchors across the centre | `campfireAnchorCapture` and the gate's `anchor` stage (`5ce2819`, baseline `7f944d0`) |
| 6 | The stream and the billboard mesh built the quad shape twice | One `quadMesh` |
| 7 | The quad from the vertex index had not run on GLES3 | The emulator ran all three programs (`tests/device/README.md`); no phone has (carried) |
| 8 | Docs: the row still open, no as-built | Written |
| 9 | The first cut sat in one `chore` commit | That was a hold commit while the sweep was probed; the milestone is five commits |

### Design pass

**First review: SEND BACK**, two blocking defects, both confirmed in `sokol_gfx.h` before the fix.
1. **The quad layouts could not make a pipeline on WGPU or Vulkan.** The first cut put every instance attribute in vertex buffer 1 and left slot 0 empty. sokol's validator skips an empty slot, but its WGPU and Vulkan backends end the buffer list at the first slot with no stride (`sokol_gfx.h:19547`, `:22663`), so buffer 1 was never declared. D3D11 and GL never showed it. The instances now step in slot 0, `bindItem` binds them there, and a test holds each quad layout to a per-instance buffer 0 and every layout to no floats in buffer 1. The 44 hashes stayed byte-identical.
2. **`external` still built any layout.** `external(VertexLayout.Billboard, 0, 6)` passed `beginFrame` and reached sokol with no instance buffer. Now no constructor takes a layout. `beginFrame` refuses a quad-layout mesh with a vertex buffer, with other than six vertices, or with instances and no buffer, as its own member, `RendererError.QuadMesh`. `drawItem` skips a mesh with nothing to draw, so a stream whose remake was refused draws nothing instead of reaching sokol with an empty slot.

Its follow-ups, and what happened:
- Bevy applies its anchor on the CPU; the quad is a table of six rather than bits; `Tile.dx/dy` is not the anchor. Written in "M16 as built". The reviewer accepted the argument against a PENDING3D row: a zero anchor is Heaps' centre, as M9's stepped sampling was an addition.
- **The pixel-art preset's placement had no check of the anchor's x.** Both billboard programs now place a corner through one function, `billboardPoint`, so the forward `anchor` stage holds both.
- Separate refusal members, tests for a four-vertex quad and a quad with no buffer: done.
- The billboard stride comment restated the layout: removed. The quad comment claimed Bevy's quad was the same table: corrected.

**Re-review of the rework: SHIP WITH FOLLOW-UPS.** It confirmed both blockers fixed, `billboardPoint` shared, and the acceptance on the current tree. Its notes:
1. **`hasNothingToDraw` was missing from the allocation list:** listed.
2. **It also skips a lit mesh whose re-upload was refused,** which used to reach sokol: written in "M16 as built".
3. **The row still said the six corners come "as Bevy's sprite shader makes its quad":** corrected.
4. **A line of 104 columns in `programMapCheck.ms`, a comment reflow with a stub line:** fixed. That test file is not in the gate's style paths.
5. **No plain gate had reproduced the four new hashes; both runs that had them were adoptions:** the final gate below is a plain one.
6. **A struct literal can still build a per-vertex mesh with instances,** and nothing refuses it. Carried.

**Controls,** run in the session. The anchor left out of both programs moves 75% of the pixel-art and forward frames. The anchor's x mirrored in the core billboard alone leaves every standing capture byte-identical and fails only `anchor` (the flame moves 16 pixels left). Leaving out the quad-shape refusal lets the test binary die in `_sg.valid`.

### Carried into M17 and later

- **No phone and no WGPU run** of the quad from the vertex index. The slot-0 layout is what WGPU and Vulkan need, read from sokol, not run.
- The pixel-art preset's light point above the anchor has no check.
- A struct literal can build a per-vertex mesh with instances.
- An emitter that writes billboards (`Data.frame` over `frames`); it can now use the core's anchor.
- M15's list: two ports of `h2d.Tile`, billboards with no rotation, ratio or saturation, alpha-tested only; M14's: programs from outside `src/void3d`, the forward preset's sRGB, MSAA and scaling, the point light's window.
- Next, agreed with the human: resource lifetime (M17), a perspective camera with frustum culling, textured meshes.

### Numbers

From `GATE_DEVICE=1 sh scripts/gate3d.sh` at `7f944d0`, a plain run, no adoption, on msc `c54a8671`.

| | |
|---|---|
| Gate | GREEN, no SKIP (`GATE_DEVICE=1`, the M16 pixel-art build with particles running on the emulator) |
| Tests | **956**: four added by M16 |
| Capture | 15 configurations; 56 standing frames byte-identical to their 44 hashes; `m16anchor_*` new (4 hashes, 48 in the manifest) |
| Anchor | the bottom-left flame 18 pixels right at both edges, rows unchanged, in all 4 frames |
| Unlit | the forward flame's 3 texel colours in all 4 frames, 10 to 87 pixels each, the same counts as M15 |
| Allocation | frame, render (now with `drawsQuads`, `isQuadShaped` and `hasNothingToDraw`) and pick paths, no array copy |
| Device | `pixellight` emulator, 24 colours, largest 38% |
| GLES3 emulator | pixel-art, forward and pixel-art-with-particles builds render; the pixel-art frames against M15's move only inside the fire's flicker box |
| PENDING3D | 24 rows: `billboard-anchor-is-the-callers` deleted |
| Android | arm64 `libVoidAndroid.so`, **3 023 208 bytes**; the sweep commit, M15's code on the same msc, is 2 996 992: +26 216, not attributed |

## M17 — resources released behind counted generational ids

**Verdict: SHIP WITH FOLLOW-UPS, after one send-back and two re-reviews.** The defect pass (`/code-review high`) read the first build and found ten issues, eight fixed in `aa80932` and two rejected with measurements. A fresh design reviewer then read that tree and gave SEND BACK with one blocking defect; the rework is `3e89bf0` and the docs after it. The same reviewer read the rework twice more and gave SHIP WITH FOLLOW-UPS both times; those follow-ups were fixed in M17 as well (`9a0cfee`, `51f6d25`). The milestone is `47bb114` onwards: the row, the slot table's move, the pool, the ids and holders, the upload and stream fixes, the churn example and stage, both passes' fixes and the docs.

Before the row, the human decided the model:
- **Explicit release on generational ids, with counted holders.** Asked which of Heaps' `dispose` and Bevy's strong `Handle` to follow, the human asked what Bevy does; read from source, Bevy is both layers (an `AssetIndex` value in the draw path, an `Arc` handle that frees on its last drop). The model taken is the lower layer with the count in the table: whoever adds holds once, a mesh node holds its mesh and material, a loader lets go with `defer`. A **NEW MECHANISM**, approved on its own.
- `defer` was the human's pointer: with counting, a plain `defer` is enough, and no `errdefer` (which MetaScript does not have) is needed.

The compiler moved under the milestone once more: M16's land waited on recompiler `19c3d513` (the for-of copy), synced as `35601908` before the row. A first gate on it failed every link (`libmingw32.lib … UnableToWriteArchive`); a plain `zig cc` rebuilt zig's cache and nothing in void changed.

### Defect pass

| # | Finding | What I did |
|---|---|---|
| 1 | A baked animation stored its frame ids without holding them: a loader that released its frames freed every frame the node did not show | The animation holds its frames from `forMeshes` until `releaseMeshFrames` |
| 2 | `doomBuffersOf` reads ownership from the generation, and `addMesh`'s comment promised it destroyed none of a caller's buffers | The generation is the ownership marker since M5; the comment says so. The design pass and its re-reviews later made `addMesh` refuse every mesh that is neither the caller's nor a stream, and any that names buffers made in no context |
| 3 | The presets wrote into their own screen material slots without checking the id | `renderFrame` refuses a preset whose screen material or mesh is gone, by name |
| 4 | `drawItem` returned silently on a stale id, and the scene discarded failed releases | `drawItem` is `unreachable` on a stale id; an over-release is refused at the caller (`HeldOnlyByNodes`, later `OnlyPinned`), so the scene's own releases cannot fail |
| 5 | A write, then a context loss, then `beginFrame` would drop the write or allow a second | Rejected: the Android bridge restores the context in `voidPlatformSurfaceAcquire`, before the frame callback, so one callback sees one generation |
| 6 | The renderers' pool check read only fresh floats | `UniformPool.fits` counts released ranges of each length first |
| 7 | No way to drop a level's holds but `remove` per subtree | Heaps' `removeChildren` |
| 8 | `sg_query_stats` per stream write copies a large struct | Rejected: measured 1 344 bytes, a few writes a frame; a commit listener would have to be registered again after every `sg_setup` |
| 9 | Material range ownership was an O(N) scan per `addMaterial` | An owned flag per range in the pool |
| 10 | The generation-wrap rule was written twice | `nextGeneration` in `slots.ms`; the three claim-and-grow sequences stay, since each grows its own tables |

### Design pass

**First review: SEND BACK**, one blocking defect, confirmed in the code before the fix.
1. **A material's release freed whatever range its public `uniforms` field named at the time, not the range it owned.** The table is written by hand (the presets write textures), and a block written into a material by hand was a state the as-built itself called reachable. Releasing such a material trapped, or freed another material's range so that two materials came to share floats silently. The context now keeps the range each material was added with (`materialBlocks`) and releases that; `beginFrame` refuses a material whose field no longer names it (`UniformsReplaced`).

Its follow-ups, and what happened:
- **Only node holds were protected** from an over-release: pins now cover a node's and a baked animation's holds (`OnlyPinned`, `NotPinned`), and `releaseMeshFrames` checks all pins first and goes all or none.
- **Value copies of holders** (a `Scene`, an animation) and **ids that carry no context:** `remove` checks every pin of the subtree before it changes anything, so a second remove through a copy is refused by name; a copy that finds another holder's pin can still take it. Written in "M17 as built" and carried.
- **The renderers' own blocks could be released by anyone:** the core owns them.
- **The allocation stage did not list the new per-frame functions:** listed, and they pass.
- **`doomedFor` was a copy of `buryDoomed`'s predicate under test:** gone; the drop branch of `buryDoomed` itself runs in a test. `remakeStream` dooms what it replaces. `addMesh` refuses a mesh made in a context that it could not remake (`Unrebuildable`).
- **Three divergences from Heaps were not written:** Heaps counts no materials (the material hold is Bevy's `MeshMaterial3d`), Heaps' zero is not final (it allocates again on the next render), and `set_primitive` decrefs first. Written; the claim that Heaps' over-release disposes under live meshes is gone.
- **The churn stage's blind spots:** rows for free ranges, doomed buffers and the scene's tables, every row required, and the control required to grow each one a release would hold flat.
- **Gate headers named `HEAD` while the tree held the next commit:** the header says so now.
- Comments: the deferral's stated reason was wrong (a stale item is refused before any draw), corrected; WHAT-comments removed; `fits` answers a `Result`.
- `drawItems` (unused) is gone; `drawScreen` answers a named error.
- Carried: checked setters for the tables.

**Re-review of the rework: SHIP WITH FOLLOW-UPS.** It confirmed the blocker fixed and the follow-ups done, and found six more, all fixed in `9a0cfee`:
1. **A node whose pin a copy took could never be removed:** `remove` and `setMeshOf` refused it, since its freed mesh counted as no pin. A freed id now holds no pin, and such a node lets go of nothing.
2. **`releaseMeshFrames` answered `StaleMesh` for a missing pin:** `AnimationError.NotPinned`.
3. **`addMesh` still took a mesh at generation 0 that named buffers:** it takes only the caller's meshes and streams.
4. **The pin checks were quadratic** in the nodes of a subtree: a count per slot (`tallyMeshPin`), linear.
5. **"A renderer made again after an unload is not refused"** claimed more than holds, since a renderer has no release: corrected.
6. **`beginFrame` named a replaced block `MaterialBlock`** when its slot or length differed: `keepsItsUniforms` is checked first.

**Last review: SHIP WITH FOLLOW-UPS.** It proved the gate had run the committed tree (the diff hash in the header matched `git diff 3e89bf0 5fba6a4`), and found five small things, fixed in `51f6d25` and the docs:
- "it can always be removed" was too strong: a robbed node stays `NotPinned` while another holder keeps its mesh or material live;
- the size was the gate before last's;
- `addMesh` took a stream at generation 0 that named a buffer;
- a reused slot did not reset its tally;
- git's line-ending warnings leaked into the gate header.

### Carried into M18 and later

- **Copies and contexts:** an uncounted copy of a holder, and ids that name no context.
- **The tables are written by index,** with no checked setter.
- **Textures, images, samplers and views have no lifetime;** a renderer has no release.
- **The pool reuses a range only at its exact length.** Bevy's slab allocator packs meshes into shared buffers; here each mesh takes one to three.
- **No device run** of anything in M17; the emulator was down for the whole milestone.
- M16's list: no phone and no WGPU run of the quad, the pixel-art light point above the anchor, a struct literal can build a per-vertex mesh with instances, an emitter that writes billboards; M15's and M14's lists.
- Next, agreed with the human: a perspective camera with frustum culling, then textured meshes.

### Numbers

From `sh scripts/gate3d.sh` on the tree committed as `51f6d25` (the header's diff hash `6e4a084a578b` matched the tree before the commit), on msc `35601908`.

| | |
|---|---|
| Gate | GREEN with the `device` stage skipped: the emulator had been shut down for memory before the milestone, and the human chose to land M16 without it |
| Tests | **995**: 34 added by M17 (slots 5, the pool 7, lifetime 18, the renderers' refusals 4) |
| Capture | 15 configurations, 60 frames byte-identical to their 48 hashes; no baseline added or retaken |
| Churn | 310 frames: every growth row 0 (mesh and material slots, live meshes and materials, reserved floats, free ranges, doomed buffers, the scene's live nodes and its table, sokol's 4 live buffers); 310 second stream writes refused; the control out of buffers after 42 frames, 127 live |
| Allocation | frame, render and pick paths, M17's functions included, no array copy |
| Oracle | 75 agree with real Heaps, 11 diverge as declared |
| Bench | `meshes=40 pipelines=5`, no frame-state growth |
| PENDING3D | 23 rows: `upload-mesh-leaks-on-replace` deleted |
| Android | arm64 `libVoidAndroid.so`, **3 294 232 bytes**, +128 800 on M16's 3 165 432 on the same msc |
| Compiler | `2026-09-29-assert-accepts-a-result.md` opened; `2026-09-23-catch-struct-literal-clang.md` has a second sighting |

## M18 — several layers in one frame

**Verdict: SHIP WITH FOLLOW-UPS, after one send-back and one re-review.** The defect pass (`/code-review high`) read the first build and found ten issues: eight were fixed and two rejected. A fresh design reviewer read the same tree and gave SEND BACK, with three blocking defects that overlapped the defect pass. The rework is `279dfde` and `476301a`, and the docs after them. The same reviewer read the rework and gave SHIP WITH FOLLOW-UPS; those follow-ups were fixed in M18 as well (`e2c1184`). The milestone is `9739a3b` onwards: the decisions shared with void2d, the row, the split, the mixed frame, the compose, aborts and HUD stages, both passes' fixes and the docs.

Before the row, on 2026-09-29, the human handed the unification of void2d and void3d to the references, relayed by the main void session and said in this window: approvals the references settle are taken, and direction stays his. The four decisions are in VOID3D.md "Shared with void2d". M18 is the first of them because it gives an app author something at once, a HUD over a 3D scene, with no new mechanism and no file of void2d's touched.

### Defect pass

| # | Finding | What I did |
|---|---|---|
| 1 | The allocation stage listed only the two `renderFrame`s, now five-line shorthands, so neither half was read | Both halves of both presets are listed, and so are the core's three guards |
| 2 | `drawToScreen` cleared the changed flag, erasing a change made between the halves | Cleared at the end of a successful prepare, when the inputs are taken |
| 3 | `compose` failed where the test answers SKIP (exit 3, no readback) and ignored `GATE_SKIP_CAPTURE` | Both are SKIP |
| 4 | The draw count was checked on the first frame only | Checked on all three frames: 1, 1, 0 |
| 5 | The as-built said `mixedFrame` prepares the 3D frame first; it did not | The test prepares first now, which is the order the doc argues for |
| 6 | The HUD panel had to equal ImageMagick's half exactly | Within 1 per channel: the claim is the composition, not the GPU's rounding. D3D11 measures 0 |
| 7 | `magick` was called with no guard | SKIP without it |
| 8 | A centred quad hides a flipped layer | The quad sits off centre |
| 9 | Two comments were left wrong by the change (`drawPost`'s, the pick entry's placement) | Fixed |
| 10 | The empty `Stage.Blit` arm keeps two sources of truth for the last stage | Rejected: `planStages` describes the whole frame and `screenKey(Stage.Blit)` reads it; the prepare half runs the offscreen stages and the screen half the last |

### Design pass

**First review: SEND BACK.** It confirmed the design: the split falls where Heaps' base renderer ends a frame (`process` up to `resetTarget`, then `copy(from, null)`), and the caller owns the pass and the commit, as `Engine.render` does. It found three blocking defects, each confirmed in the code before the fix: the allocation stage's blind spot (defect 1 above), the flag cleared in the wrong half (defect 2), and the false as-built sentence (defect 5).

Its follow-ups, and what happened:
- **Which pass is open is not checked.** Carried to M20. Tracking the open pass needs every pass to open in one place, and void2d opens its target passes itself. Written in "Not done here".
- **The prepared flag was not tied to a frame, and each preset had its own copy.** The core now holds it (`openPrepare`, `closePrepare`, `openScreen`), stamped with sokol's `frameIndex`. A screen draw in a later frame than its prepare stops.
- **Bare `unreachable`s became reachable by a release between the halves.** They now print named messages, and the stale comments are corrected.
- **Divergences not written:** `drawToScreen` is swapchain-only and full-screen, where Heaps renders into any target (`setOutputTarget`); the copy is opaque, so 3D over 3D is not delivered; and the row credited `fwd.Renderer` with a copy that is `pbr.Renderer`'s. All written.
- **Acceptance gaps:**
  - The pixel-art prepare-twice guard had no test. Both presets now have headless abort tests.
  - The controls were run by hand. Both are gate lines now.
  - `compose` passed without its summary line. The line is required.
  - `aborts` searched the build log. It reads only the run log.
- **§14:** the example's frame functions answered `false` after a `console.log` and took a boolean mode. They answer `Result<int32, CampfireError>` and take `FrameShare`. `stepScene`'s older booleans are unchanged.
- **A refused layer in an embedded view:** the HUD entry still opens the screen pass and commits when the campfire refuses, and EMBED.md says a closure must.

**Re-review of the rework: SHIP WITH FOLLOW-UPS.** It confirmed the three blockers fixed and the follow-ups done or argued, accepted both rejections, and found six more:
1. **The kept flag had no test:** moving the clear back into the screen half left every stage green. `mixedFrame` now marks the renderer changed between the halves and requires `needsFrame` after the commit; with the old placement it fails.
2. **The later-frame stop had no test:** `VOID_MIXED_SCREEN_NEXT_FRAME=1` prepares, commits and draws the next frame, and must stop.
3. **Gate checks that could pass for the wrong reason:** the panel's number is checked to be a number, and the controls must fail for the intended reason ("inside the quad", "the opaque bar").
4. **The new deferrals had no PENDING3D rows:** `screen-pass-unchecked`, `screen-output-swapchain-only` and `copy-opaque`, with sentinels at both screen halves.
5. **Stale text:** a "first renderFrame" comment and the status line, fixed. VOID2D.md's audit still says `mixedFrame` draws the cube and that `renderer.endFrame` imports the bridge's commit: void2d's file, left to its arc and named in its card's neighbours.
6. **The campfire's refusals lost their cause:** the inner error is logged where the frame is refused.

### Carried into M19 and later

- **The open pass is not checked** (M20's door).
- **3D over 3D and a 3D view in a UI panel** (M20's targets, and a blended copy).
- **void2d's `Scene` has no halves** (void2d's arc).
- A refused `renderFrame` in an embedded view aborts as "returned without commit()"; that was so before M18.
- M17's list: copies and contexts, the tables written by index, textures and renderers without a lifetime, the pool's exact-length reuse, no device run.

### Numbers

From `sh scripts/gate3d.sh` on the code of `e2c1184` (the header's diff hash `d57d28799fb2` is that commit plus VOID3D.md's status line), on msc `35601908`.

| | |
|---|---|
| Gate | GREEN with the `device` stage skipped: no emulator |
| Tests | **995**, none added: the new checks are abort programs and gate stages |
| Capture | 15 configurations, 60 frames byte-identical to their 48 hashes; no baseline added or retaken |
| Compose | 7 200 quad pixels blended over the 3D frame, 69 600 outside identical; the control fails all 7 200; a second prepare and a screen draw after a commit each stop |
| HUD | 4 frames, byte-identical outside, bar exact, panel within 1 (0 measured); the control fails 4 of 4 |
| Aborts | 4 programs, each stops and names the call |
| Allocation | frame, render and pick paths, M18's functions included, no array copy |
| Android | arm64 `libVoidAndroid.so`, **3 312 448 bytes**, +18 216 on M17's 3 294 232 |
| PENDING3D | 26 rows: three added |
| Compiler | `2026-09-29-static-extension-on-aliased-same-name-type-ambiguous.md` and `2026-09-29-duplicate-import-name-binds-first-silently.md` opened, from the naming probes for M19 |

## M19 — the names shared with void2d, and the stop on a misused handle

**Verdict: SHIP WITH FOLLOW-UPS, every follow-up fixed in the milestone.** The defect pass (`/code-review high`) read the build and found ten issues; nine were fixed and one rejected. A fresh design reviewer read the same tree and gave SHIP WITH FOLLOW-UPS with eight findings, and every one was fixed in M19 (`5074202`, `ada6f91`). The same reviewer then read the fixes (below). The milestone is `22dd074` onwards: the row, the rename, the error rule and the statics, the as-built, the fixes.

The rule came from the references before the row ("Shared with void2d"). Heaps throws on misuse, `h3d.scene.Object.toMesh` and `h2d.Object.addChildAt` both do, and Bevy's `World::entity` panics. void2d's P5, which the human decided, stops on a stale handle. The split between stopping and answering is Bevy's: `World::entity` panics and `get_entity` answers, and `Assets::get` answers an `Option` for an asset. So a node call stops, and a question or an asset id answers.

### Defect pass

| # | Finding | What I did |
|---|---|---|
| 1 | The campfire's flicker drove `fireLight` even when setup had bailed before it was set, and now stopped with a misleading message | `setupDraws` answers `CampfireError.SetupRefused`, and no frame runs after a refused setup |
| 2 | `liveRow` called an id that names no row "stale, the row 0" | It says the id names no node of this scene |
| 3 | The row named `Transform3D.at` and still read **planned** | `fromTranslation`; done at the end |
| 4 | The rename made `Bounds3D`'s `toString` say `Bounds3D{…}` beside `Bounds{empty}` | Back to Heaps' `Bounds{…}` shape for both |
| 5 | `syncMeshFrame` reported a pin taken through a copy as `StaleTarget` | `AnimationError.NotPinned` |
| 6 | `syncPose` checks liveness twice per track | Rejected as a cost: two integer compares per track. The check was dead anyway (design finding 6), and is gone |
| 7 | `campfirePixelOf` answered `NodeNotFound` for a live node that is not a mesh | Its own `PixelOfError` |
| 8 | Only two of the stopping entries had an abort program | One per entry: nineteen programs |
| 9 | `churnScene` kept an alias left by the unwrap | Gone |
| 10 | A comment named `NO_NODE`; an abort declared a context it never used | Fixed |

### Design pass

**SHIP WITH FOLLOW-UPS.** It read every node-handle entry: each checks before it touches state. It read the emitted C: the live path allocates nothing, and no type still collides with void2d but `BlendMode`, which M20 owns. Its findings, and what happened:
1. **The aborts measured two entries of about ten.** One program per entry, nineteen in all, and the as-built lists them.
2. **The campfire stopped on a failed setup, with the wrong cause.** Same as defect 1. `liveRow` names an id that is not a row.
3. **`addGltfNodes` answered `SceneRefused` for a stale parent** while the calls it wraps stop. It stops too, through the exported `liveRow`, as void2d exports its own.
4. **The allocation stage could not see a string built on the live path.** The messages moved into `stopOnDeadId` and `stopOnWrongKind`, which only the stopping path calls. The stage now fails any listed frame- or render-path function that builds a string, a rule for all of them rather than a check on two.
5. **Three error mappings named the wrong error.** `NotPinned` in `syncMeshFrame`, `PixelOfError` in the campfire, and the baked stone's setup error.
6. **A dead liveness check in `syncPose`,** already made for every track before the loop. Gone.
7. **"void2d and void3d in one file" was not measured.** `tests/integration/bothLayers.ms` and the `both layers` stage cover it: every function name both layers export resolves to its own layer on `main`'s void2d.
8. **Doc leftovers:** the row, stale names in `gpu3d.c`, `bounds.ms`, `boundsCheck.ms`, `scene3dCheck.ms` and PENDING3D, and Heaps' `toMesh` as the kind check's precedent. Fixed.

**Last review: SHIP WITH FOLLOW-UPS.** It confirmed every fix: the nineteen aborts, of which the two whose mesh ids are also stale guard the order of the checks; the setup guard; the string check, which finds nothing in `liveRow` and `kindRow` and six hits in `stopOnDeadId` on the emitted C; the error names; and `bothLayers.ms` covering every shared function name. Its follow-ups, fixed in `1a4dbc0`:
- the acceptance named the tree before the fixes;
- `addGltfNodes` stops but had no abort program: `gltfUnderStaleParent`, twenty in all;
- the fixes left unused imports in `gltfScene.ms` and eight aborts;
- `syncMeshFrame`'s `NotPinned` had no test: a copy of the scene takes the pin of a mesh no frame holds, and the swap answers `NotPinned`. "No frame after a refused setup" is marked as read from the code.

### Carried into M20 and later

- **`BlendMode`**, the one shared type left, goes through M20's door.
- **void2d's P5 names** (`setVisible`, `remove`, `setName`, …) join `bothLayers.ms` when its arc rebases, with its own renames.
- M18's list: the open pass unchecked, 3D over 3D, a 3D view in a UI panel, void2d's `Scene` halves.
- M17's list.

### Numbers

From `sh scripts/gate3d.sh` on tree `5238df235a32` (commit `1a4dbc0`), on msc `35601908`.

| | |
|---|---|
| Gate | GREEN with the `device` stage skipped: no emulator |
| Tests | **993**: three moved into abort programs, one added (`NotPinned` through a copy) |
| Aborts | **20** programs, each stops and names the call: one per stopping entry, and M18's four |
| Capture | 15 configurations, 60 frames byte-identical to their 48 hashes; the HUD and compose checks unchanged |
| Both layers | every function name the two layers export resolves to its own layer (void2d as on `main`) |
| Allocation | frame, render and pick paths: no array copy, and now no string built |
| Oracle | 75 agree with real Heaps, 11 diverge as declared; the MetaScript preludes on the new names |
| Android | arm64 `libVoidAndroid.so`, **3 301 672 bytes**, -10 776 on M18's 3 312 448 |
| Compiler | `2026-09-29-try-on-a-non-result-passes-the-checker.md` opened |

## M20 — one GPU door, programs and layouts by registration

**Verdict: SHIP.** The first defect and fresh principal-engineer design passes both
returned SEND BACK. After the repairs, the defect re-review returned SHIP and the
design re-review returned SHIP WITH FOLLOW-UPS: document the migration boundary,
bounded registry contract and final acceptance. Those documentation follow-ups are
recorded here and in VOID3D.md "M20 as built"; the final read-only documentation
review returned SHIP with no factual mismatch or remaining blocker.
The reviewers read source/docs only; the owning session ran the reproduction and gate.

### Defect pass and repairs

| Finding | Repair and proof |
|---|---|
| A foreign layout registered first shifts void3d's layout base, but its program table kept local ordinals | `gpu3d.c` `registerOnce` translates the table. `gpu3d.ms` `vertexLayoutOf` reads the registered mapping instead of maintaining a second map. The foreign-first consumer exercises the shifted layouts. |
| `drawItem` indexed the shared uniform-mask cache with local program ordinals | Both mask queries use `doorProgram`. Before the repair, the real foreign-first lit draw stopped with `VALIDATE_DRAW_REQUIRED_BINDINGS_OR_UNIFORMS_MISSING`; after it, both registration orders pass the readback. |
| Signed registration counts could underflow or overflow the registry cursor | `door.c` refuses negative counts before mutation and compares capacity against `limit - current`. Four abort programs cover negative and `INT32_MAX` counts after a seeded registration. |
| Invalid registry ids silently selected entry zero | Invalid program/layout ids now stop by name; two abort programs cover them. |
| Diagnostic-text snapshots and a duplicated layout table did not prove a consumer | Three incidental tests were removed, not re-pinned. The foreign C unit has its own generated shader and draws through the door in `mixedFrame.ms`. Obsolete backend-forwarding and test-only wrappers were removed. |

### Design pass

The shared ownership matches Heaps' `h2d.RenderContext` (`RenderContext.hx` inheritance,
`pass`, `pushTarget`) using h3d's engine, textures and passes. Bevy supplies the
[shared resource-creation precedent](https://github.com/bevyengine/bevy/blob/0f38358f/crates/bevy_render/src/renderer/render_device.rs)
and [shader handles plus vertex layouts](https://github.com/bevyengine/bevy/blob/0f38358f/crates/bevy_material/src/descriptor.rs).
The bounded C registry is **NEW MECHANISM**, not a literal port of Bevy's implementation.
`src/gpu` imports no void3d code; the foreign shader/table lives under `tests/integration`.

Registration ids live for the process and depend on import order; they are not persistent
asset ids. The 64-bit key supports sixteen registered programs and eight layouts.
Beyond either limit the key needs another word; registration refuses rather than truncating.
The source/acceptance re-review found no remaining blocker in the offsets, bounds,
pass guards, context reconstruction or steady-path allocation.

### Acceptance

`sh scripts/gate3d.sh` on code tree `2d357a5ffe7de6c3eea20f4759427b213f41e7c9`
(`3388622`; gate header: `fca803a` plus tracked diff `965a60f031f6`), msc
`35601908`, D3D11, 2026-09-30: **GATE GREEN with 1 skipped stage**.

- **990 tests**, versus M19's 993: three incidental text/table tests removed.
- **34 abort programs**, versus 20: pass misuse, malformed registration counts and
  unknown registry ids added. Every program stops with its expected message.
- **15 capture configurations, 60 frames byte-identical to 48 hashes**; no baseline
  added or retaken. HUD, compose, both-layers and three picking probes pass.
- **Foreign registration in both orders**, fresh processes:
  `VOID_GPU_REGISTRATION=1` and `=2`. Each fills the registry to sixteen programs/eight
  layouts. The foreign shader replaces the forward copy in one frame; the two complete
  readbacks match, the lit box is independently visible, all 7,200 HUD pixels blend
  correctly and the cache reuses the foreign pipeline.
- **Allocation:** no array copy or built string in the listed frame/render/pick functions,
  now including the door's pass methods. This is emitted-code coverage, not a global
  allocator audit. First-use cache misses and changed sizes remain setup boundaries.
- **Churn:** 310 frames, tables/uniform pool/four live buffers flat; every second stream
  write refused. The never-release control exhausts sokol buffers after 42 frames.
- **Oracle:** 75 agree, 11 diverge as declared. **Android arm64:** 3,324,648 bytes.
- **Device skipped:** no GLES3 or real context-loss proof was added.

### Carried into void2d and later

- void2d's pipelines/targets still move onto the door in its own arc. Its raw bridge
  passes are not tracked yet; the pass guarantee here covers door-mediated calls.
- `gpu/state.ms` owns the twelve-member `BlendMode` ready for void2d. The old independently
  ordered five-member void2d enum is not migrated here.
- Full-swapchain-only output, opaque copy, void2d scene halves and M17's lifetime gaps
  remain as scoped. The camera follows this milestone; the spike remains.

## M21 — perspective camera and per-view frustum culling

**Design verdict: SHIP after one SEND BACK and the numeric repairs.** The owning session
performed the defect pass and verified each finding. A fresh principal-engineer reviewer
read the pinned reference sources and the implementation, without running builds or tests.
Its initial SEND BACK, first repaired SHIP and final inverse-boundary SHIP are retained here.

### Defect pass

| Finding | Repair and evidence |
|---|---|
| Foreign `near`/`far` plane names repeat the recorded Windows-header macro trap | `Frustum3D.nearPlane` / `farPlane`; caught against the handoff before compiling, not claimed as a new compiler bug |
| Culling changed the drawn set, but both presets still returned the input length | Both `prepareFrame` paths return the filtered count; the real perspective consumer requires that result to equal its pass-list count |
| Resetting the new counter before validation violated the existing refusal boundary | The counter changes only with an accepted frame; source inspection, not a separately exercised refusal test |
| A proposed control changed only the expected count | Rejected before execution. The kept control changes the actual camera to x=200 and fails with 0 visible / 8 culled instead of 4/4. A separate temporary production-filter bypass fails with 8/0 |
| Tiny finite perspective depths produced a zero inverse and invalid picking rays | `UnprojectableView` at resolve, using the same inverse and screen-ray arithmetic the consumer uses. Two scale variants were red before the repair; no inverse threshold or fallback is changed |
| Test helper used `assert` outside a test block | The installed compiler refused it; the helper now unwraps or stops, and assertions remain inside test blocks |

The copy/forwarding-only camera-block test was deleted, not re-pinned. A storage-capacity
assertion was removed from the existing alpha-order test; actual item ordering stays tested.
No renderer shader, GPU resource, main checkout, recompiler file or neighbour-owned path
was changed.

### Fresh design pass and re-reviews

**Initial SEND BACK.** `Camera3D.resolve` accepted near/far `1/100000000` and
`0.1/10000000`, where float32 rounds the depth coefficient to one. The far plane then has
zero normal, an object at twice far stays visible, and `rayFromScreen` unprojects an
infinite far endpoint. The owning session reproduced all three facts on msc `35601908`.
The ordinary `1/100` control retained a far-plane normal, rejected the outside object
and returned a finite ray.

The declaration now refuses `depth <= 1` as `UnrepresentableDepthRange`. The permanent
two-variant regression in `cameraCheck.ms` failed before the guard:
**314 passed / 1 failed**, `AssertionError: ! result . ok`; after it, **315/315**.
The design re-review returned SHIP for that repair, explicitly awaiting the final gate.

The owning defect pass then measured the separate inverse precision boundary at
`1e-12/1e-10`. Both that scale and `2e-12/2e-10` were pinned: **315 passed / 1 failed**
before the inverse/ray check. The resolved inverse is retained and reused for picking,
as Heaps' `Camera.getInverseViewProj` caches it; eager validation is the documented
deviation from its lazy cache. The center and four corner rays must have finite endpoints
and nonzero finite directions. A near-π FOV overflow test additionally keeps a supported
large-view control. The final camera lane is **317/317**, including **19 local tests**.

**Final design re-review: SHIP, no remaining source/design blocker.** It confirmed:
- the projection union and clean caller migration, with no `OrthoCamera` compatibility path;
- view-local filtering on every frame, with the original draw list and scene flags preserved;
- transformed-local support-radius bounds, covering reflection, rotation, nonuniform scale
  and shear without an inverse per item or new scratch allocation;
- the numeric refusal at declaration, the cached inverse, updated literal callers and
  allocation-list coverage, without a fake matrix or a looser math threshold;
- no customer-shaped renderer policy, new GPU-resource lifetime or hidden compiler workaround;
- independently expected lit RGB and picking in the capture consumer, not blank-image hashes.

The references and deliberate differences are in VOID3D.md "M21 as built":
Heaps `b9aa6dcbb2307b03c1f435e87bdb036060100984`; Bevy
`157e1ce6bc66fadca9f57260c18a16d743c11ed5`. The reviewer did not claim runtime evidence
it had not run; the owning session supplies it.

### Final acceptance

`sh scripts/gate3d.sh`, msc binary/support `35601908`, D3D11, 2026-09-30:
**GATE GREEN with 1 skipped stage** (`device`). The source/baseline snapshot is committed
as `44f2f3c`, tree `95d9475bfaf2a2d248287ec80f934452b57d0bb6`; the run's header was
`d688548` plus tracked diff `da63d5f8ed3a`, before the logical commits.

- **1004/1004 tests**, +14 net against M20; **35 abort programs**, +1. No new failing stage.
- **16 capture configurations / 64 matching frames / 52 hashes**. All 48 old hashes
  remain untouched; the four perspective hashes are the only additions, in their own commit.
- Perspective visible/culled counts **4/4, 4/4, 5/3, 4/4**, nearest and off-center picking,
  independently checked lit RGB and background. The distant-camera control fails correctly.
- Existing HUD, compose, both-layer, both registration-order and campfire picking checks pass.
- The allocation scan includes the inverse/ray guards and frustum functions: no array copy
  or built string in listed paths. No frame-state growth over 300 frames; 310 churn frames
  keep tables/pool/four live buffers flat; second stream writes are refused.
- **75 oracle agreements / 11 declared divergences**, 25 PENDING3D rows.
- **Android arm64 3,372,240 bytes**. No GLES3/device or real context-loss execution added.

### Scope still separate

- Perspective GLES3/device coverage; this milestone's pixel proof is D3D11.
- Bounds for external GPU-only meshes and particle/billboard streams, when that capability
  is asked for; missing CPU bounds stay drawn as Bevy's no-Aabb branch does.
- Inherited group colliders, hierarchical culling, textured meshes and the earlier
  M17–M20 lifetime/output/void2d boundary gaps.


## M22 — textured meshes

**Design verdict: SHIP WITH FOLLOW-UPS, every follow-up taken in the milestone; the re-review
of those, SHIP WITH FOLLOW-UPS, its last points taken too.** The owning session ran the defect
pass and every control. A fresh principal-engineer reviewer read the diff, the pinned Heaps and
Bevy sources and the gate logs, without running builds; its findings were checked in the session
before anything was changed.

### Defect pass

| Finding | Repair and evidence |
|---|---|
| A context texture on a material whose program samples nothing was bound to a slot the shader does not declare, silently unused and still pinned: sokol validates only the bindings a shader expects (`sokol_gfx.h:25196-25199`) | `addMaterial` refuses `MaterialError.TextureNotSampled`; `texturesFit` holds the drawn program to view and sampler 0 (`b2b43a1`); headless test (`57484d4`) |
| The pixel-art configuration could not tell its program from the core's: mapping `LitTextured` to itself in the preset passed every check | The pixel-art lit frame uses a point light, which the preset steps: the same control now fails at red 140, not a ramp level |
| The gate's style stage counted bytes, so its answer depended on the caller's locale | `332d25b`: `LC_ALL=C.UTF-8` for the count |
| A hand-made control (`if (false)` in `samplerFor`) made msc exit 127 with no output | Compiler card `2026-09-30-c-style-for-under-if-false-exits-127.md`; the control was rewritten as a live condition |

### Fresh design pass

No correctness defect found by reading; holders ≥ pins throughout, no leak or double destroy,
the frame path allocation-free. Findings on what the acceptance proves, and what was done:

| Finding | Done |
|---|---|
| M1: the rebuild called `rebuildTextures` directly; `samplerFor`'s reset and `beginFrame`'s call never ran with a texture | The rebuild configuration loses the context through `beginFrame`'s own new-context branch, sampler cache included, and requires a new view and sampler. Control: a cache that ignores the new context fails the run |
| M2: the sampler key was never observed | Headless test: six settings, six slots; the GPU lifetime check requires one new sampler per new setting |
| M3: texture lifetime only on D3D11, missing cases | Added: two materials on one texture, a material freed while the caller holds its texture. Still not headless: eager upload and no device in the suite, written down |
| M4: the pixel-art program's normal and depth output never read | Fourth configuration, outlined, orthographic: silhouette shaded by depth, crease lifted by normals. Control: a constant normal fails the crease check. Found: the pixel-art post pass does not outline a perspective scene (measured), predating M22; recorded |
| L1: `drawScreen` indexed the texture field unchecked; context textures on screen and billboard programs | `drawScreen` refuses `TextureReplaced` (`765b54c`, test `29e1e3c`); any program sampling slot 0 takes a context texture, written down |
| L2: the cube's top and bottom orientation not traced to Heaps | Written down as this port's own orientation: every face upright and unmirrored face on; Heaps' top and bottom both put the first row toward its +y |
| L3: "same Slots table"; `realloc` is Heaps' caller callback | Corrected; the CPU copy's RAM cost written down, Bevy's `RenderAssetUsages` named |
| L4: a refused remake draws nothing, silently | Kept on M16's precedent; written down |
| Style: comments restating code, a missing PENDING sentinel, unnamed reused mechanisms | Comments trimmed; sentinel on `litTexturedFs`; the sampler cache named as `PipelineCache`'s context idiom and the material's pin as M17's |
| Style: `let` where `const` would do; a fixed-size `Vec`; `Result<int32>` of the index | Kept: `let` is the arc's rule since msc refuses writes through `const`; the `Vec` and the result mirror `bindings` and `uploadMesh` |

### Re-review of the follow-ups

SHIP WITH FOLLOW-UPS, nothing blocking. It confirmed M1 to M4 and L1 to L3 closed and accepted
the reasons for what was kept. Its remaining points, all taken:

| Finding | Done |
|---|---|
| Neither preset checked its own screen materials' textures: a replaced one reached `unreachable` in the pixel-art post draw, and the forward one stopped naming a release | Both `prepareFrame`s refuse `TextureReplaced` by name before any pass; the stop messages name the texture; headless test |
| `checkOutline` counts matching texels anywhere, while the draft said where | The as-built says what it checks: shaded and lifted texels exist, the quadrant centres stay exact, and where they sit is held by the hashes |
| The pixel-art post pass under a perspective camera was only a "still missing" line | PENDING3D row `pixel-art-depth-orthographic`, sentinel at the first `depth01` write in `pixelArt3d.glsl` |
| Heaps' cube side orientation claimed in a right-handed reading; Heaps defaults to left-handed (`Camera.hx:69`) | The sentence now says only that Heaps' table is laid out for its Z-up, left-handed frame; the top/bottom claim stands |
| The final gate had to compare the outline frames, not adopt them | Done: the gate on `b9be806` passed all four outline frames against their hashes |

### Final acceptance

`sh scripts/gate3d.sh`, installed msc `35601908`, D3D11, 2026-09-30, on the committed code
(`c67b5e5`): **GATE GREEN with 1 skipped stage** (`device`).

- **1022/1022 tests**, +18 on M21; **35 abort programs**, unchanged.
- **20 configurations / 80 frames match 64 hashes**: the 52 earlier hashes untouched; the twelve
  `m22textured*` hashes added in their own commits.
- The textured stage: uv orientation, exact texels, texel times light, the preset's stepped
  point light, the outline's depth and normals, texture lifetime on the driver and a context
  rebuild through `beginFrame`, both presets. Five controls fail where they should.
- Allocation scan clean with the texture functions listed; churn flat at 6 buffers, 3 images and
  2 samplers over 310 frames; the control runs out of sokol's pools.
- **75 oracle agreements / 11 declared divergences**, **26 PENDING3D rows**.
- **Android arm64 3,479,656 bytes**. No GLES3/device run and no real context loss.

### Scope still separate

- GLES3/device and a real context loss; the rebuild is simulated on D3D11.
- glTF `TEXCOORD_0` and images, image-file decoding, mipmaps, sRGB, `killAlpha`.
- The pixel-art preset under a perspective camera.
- Deleting the spike, the human's call.

## M23 — textured content from files

**Design verdict: SEND BACK on one defect, taken; the re-review, SHIP WITH FOLLOW-UPS, its last points taken.** The
owning session ran the defect pass, verified each of its candidates against the code and the
pinned references, and ran every control. A fresh principal-engineer reviewer read the diff, the
Heaps source at `b9aa6dcb` and Bevy at `157e1ce6`, the gate logs and the captured frames, and
measured its blocking finding with a modified fixture; its findings were checked in the session
before anything was changed.

### Defect pass

`/code-review high` on `da156bc..bde391d`: ten candidates, each read against the code.

| Finding | Done |
|---|---|
| Churn named a failed release and bad model data `NodeRefused` | `ReleaseRefused` and `ModelRefused`, the match exhaustive (`cd02e74`) |
| A comment named a milestone | Removed (`c89e638`) |
| The gate's prose counted "twenty-two" capture entries, wrong once M23 added three | No count (`32f5613`) |
| `gltf_parked` built the entry twice | Moot: the park came out with the sync (`b3b3202`) |
| `facingNormal` under a mirrored node | Not a loader case: a non-positive scale product and `matrix` are refused (`gltf.ms:463-465`, `:409`); scene-API mirroring behaves as Heaps' `FlipBackFaceNormal`, written down |
| The generator does not pad the BIN chunk | It does, after the PNG (`makeTexturedGlb.py:127-128`) |
| A single-sided material takes the setup's culling verbatim | The setup is Heaps' `MaterialSetup` pass, by the row |
| `releaseGltfAssets` stops at the first stale handle | Kept: fail loud; the rollback's handles are the call's own |
| Two textures on one image decode twice | Bevy's `load_image` does the same; written down |
| No decode memory budget beyond 16384 per side | Neither reference has one (Bevy's loader calls `no_limits()`, `bevy_image/src/image.rs:1632`); written down |
| An OPAQUE texel's alpha reaches the target | Recorded, with the claim that nothing reads it: **wrong**, see the design pass |

Found by the adopt run, not the pass: `GATE_ADOPT=1` reported the M23 hashes recorded and wrote
none, since `record_hash` rebuilds the manifest from `baseline_names`, which did not list them.
Listed, and an unlisted key now fails its capture (`e6563c4`); control: an unlisted key on a copy
of the manifest fails and leaves it unchanged.

### Fresh design pass

SEND BACK on one finding. Frame loop allocation-free (no function added to the frame path, the
scan unchanged and passing), no new kind of GPU resource, no Hibernal leak, the asBytes card
parked and unparked correctly, the readback run for real (the reviewer re-ran the pixel-art
entry fresh against the adopted hashes).

| Finding | Done |
|---|---|
| **Blocking:** the pixel-art post pass scales both outline terms by the colour target's alpha (`pixelArt3d.glsl:242-243`), the outline is on by default, and an OPAQUE texel's alpha reached it. Measured by the reviewer: a fixture texel at alpha 0 changes 376, 188 and 334 pixels of frames 1, 6 and 11 in an outlined orthographic configuration, the cube's silhouette unoutlined. The headless test pinned the violation | Texels load with alpha 255 (`d8d5ed0`), exact while only OPAQUE is accepted; the tests assert it; control: the texel alpha kept fails both tests. The as-built says why, and that the alpha moves to the program, as Bevy's `alpha_discard`, when MASK or BLEND arrive |
| Factor and `COLOR_0` are linear in glTF and drawn as stored | Written into Still missing with the fixture's (128, 64, 128) against about (188, 137, 188), and Bevy's `linear_rgba` |
| Materials are shared per glTF material, while `makeMaterial` deep-copies per object and the doc said "as `makeMaterial` does" | Kept and argued: Bevy's loader shares one handle per material label and void3d's nodes share materials by id (M17); a per-node look is a per-node material |
| The decode cap is D3D11's; GLES3 guarantees 2048 and `addTexture` never checks the device limit | Still missing, with sokol's limit read and its size validation |
| An absent `magFilter` takes the min filter's base | Written down beside Bevy's default |
| The setup's own double-sided value was overwritten silently | `BadSetup` (`0d290f9`); control: the check removed fails the setup test |
| The decoder's output pointer was `const` and cast | `uint32_t *` (`5719f57`) |
| Four typed-local error helpers, needed by nothing on msc `5791eadd` | Removed, `accessorError` included (`be6f2ff`); whether msc `35601908` needed them cannot be checked, that binary is gone |
| An if-chain over the two mime literals | A `match` (`be6f2ff`) |
| Provenance comments belong in the doc | Kept: they name the external authority the port follows, the idiom of the void3d sources |

### Re-review of the send-back

SHIP WITH FOLLOW-UPS, nothing blocking. It rebuilt the new head and reran its measurement: with
the fixture's texel at alpha 0 and at 255, frames 1, 6, 11 and 16 differ by 0 pixels, and the
outline is still drawn (94 outlined-red pixels in frame 1). It accepted holding the property
headless, since no texel below 255 reaches the GPU from glTF, and read Bevy's material labels
itself. Its remaining points:

| Finding | Done |
|---|---|
| Two sampler refusals over 100 columns after the helpers went, which the style stage would fail | Wrapped (`0bfcae3`) |
| The context paragraph's last sentences had landed inside the sharing sub-bullet | Moved back (`b9860c0`) |
| `let pixels = decoded.value.pixels` copies the image once more at load (CODE-STYLE §5) | The texels are written through a `Span` view of the decoded words (`0bfcae3`); the alpha tests still pass, so the view writes through |
| Carried: the colour-space decision, `addTexture` against the device limit, alpha moving to the program with MASK and BLEND | In "Still missing after M23" |

### Final acceptance

`sh scripts/gate3d.sh`, installed msc `5791eadd`, D3D11, 2026-10-01, on the reviewed code
(`b9860c0`, clean tree) before the rebase over void2d's D1: **GATE GREEN with 1 skipped stage**
(`device`). Commits are named as they are on main.

- **1037/1037 tests**, +15 on M22; **35 abort programs**, unchanged.
- **24 configurations / 96 frames match 72 hashes**: the 64 earlier hashes untouched; the eight
  `m23gltf*` hashes adopted in their own commit (`b77bff2`). The pixel-art frames 1, 11 and 16
  equal the forward ones; the rebuild configuration matches the forward hashes.
- The `gltf` stage: the fixture read from disk, texels, factor colour, both sides lit, culling,
  rollback, release and a rebuild, both presets. Five consumer controls and the headless ones
  fail where they should.
- `gltf-cpu` links no sokol; allocation scan clean; churn flat at 10 buffers, 4 images and 2
  samplers over 310 frames with a glTF model loaded and released every frame; the control runs
  out of sokol's pools after 14 frames.
- **75 oracle agreements / 11 declared divergences**, **26 PENDING3D rows**.
- **Android arm64 3,469,312 bytes**. No GLES3/device run and no real context loss.

### Scope still separate

- GLES3/device, a real context loss, and the device's texture size limit.
- Colour spaces for texels, factors and `COLOR_0`; alpha as a material's (MASK, BLEND).
- Images by URI, `KHR_texture_transform`, normal, occlusion and emissive maps, mipmaps.
- A real Blender export (`gltf-real-export-not-exercised`).

## M24 — store identity

**Design verdict: SEND BACK on one defect, taken; the re-review, SHIP WITH FOLLOW-UPS, its points taken.** The owning
session ran the defect pass, read every candidate against the code, and measured each control.
A fresh principal-engineer reviewer read the diff, Heaps at `b9aa6dcb`, Bevy at `157e1ce6` and
GPUI at `b961b49`, the logs and the C the gate emitted. It built and ran nothing, since the
workstation's native capacity was rationed between sessions that day. Its findings were checked
in the session before anything changed.

### Defect pass

`/code-review high` on `0048b18..801a0ab`: ten candidates, each read against the code.

| Finding | Done |
|---|---|
| `pickNearest` reads a caller's tables with no store check | Carried to M25's row (`6bf51d5`): the scene holds its context there. The headless pick tests build their tables without a GPU, so taking a context now would break them for one milestone |
| `syncMeshFrame` and `addMaterial` map errors through a `_` arm | Every case named, the impossible ones stopping by name (`ac3b615`); made exhaustive `match`es again in `13f478a` after the design pass |
| Stale-or-foreign is chosen at about ten call sites | Kept: each layer maps to its own error enum, and the one predicate, `issued*`, is defined once in `draw.ms` |
| `admitted` and `holds` both compare the store | One compare on success; `admitted` classifies only a refusal (`ac3b615`) |
| `forMeshes` and `addGltfNodes` compare twice | `hasMesh` first, the classification only on failure (`ac3b615`) |
| The `addMeshNode` comment says two `ref`-receiver functions collide | Measured with a value interface parameter (`out/tmp/overload/value`): the call is now refused at compile time, not silently wrong; comment and PENDING3D row rewritten (`6bf51d5`) |
| `run_stores` sat under the both-layers comment, its line continuation lost | Moved, continuation restored (`a2d8cb6`) |
| Id literals leave `store` at 0 | `NO_MESH` and `NO_MATERIAL` exported, every literal writes its store (`ac3b615`, `13f478a`) |
| The serial counters can overflow `int32` | They stop by name at the last value (`ac3b615`) |

Found by the gate, not the pass: the churn example's exhaustive `match` over `GltfSceneError`
missed the new `ForeignMeshBinding` and stopped the churn build (`6acafbd`).

### Fresh design pass

SEND BACK on one finding. The mechanism follows the references (the store is one object, as
Heaps' object and the `Arc` of Bevy and GPUI are); the serial is honestly a NEW MECHANISM; the
frame loop allocates nothing; the rebuild captures stay byte-identical; no compiler workaround.

| Finding | Done |
|---|---|
| **Blocking:** `drawItem`, which is public, applied its pass-wide blocks without checking their pool, so another pool's block drew silently, and `applyBlock` would read past this pool's values for a block of a larger pool; `drawScreen` skipped `keepsItsUniforms` | `drawItem` stops by name on an item, a pass-wide block or a material block its context does not hold, before any GPU call; `drawScreen` returns `UniformsReplaced` (`0112560`). Abort `drawItemForeignBlock`; control: without the check it runs past and stops later, unnamed. The first gate on it failed allocation (a string built in `drawItem`) and style; the messages moved into stop helpers off the frame path (`90b4cbd`) |
| The draft's account of the red run did not match its log | Rewritten from `red-431dc90.log`, and the red program's first form named |
| Texture and block had no control | Measured: each forced open fails exactly its own checks, four lines each |
| The allocation stage did not list the new callees | `issuedMesh`, `issuedMaterial`, `uniformPool:admitted` listed (`b86bac7`) |
| The review fix turned `match` into `if` chains | Exhaustive `match` with a stop helper as the arm value (`13f478a`) |
| A comment moved off `syncMeshFrame` | Back above it (`13f478a`) |
| Still missing left out `RenderTarget`, `Sampler`, `collect`, `filterFrustum`; "Data types" still said index and generation | Both written; "Data types" names the store (docs commit) |
| `tallyMeshPin` and `tallyMaterialPin` answered "covered" for a foreign id | They stop by name (`13f478a`) |
| The pick deferral's reason was weak | The as-built says how it is M25's to settle, not that it cannot be done |
| Foreign as a `Result`, misuse as a stop: the rule was not written down | Written in the as-built, with Bevy's `Assets::get` and M19 |
| `serial` is writable | PENDING3D `store-serial-writable`, a Parked-at site on card `2026-09-27-readonly-interface-field-unresolved-type.md` (`13f478a`) |
| Messages that misname a foreign case | `drawToScreen` names a context that did not make the preset; the camera and light writes cannot meet a foreign block, since the screen mesh is checked first |
| The cost line counted only `DrawItem`; "neither reference has one" undersold Heaps' and Bevy's handles | Rewritten: `Material`, `MeshInstance`, `GltfMeshBinding` +8 bytes, a context two heap objects; both references route a release through the handle's store |

### Re-review

SHIP WITH FOLLOW-UPS, nothing blocking. B1 closed: `drawItem` stops before any GPU call on an
item, a pass-wide block or a material block its context does not hold, `holds` comparing the
store and the generation, so a released block of the same pool stops too; the messages are off
the frame path; the abort is the right case and its control shows the named stop comes from the
check. Bench CPU per frame 0.0966 ms against 0.0968 ms before. Its remaining points:

| Finding | Done |
|---|---|
| New from the fix: neither preset's `prepareFrame` checked its own screen materials' blocks, so a replaced one was refused mid-frame, after the scene pass, and the post material's ended in a bare `unreachable` | Checked beside their textures, `UniformsReplaced` before any pass; a suite test for both presets |
| The two tally stops had no abort programs (M19: one per stopping entry) | `tallyMeshPinThroughForeignContext`, `tallyMaterialPinThroughForeignContext` |
| "Data types" still said an id is an index and a generation | It names the store |
| Card `2026-09-27`'s `State:` said nothing waits on it; `uniformPool.ms`'s serial had no sentinel | The state names void3d's sites; a sentinel in `uniformPool.ms` |
| The as-built pointed "above" at a churn failure it did not describe; `drawItem` read the material slot twice | Described; one read |

### The coordinating session's source review

After the re-review, the session coordinating the unification read `drawItem` at `90b4cbd` and
found the same class as B1 one field over. Each finding was read against the code here first.

| Finding | Done |
|---|---|
| `drawItem` and `bindItem` index the texture table at the material's `texture` without `keepsItsTexture`, so a caller who rewrites it to another store's id, a stale id or an index past the table reaches that index | `drawItem` requires `keepsItsTexture` before any index (`4ca3705`); three abort programs, each with a control (`66eb1d3`) |
| `holds` on the material's block admits another live block of the same pool the material does not own | `keepsItsUniforms` in its place; two abort programs, live and released, each with a control (`66eb1d3`) |
| The presets' new screen-block checks had no red control | Headless, without each of the three a frame passes `prepareFrame` and makes its first GPU object (`sg_make_buffer` from `makeScreenTriangle`), and can run no further. On D3D11 in the `stores` consumer (`3e7101f`): each replaced block refused before any pass, no new GPU object, a surviving context's frame its own colour; without each check the frame runs into its passes and fails late, the copy and the blit at `drawToScreen`'s stop, the post on a bare stop (exit 132) |

### Final acceptance

`sh scripts/gate3d.sh`, installed msc `5791eadd`, D3D11, 2026-10-01, on the reviewed code
(`3e7101f`, "test(void3d): replaced screen blocks refused before a pass on D3D11", clean tree)
before the rebase over void2d's GPU-door closure (`122e515`): **GATE GREEN with 1 skipped stage**
(`device`). Commits are named as rebased.
The workstation's native capacity was rationed between sessions; each native run here had its own
go from the coordinating session.

- **1123/1123 tests**, +9 on main's 1114 (`src/test/storeCheck.ms`); **46 abort programs**, +11.
- **24 configurations / 96 frames match 72 hashes**, none adopted: nothing in M24 moves a pixel.
- The new `stores` stage: two contexts on real D3D11 objects refuse each other's meshes,
  materials, textures and blocks by name, an alias releases once, a reused slot is stale, and both
  presets refuse a replaced screen block before any pass while another context draws. Its
  controls (one kind forced open at a time) fail exactly that kind's checks; the red run on
  `0048b18` failed 23.
- Allocation scan clean, with the store checks on its lists; style clean; churn flat at 10
  buffers, 4 images and 2 samplers over 310 frames; bench flat.
- **75 oracle agreements / 11 declared divergences**, **27 PENDING3D rows** (+1,
  `store-serial-writable`).
- **Android arm64 3,566,184 bytes**. No GLES3/device run.

**Rebased before landing.** `main` had moved to `122e515`, void2d's GPU-door closure. The rebase
had one conflict, `src/void3d/pixelArtRenderer.ms`, where `bindScreenTextures` now takes M24's
`context` by value and reads main's `renderer.sampler.asHandle()`; nothing else needed adapting.
Every M24 commit took a new hash; the hashes above are the rebased ones (`2eca4b4`). On the rebased
code (`2eca4b4`, clean tree), installed msc `5791eadd`, D3D11, 2026-10-01:

- `sh scripts/gate3d.sh`: **GATE GREEN with 1 skipped stage** (`device`). **1127/1127 tests**,
  main's 1118 + 9; **67 abort programs**, main's 56 + 11; 72 hashes byte-identical; the `stores`
  consumer prints the same line as before the rebase; oracle 75 / 11, 27 PENDING3D rows, churn
  flat at 10 buffers, 4 images and 2 samplers. **Android arm64 3,596,448 bytes**, +30,264 on the
  pre-rebase tip, not measured on main alone.
- `sh scripts/gate.sh --web`: **GATE GREEN with 8 loud skips**. 1127 tests plus 299 isolated,
  D3D11 78/78, WebGL2 56 pass / 18 pending / the four `conformance:webgl2-pixel-centre` reds,
  allocation 107 frame functions / 245 callees, 16 PENDING rows; web builds 2,344,744 /
  2,116,929 B, the sizes void2d's closure recorded on `7cf741d`.
- Logs: `out/tmp/m24/rebase/`.

### Scope still separate

- M25: owners as references holding their context, their `close`, `pickNearest` on the scene's
  context, node ids naming their scene. It waits on void2d's `PipelineCache` as a reference owner.
- void2d's door: `RenderTarget` and `Sampler` generations and checked borrows.
- The post-M23 list: colour spaces, alpha as a material's, the device's largest texture, device runs.

## M25 — owners and their teardown

**Design verdict: SHIP WITH FOLLOW-UPS, every follow-up taken inside the milestone.** The owning
session ran the defect pass through one read-only reviewer and read every finding against the
code before changing anything. A fresh principal-engineer reviewer then read the diff
`b4f7fc5..01c9687`, the row, the arc card's measurements, the logs, Heaps at `b9aa6dcb`, GPUI at
`b961b49` and Bevy at `157e1ce6` (fetched), and built and ran nothing: the workstation's native
capacity was rationed between sessions. The session coordinating the unification ruled the two
points put to it.

### Defect pass

`/code-review high` on `b4f7fc5..c070540`: eight findings, none high, each re-read in the session.
Fixes `cab7b02..01c9687`.

| Finding | Done |
|---|---|
| A preset's first frame forgot its palette table, so a table the host uploaded or another preset shared before it leaked its image and view | The forget dropped; `upload` forgets a stale image itself (`cab7b02`). The `views` consumer uploads the table first: with the old line back it grows 5 images and 5 views over five cycles, and none without |
| A call with a closed scene answered `StaleTarget` or stopped naming `syncWorld`; a pixel-art preset whose core an alias closed could still ask for a frame | `Scene3D.requireOpen` at each entry, `needsFrame` false on a closed core (`43c6413`); abort `syncMeshFrameWithClosedScene` (`65dfe64`), whose control without the check returns |
| The row stops a glTF model paired with another context's scene; it answers `ForeignMeshBinding` | A divergence, ruled in the design pass below and written in the as-built |
| A constructor given a closed context did not stop by name | `DrawContext.requireOpen` in `Scene3D.create`, `forMeshes`, `addGltfAssets`, `Renderer.createDrawing` and both presets (`43c6413`); abort `sceneOnClosedContext`, whose control without the check runs on |
| The campfire's placeholder mesh frames left `context` and `closed` out of their literal | Both written (`0eee5c7`); the hole is a compiler card (design pass finding 7) |
| closeCheck's two stale-close tests might pass on the wrong branch | Not a defect: each forced destroy alone stops the test binary on sokol's `_sg.valid` (image `sokol_gfx.h:27197`, buffer `:27117`); only those tests hold a handle headless |
| The `views` consumer never closed its module-level placeholders, and its pass line counted six cycles where five are compared | `closeView()` in `init`; the lines count the compared cycles (`d0618e6`) |
| `drawScreen`'s comment named a `context` argument that is gone | Rewritten (`83f1557`) |

The fix phase also moved the owners' `context` and the scene's `serial` under PENDING3D
`store-serial-writable`, with a Parked-at line on card
`2026-09-27-readonly-interface-field-unresolved-type.md` (`01c9687`).

### Fresh design pass

SHIP WITH FOLLOW-UPS, nothing blocking. The port follows its references: the owner keeps its
context as a Heaps texture keeps its `mem` (`h3d/mat/Texture.hx:129`) and a `Scene2D` its context;
a node unpins its mesh on removal as `Mesh.onRemove` decrefs its primitive (`h3d/scene/Mesh.hx:133-137`);
releases are gated on the generation as the door's `released()` is; picking reads the scene's
context as Bevy's reads the world's one store. Nothing game-shaped entered `src/void3d`; every
check on the frame path is a field load and a branch. Its findings, each read against the code
here first:

| Finding | Done |
|---|---|
| Abort coverage below M19's one program per stopping entry | Ruling A below: every closed and pass-open stop has a case |
| The allocation stage did not list `requirePaired` or `requireOpen`, and `requirePaired` held its message | The message moved to `stopOnUnpaired`; `scene:requireOpen`, `scene:requireOwn`, `draw:requireOpen` and `animation:requirePaired` listed |
| A scene whose context was closed under it answered `StaleMesh` or `BadMeshBinding` | `addMeshNode`, `addGltfNodes` and `setMeshOf` stop naming the closed context; three cases |
| `NotPinned` meant two things: a stop in `closeMeshFrames` and `closeScene`, a `Result` in `remove`, `setMeshOf` and `syncMeshFrame` | Ruled with the coordinating session: M19's reason for the `Result` was a pin taken through a copy of a scene (VOID3D.md "M19 as built"), and no copy exists now. A missing pin stops all of them; `SceneError.NotPinned` and `AnimationError.NotPinned` gone; `remove` and `removeChildren` answer the count; the two tests became five cases |
| Divergences not written down: a second close stops (Heaps `Texture.dispose` and GPUI `destroy` are idempotent), `closeContext` refuses where Heaps' `MemoryManager.dispose` forces, `closeScene` against `Scene.dispose`, the shared palette's alias close, the glTF `Result`; "Data types" still said a node is an index and a generation; the cost of the scene serial | Each in "M25 as built", argued, citations checked against the sources; "Data types" names the serial and the owners as references |
| Evidence: the capture count overstated (15 configurations and 5 derived checks, not 20); nothing but views, aborts and captures re-ran after the fixes; the bench result was missing | The final gate below is the acceptance, on one recorded tree |
| An interface literal that omits a reference field compiles | Compiler card `2026-10-03-interface-literal-omitted-reference-field.md` |
| The palette's stale `upload` path and `closeContext`'s stale-sampler branch are read, not run: `contextGeneration()` is 1 on D3D11 | Written under "Still missing after M25"; a device run is what runs them |
| `closeGltfAssets` kept its id lists after close | Emptied, as `closeMeshFrames` empties its frames |
| An animation bound in one scene and synced into another of the same context answered `StaleTarget` where a setter stops | `requireOwn` in `bindTracks`, `syncPose`, `bindMeshFrames` and `syncMeshFrame`: "of another scene"; four cases |
| Card `2026-10-02-top-level-unreachable-guard-hides-interface-global.md` listed no site; three aborts named their animation for a game | The site listed; the name is `frames` |

**Ruling A, abort coverage.** An abort proves an entry reaches its check before it acts and names
itself; one per helper proves only the helper's message. Without its check, `bindTracks` and
`syncPose` answered a `Result` again, and the constructors stopped under another call's name. The
coordinating session kept M19's rule for every closed and pass-open stop, about eighty, and
carried it as Rust carries `#[should_panic]`: one program per owner module, built once, each case
run on its own against its own line (`tests/aborts3d/cases/`, "M25 as built"). The one-case
programs stay.

**Ruling B, the glTF pairing.** `addGltfNodes` pairs no owner with the scene; it takes ids per
call, so M24's rule makes another context's model a `Result`, and the row's stop holds for mesh
frames. Agreed by the coordinating session; the as-built narrows the row for glTF and names the
alternative not taken.

### Final acceptance

On the reviewed code, `1509a1d` ("test(void3d): the abort cases fit 100 columns", clean tree
`909d87b54d30`), installed msc `5791eadd`, D3D11, the shared Windows workstation, 2026-10-03;
one `gate3d.sh` then one `gate.sh --web`, serial, the BUILD read before each.

- `sh scripts/gate3d.sh`: **GATE GREEN with 1 skipped stage** (`device`), 12:22-12:31.
  **1138/1138 tests**: 1140 on the built code, less the two `NotPinned` tests that became abort
  cases. **84 abort programs** (main's 73, 12 new, 3 gone with their call shape, 2 from the defect
  pass) and **98 abort cases** in 10 programs under the new per-case form. 24 configurations /
  96 frames match **72 hashes**, none adopted: nothing in M25 moves a pixel. The `views` stage
  holds every live count at the first cycle's after each of the other five; `stores`, `gltf`,
  `textured`, `perspective`, `compose`, `pick`, both layers green; churn flat at 10 buffers,
  4 images and 2 samplers over 310 frames; allocation clean with `requireOpen`, `requireOwn` and
  `requirePaired` on its lists; style clean; **75 oracle agreements / 11 declared divergences**;
  **27 PENDING3D rows** (`store-serial-writable` widened, none added). Bench 0.0999 ms of CPU a
  frame, reported only (M24's gate 0.0966). **Android arm64 3,630,416 bytes**. No GLES3 or
  device run.
- `sh scripts/gate.sh --web`: **GATE GREEN with 8 loud skips**, 12:32-12:40. 1138 tests plus
  299 isolated, D3D11 78/78, WebGL2 56 pass / 18 pending / the four
  `conformance:webgl2-pixel-centre` reds (`prim/strokeRect`, `prim/polygonBezier`,
  `prim/patterns`, `xform/scale`); allocation 107 frame functions / 245 callees; 16 PENDING rows;
  web builds 2,345,812 / 2,118,001 B.
- The per-case protocol's control, run once on the stage's own loop over `paletteCases`: with
  `fill`'s closed check removed, and with a case the program does not know added to its header,
  both cases fail the stage and the others pass (`out/tmp/m25/fix2/controlProtocol.log`).
- Logs: `out/tmp/m25/gate/` (the gate logs and the tree each ran on), `out/tmp/m25/fix1/`,
  `out/tmp/m25/fix2/`.

### Scope still separate

- The device's shutdown; void2d's scene teardown (its arc's B1).
- The palette's stale `upload` and `closeContext`'s stale samplers, which run only on a device
  where the GPU generation moves (V6).
- The post-M23 list: colour spaces, alpha as a material's, the device's largest texture, device
  runs.
