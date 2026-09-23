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
