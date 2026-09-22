# Phase reviews

One section per phase of the [VOID2D.md](VOID2D.md) roadmap. Every phase gets two passes
before the next one starts: a **defect pass** (`/code-review high` on the phase diff) and a
**design pass** by a fresh reviewer who did not write the code, judged against the phase's
exit criteria, the guardrails and the decision rule. Verdicts are **SHIP**,
**SHIP WITH FOLLOW-UPS** or **SEND BACK**.

Send-backs stay on this page. A clean story here would mean the reviews were not doing
anything.

---

# P0 — The gate

**Diff:** `c487474..HEAD`, 16 commits.
**Defect pass: 10 findings, all confirmed, all fixed** (`a06edd9`).
**Design pass: SEND BACK** on four blockers, then fixed (`8dd1b7f`) and re-reviewed.
**Final verdict: see "Design pass — re-review" below.**

## Defect pass — `/code-review high`

Ten findings, every one real. Fixed in a commit of its own, `a06edd9`.

| # | Finding | What I did |
|---|---|---|
| 1 | `golden.sh` took the pipeline's status from `grep`, so a scene printing `FAIL` or `SKIP` counted as a successful capture and `--update` would overwrite the goldens after a failed run while printing "goldens updated" | Take the runner's own status into a log, match `^CAPTURED` alone, and count everything else — including an empty verdict — as a failure |
| 2 | Neither `golden.sh` nor `gate.sh` created `out/` before redirecting into it; `out/` is gitignored, so neither worked on a clean checkout — contradicting the exit criterion that says "from a clean clone" | `mkdir -p out out/golden` at the top of both. Verified by deleting `out/` entirely and re-running the gate |
| 3 | `staticBuffersFailed` was decremented on destroy, so a node re-uploading a mesh every frame could drive it unboundedly positive and `nodesDrawn` negative | Renamed to `staticBuffersRefused` and made it monotonic: it counts allocations sokol turned down and is never decremented. `alive` stays symmetric |
| 4 | `nodesDrawn` subtracted a refused-label-buffer count from a *card* count; it landed on 126 only because there is exactly one Label per card | Replaced with `retainedNodes` (nodes that ask for a GPU buffer) beside `buffersAlive`, so the pair reads as "10 000 labels asked, 126 drew". `nodes` now counts all 20 000 |
| 5 | `web-liveness.sh` never deleted the previous screenshot, so a Chrome crash measured the last run's PNG and reported PASS | `rm -f` before each run |
| 6 | `compare.ms`'s `parseInt32` returned a `0` fallback for anything unparseable — including the `-` placeholder its own table documents — turning a malformed budget into "over its budget (0 px, delta 0)" | Returns `NOT_A_NUMBER`; an unreadable budget row is reported by name and fails the run |
| 7 | Unchecked `malloc` in `capture.c`'s `slotResize`, then dereferenced; the slot was also sized before the allocation succeeded | Returns NULL and leaves the slot empty; both backends check it and release their D3D11 handles first |
| 8 | `d3d11_conformance="$(grep …)"` is a bare assignment under `set -e`: a missing line killed the gate mid-run with no summary and no message | `|| echo 'no conformance line in the log'` |
| 9 | `web-liveness.sh` installed its `EXIT` trap *after* a 2 s sleep, so an interrupt in that window orphaned the HTTP server on the port | Trap moved to immediately after the background launch |
| 10 | Four other entry points (`mainSokol.ms`, `mainCampfire.ms`, `iosEntryAnim.ms`, `iosEmbedEntry.ms`) still carry the `main()` defect | Deliberate scope call: they are the void3d arc's files and the void3d worktree is live. Recorded in `tests/PENDING.md entry-main-not-called` and in VOID2D.md "Known defects" |

## Design pass — SEND BACK

> "The artifacts are sound; the *claims about them* are not yet, and claims are this phase's
> only product."

That is the right framing and I accept the verdict. Four blockers:

**B1 — `golden.sh` did not work on a checkout that had never run it.** Same root as defect-pass
finding 2, found independently and demonstrated: deleting `out/golden` produced
`golden d3d11: 0 pass, 0 pending, 37 fail of 37` and *misattributed the cause to the
renderer*. Fixed; verified by deleting `out/` entirely.

**B2 — `golden.sh` could not count a capture failure.** Same root as finding 1. Fixed.

**B3 — a published baseline number was wrong.** `nodes 10 000 / nodesDrawn 126`. Same root as
finding 4. Fixed, and `baseline.json` and the VOID2D.md table regenerated.

**B4 — `tests/PENDING.md` was not seeded with every "Known defects" line, and four documents
said it was.** This one was new and it was the sharpest finding of the night. The ~126-node
cap, fractional-DPI truncation, REPEAT samplers and the rotated-Mask AABB had no PENDING
row; they were covered by `regress/` goldens instead — defensible, but not what the
documents claimed, and it meant rexa's graduation rule did not cover 4 of 13 defects.

What I did, rather than mechanically adding rows: stated the contract exactly and made it
checkable. `tests/PENDING.md` now opens with an **index that maps every "Known defects" line
to the row or the `regress/` golden that covers it**, and says why a golden is the stronger
record where one exists (it says what the defect *looks like*, and the fix cannot land
without a `--update` commit that explains itself). A defect in neither column is a hole, and
the index is what keeps that visible. The four claim sites in VOID2D.md, TESTING.md and
PENDING.md's own header now say that, instead of "every line becomes a listed failing case".

## Design pass — follow-ups, and what I did about each

The reviewer assigned fourteen. I took nine in this phase rather than carrying them, because
every one of them is a claim this phase is supposed to be making honestly.

| # | Follow-up | Done here? |
|---|---|---|
| F1 | **The `step2d`/`present2d` split killed WASD panning**: `present2d` overwrote the `cam.x/y` that `step2d` had just moved, and no golden could see it because goldens never press a key | **Fixed.** The pan accumulates in its own `panX`/`panY` and the auto-fit adds it, so panning now works rather than being restored to the one-frame flicker it was before |
| F4 | The atlasFull numbers were not reproducible by any committed command | **Stated honestly.** The numbers now carry their provenance — builder, size, run count, date — and say plainly that re-deriving them needs the row wired back, which is P1's job when it fixes the defect |
| F5 | The harness had zero tests of its own, and `parseFloat64` silently dropped `-` and `e` | **Fixed.** Parsers extracted to `tests/harness/parse.ms` with six `test` blocks, reached from `src/test/index.ms`. T0 went 425 → 431. Both consumers now share one copy |
| F6 | The PENDING graduation rule had never executed | **Exercised and documented.** Both directions verified by hand: a budgeted scene that comes back byte-identical fails with "delete the entry"; a budget of `9 874` / `-` fails as unreadable. Written into PENDING.md as evidence, with the exact messages. It also surfaced a hazard worth naming: the parser knows nothing about markdown, so a pipe-delimited *example* anywhere on that page is read as a real row — which is why the examples there are block quotes |
| F7 | The table/builder cross-check compared lengths, not names | **Fixed.** Builders are `{ name, build }` and the runner compares name by name. Verified it fails: renaming one row gives `FAIL row 3 is 'prim/strokeRect' in table.ms and 'prim/oops' in scenes.ms` |
| F8 | Gate step 3 built the demo but never ran it — the defect P0 found would not be caught by the gate P0 shipped | **Fixed.** The gate runs `out/demo2d.exe` for five seconds; a windowed app never exits on its own, so the timeout *is* the pass and an immediate exit is a FAIL |
| F10 | `du` blocks instead of bytes, and contradictory wasm numbers | **Fixed.** 826 687 B total / 599 711 B demo / 226 976 B UI. The correction changes the conclusion: the ~600 KB estimate **held** for the UI scenes it was about. wasm stated per backend in bytes, broken and fixed |
| F11 | `present.ms` published to two decimals with no spread | **Fixed.** Median and range, with the reason |
| F12 | `web-liveness.sh`'s SKIPs never reached the gate's counter | **Fixed.** Counted through a log |
| F2 | Fold DPI into `Scene` state instead of a `presentAt` argument | **Carried to P1**, which already makes `begin2d` take a float logical size — same commit, same goldens |
| F3 | Commit a per-scene counter snapshot beside each golden | **Carried to P1.** The runner already computes the draw count and discards it; this is the spine of T1 |
| F9 | Two stale `Parked at:` lines in `~/metascript/.inbox/compiler/` | **Partly.** The `main()` question is resolved in the docs — CODE-STYLE §9 says nothing calls `main()`, on any platform, so it is not a compiler defect and VOID2D.md no longer frames it as one. Updating the two cards is **carried to P1** |
| F13 | ≤100 columns, and the `-1.0` sentinel in `check.ms` | **Sentinel fixed** (a `[reported, value]` tuple). **Columns carried to P1** |
| F14 | Record RGB-only capture as a stated limit of T2 | **Carried to P2**, which is where blend space first matters |

## What the reviewer praised, kept verbatim so it is not lost

- The guardrail-9 reporting: the gate never prints a conformance result it did not produce —
  the D3D11 line is `grep`'d out of the comparator's own output — and every other backend is
  a named SKIP.
- The hand-computed harness scene: "best piece of work in the diff". It genuinely covers the
  hand-written BGRA→RGBA swizzle; re-encoding the capture with R and B swapped fails it with
  32 768 of 32 768 pixels wrong.
- `harness/mustFail` has single-pixel sensitivity, not a token difference.
- Comment density: "every non-obvious choice carries its reason and a citation".

## One thing recorded rather than fixed

The goldens are taken at `sample_count` 1 while `mainSokol2d.ms` ships the demo at 4, so
"the demo is never broken" is checked in a configuration nobody ships. This is the right
trade — a golden set five backends must match cannot carry MSAA, and MSAA is on for the
sokol_app entry only — it is written down in three places, and P2 removes the dependency by
giving box-shaped UI its own analytic antialiasing.

## Design pass — re-review: **SHIP WITH FOLLOW-UPS**

The same reviewer, re-reading after `8dd1b7f`. All four blockers closed, each demonstrated
by running rather than by reading, and explicitly **not** a second send-back on the same
cause:

> "B1 and B2 were *mechanical* defects in two shell scripts, B3 was arithmetic, B4 was a
> claim without a record — all four now hold under a command anyone can re-run. The phase
> design is sound; what was wrong was the code and the prose, and both were fixed."

What the reviewer verified independently, and which I had not:

- **B1** by deleting `out/` twice over, and by running `scripts/golden.sh` *standalone* —
  the case `gate.sh`'s own `mkdir` would have masked. Green from nothing, 39 s.
- **B2** by driving `capture()` with stub runners: all-`SKIP`, one `FAIL`, no output, and
  `--update` after a failed capture. Every one exits 1; `--update` prints
  "goldens NOT updated: capture failed".
- **B4** by checking all 14 "Known defects" bullets against the index, and every cited
  golden against the tree: "a perfect bijection over 37 names — zero in the table without a
  PNG, zero on disk without a row".
- **F6** by re-running the graduation probe in both directions from the written record, in
  ninety seconds. That was the point of writing it down.

No fix introduced a new defect. The monotonic counter, the pan fix, the name pairing, the
shared parser module and the `malloc` check were each checked and cleared.

### Four follow-ups assigned to P0, and closed in this commit

| id | Finding | What I did |
|---|---|---|
| **G1** | `docs/REVIEWS.md` was untracked — "for a phase whose whole product is 'a claim someone else can check', the review log being invisible on a clean clone is the exact failure mode P0 exists to end" | This file, committed. Fair hit, and the sharpest one in the re-review |
| **G2** | `VOID2D.md` and `TESTING.md` still said 425 tests; the gate prints 431 | Both corrected |
| **G3** | `present.ms` published as `4.28–4.87`, and only two of the reviewer's eight samples fell inside it; the real spread is ±20%, not the "around 10%" claimed | Re-measured, eight more samples. Published as **~4.2 (3.6–5.2)** and **~1.7 (1.5–2.1)** over sixteen runs, with the spread stated as ±20% and load-dependent |
| **G4** | The gate's PENDING count used an allowlist of id prefixes, missed `entry-`, and printed 52 where the file has 53. "A count that is off by one is worse than no count" | Counts by row *shape* — `\| <id> \| T<n> \|` — so a new prefix can never silently drop out |

Also corrected while in there: the gate is ~40 s, not ~35 s — the demo run was added after
that number was taken.

### Carried into P1

| id | Finding | Phase |
|---|---|---|
| F-B2a | `golden.sh` matches the verdict *string*, so a multi-line verdict starting with `CAPTURED` would count as success. Unreachable today only because `finish()` exits immediately after printing — which is exactly the kind of "safe by accident" the reviewer is right to refuse | P1 |
| F-B2b | If `VOID_SCENE_LIST` fails, `table.tsv` is empty, the loop never runs, and `capture()` returns success having captured nothing | P1 |
| F-B2c | `compare.ms` drops a row with fewer than 8 cells silently — the same family as the malformed-budget bug fixed loudly two lines below it | P1 |
| F-B2d | `benchUi` emits ~9 874 `[sg][error]` lines on stdout; the row parser survives them by accident, and a sokol message with one dot and one space would parse as a metric row | P1 |
| F2 | Fold DPI into `Scene` state when `begin2d` takes a float logical size | P1 |
| F3 | Commit a per-scene counter snapshot beside each golden | P1 |
| F9 | Update the two stale `Parked at:` lines in `~/metascript/.inbox/compiler/` | P1 |
| F13 | ≤100 columns in P0's new files — 40+ lines over, worst 177 | P1 |
| F14 | Record RGB-only capture as a stated limit of T2 | P2 |

`parseFloat64` has one asymmetry worth carrying forward too: unlike `parseInt32` it neither
trims nor reports unparseable text, returning `0.0` silently. It is safe today only because
the bench row parser splits on `" "` so the field never carries spaces. P1.

### Verdict

**SHIP WITH FOLLOW-UPS.** P0 is done. P1 may start.
---

# P1 — The display list

Diff reviewed: `b70b5fa..36b3c43`, 70 files, +4628 / −865. Ten commits.

Both passes were run by fresh reviewers that did not write the code. **The defect pass was
not `/code-review high`**: that command is user-triggered in this harness and cannot be
launched from inside a session, so a separate adversarial reviewer was briefed for the same
job — find defects, cite file:line, give a failure scenario, separate what was traced from
what was suspected. Recorded here because a reader should not assume the usual tool ran.

## Verdict: **SEND BACK** — three blockers, and a fourth the defect pass found

Neither reviewer saw the other's output. **Both independently returned the same two
blockers**, which is the strongest signal in this page so far.

---

## The blockers

### B1 — the counter that closes the headline defect is a literal

`src/void2d/batcher.c:129` is `int void2dBuffersAlive(void) { return 3; }`.
`tests/bench/baseline.json` gates `ui.buffersAlive == 3` and `sprites.buffersAlive == 3`, and
`tests/bench/check.ms` lists it among the hard-gated metrics. **The assertion compares a
constant to a constant.** It would still print 3 if every Label allocated a buffer again
tomorrow — which is precisely the defect it is cited as having closed.

Worse, `docs/VOID2D.md` publishes the number in a column headed **measured**, as the evidence
that the ~126-node cap is gone.

It also miscounts what it names: `s_vbuf` and `s_fsQuad` are two *buffers*, the third thing is
the font *image*, and it ignores the up-to-16 render-target images the new pool holds and the
retired atlases waiting to be freed.

Against `CLAUDE.md` "Measurements are measured, not asserted" and TESTING.md "Distrust the
harness before the engine". The shape it needs is the one `void2dAtlasImagesAlive()` already
has: made minus freed, incremented at the real `sg_make_buffer` / `sg_destroy_buffer` sites.

### B2 — `void2dFrameBegin` treats a bracket as a frame, which re-opens a defect this phase deleted

Verified in the pinned sokol: `append_pos` is reset only when
`buf->cmn.append_frame_index != _sg.frame_index` (`deps/sokol/sokol_gfx.h:27551-27552`) —
once per **sokol frame**, at `sg_commit`. But `ensureVertexBuffer((int)vertexBytes)`
(`batcher.c:465`) sizes the buffer for **this bracket's** bytes alone.

`src/examples/renderer2d.ms:222-241` runs **two brackets per frame**: the manual filter
brackets, then `sc.present()`. The second bracket's append therefore accumulates on top of the
first. Past the end sokol sets `append_overflow`, **copies nothing**, and still returns a
start position — so every draw in that bracket reads whatever was in the buffer before.
Silent in release; `VALIDATE_ABND_VBUF_OVERFLOW` in debug.

That is the exact mechanism the "Per-frame vertex cap" defect text named —
*"`sg_append_buffer` accumulates across flushes within a frame"* — and
`tests/PENDING.md debug-abort:vertex-cap` was deleted on the strength of a **single-bracket**
re-run. The defect is not dead; it moved up a layer.

Two more per-sokol-frame resources are re-armed per bracket by the same function:
`s_atlasUpdated`, which guards sokol's one-`sg_update_image`-per-image-per-frame rule (a hard
`SOKOL_ASSERT`), and `s_drawCallCount` / `s_uploadCount`, so after a two-bracket frame the
counters describe only the last bracket.

And when growth *does* fire in the second bracket, `ensureVertexBuffer` destroys and re-creates
`s_vbuf` while the first bracket's already-encoded draws still reference it: benign on D3D11's
immediate context, a use-after-free on Metal and WebGPU. That is guardrail 9.

### B3 — an exit criterion reported as met is not met, and the record does not say so

*"No `sg_*` call happens between the start and the end of the tree walk — assertable, because
the stream is the walk's only output."*

It is not. `render.ms` `acquireTarget` → `allocRenderTarget` → `sg_make_image` + `voidMakeView`
runs inside `draw()`, and a fontstash atlas resize inside text layout runs `fons_resize` →
`fons_create` → `sg_make_image` mid-walk. `draw.ms` half-admits it — "the only sokol calls left
here are the ones that are not drawing — creating a render target, opening a pass — and those
are the host's, not the walk's" — but creating a *filter* target is the walk's.

The P1 Measure table has no row for this criterion, so it reads as met.

### B4 — Glow and DropShadow still apply the group alpha twice

Found by the defect pass, confirmed by reading. `drawFiltered` computes `na = a * n.alpha` and
then calls `drawContent(n, na, vw, vh)` — and `drawContent` opens with `const na = a * n.alpha`
again. The sharp original therefore draws at `a · alpha²`.

This is the defect the commit message and the `drawFiltered` docstring claim to have closed
("alpha is applied once… before, a group at 0.5 came out at 0.25"). It **was** fixed on the
Blur branch, which returns early, and left standing on the Glow/DropShadow branch.

**The phase's own golden set is arranged so that it cannot catch this.** `filter/glow` and
`filter/dropShadow` use a host at alpha 1; `filter/groupOpacity` — the scene that was read
pixel by pixel against two models — uses `blurFilter(0.0)`, which is the branch that was
already right. A fix without a scene at alpha ≠ 1 on the Glow branch would be worth nothing.

Same site, second half: the sharp original is drawn by a **second walk of the subtree into the
swapchain** rather than by compositing the target that already holds it, so the "composites
once" property proved for Blur is false for Glow and DropShadow, and the docstring's "one
walk, one sync" is false for them too.

---

## Further defects to fix with the blockers

| | |
|---|---|
| **D1** | Filter composites and blur downsamples inherit `curSampler`/`curEffect` from an unrelated sibling. `endTarget` restores what was current when `beginTarget` ran, and `drawFiltered` emits its composite with no `setSampler`, and on the Blur branch no `setEffect`. A grayscale sibling therefore tints the next node's blur, and `defaultSmooth = false` point-samples every downsample step — which degenerates guardrail 3's kernel. `void2dBlur` hardcodes the linear-clamp sampler for its tap pass for exactly this reason; the blit does not. |
| **D2** | A mid-frame glyph-atlas resize corrupts every label laid out before it. `fonsExpandAtlas` changes the normalised texture size, so quads emitted before the expand carry old-atlas UVs, while `emitNode` resolves `fontView()` at **emit** time — always the newest atlas. The retired-atlas list defers destruction to protect commands that bind the old view, and no label command ever does; it guards a case that cannot arise and misses the one that does. Worse, the straddling label records `lastAtlasGen` *after* `buildGlyphMesh`, so it is never re-laid-out. This is the scene `regress/atlasFull` is, and its closure was claimed on "10 runs, 1 output" — deterministic is not correct. |
| **D3** | `applyScissor` multiplies by `s_dpiScale` unconditionally, but inside a target pass the viewport is `rtW/rtH`, computed in *logical* units and handed to `allocRenderTarget` as a pixel size. A Mask inside a filtered subtree at DPI 1.5 therefore scissors 1.5× its zone — and the same root cause means a filtered subtree renders at 1/1.5 resolution and is upscaled, against the P1 exit line about DPI 1.25/1.5. No golden covers it: all five filter rows are at dpi 1.0. |
| **D4** | A `Draw` following a `CMD_KIND_BLUR` in the same pass would skip its `sg_apply_pipeline`, because the Blur branch does not clear `lastPipeline`/`paramsValid`/`fxValid`/`scissorApplied` the way the target branches do. Masked today only because the blur block is always `TargetBegin, Blur, TargetEnd` on its own. |
| **D5** | `snapshot.ms` depends on a global no test resets: `sceneSmooth` is set only by `Scene.presentAt`. `breaks.txt` records `sampler:2`/`sampler:3`, which shift to 0/1 if any test in the same process renders a scene with `defaultSmooth = false`. `record()` should set it. |
| **D6** | `BreakReason.Capacity` is produced by no emitter, and the only thing that names it is a test asserting its name. |
| **D7** | `golden.sh capture()` still decides purely from a printed line — the runner's exit status is discarded with `|| true` despite the comment saying it is used, and nothing checks that the PNG was written. |
| **D8** | Per-draw cost: `sg_query_features()` and a 16-entry `voidIsRenderTargetView` scan run **twice** for every Draw — 40 000 scans per frame on the bench whose `present` the phase reports as not met. Both are frame-invariant. |

---

## What the reviewers checked and found sound

Recorded because a review that only lists faults is not a measurement either.

- **The `draws ≤ 253` argument is correct, not an excuse.** The design reviewer went looking
  for one: 126 × 2 + 1 = 253 is the *defective* renderer's number, the bench alternates a card
  and a label per node, so 10 000 labels is 20 000 binds and a display list cannot collapse
  what it faithfully records. The reviewer singled out that P2's own Measure anchor was
  corrected from "253 → ≤ 4" to "20 000 → ≤ 4" so P2 cannot inherit a number it never had.
- **The guardrail-8 millisecond claim** is backed by an interleaved same-box A/B against the
  parent commit, and the warn factor was not raised to fit a noisy reading.
- **`filter/groupOpacity`** read pixel by pixel against both a double-blend and a
  single-composite prediction, matching the latter to within 1/255.
- **The blur kernel is one implementation** serving both the node filter and the manual
  helper — "two would drift".
- **`void2dGrowthTarget` is clean** and its T1 boundary test is real, including the
  drop-past-cap, which is the only way a 192 MB cap is ever exercised.
- **No compiler workaround hides a bug.** The two "on this compiler" notes are documented
  language limits, not defects, and both carry their consequence.
- **The `addChild` fix was the right thing to do out of scope.**
- **PENDING discipline held on the hardest case**: the three T1 rows were deleted only after
  the assertion existed, not before.

## The line worth keeping

> Make every gated number come from a site that can move. P2's entire thesis is a number going
> down; a number that can only go down is not evidence.

## Follow-ups the design pass carried, to be handled with the fix or assigned

| id | Follow-up | Phase |
|---|---|---|
| P1-a | `VOID2D.md` still says the three T1 rows are open; `PENDING.md` says deleted. Reconcile | P1 |
| P1-b | `docs/HEAPS.md:323-324` still lists `smooth`/`tileWrap` and filter semantics as missing | P1 |
| P1-c | 37 → 45 goldens everywhere: `TESTING.md:162, :267, :290`, `VOID2D.md` guardrail 9 | P1 |
| P1-d | Two PENDING rows still stamped P1: `backend:gles3-desktop`, `legacy:tests/layout.test.ms` | P1 |
| P1-e | P0's F2 (DPI into `Scene`), F3 (counter snapshot per golden), F13 (≤100 columns) — do them or record them as deferred with a phase | P1 |
| P1-f | Gate `uploadBytes`; wire `void2dAtlasImagesAlive()` into the bench and the baseline; delete or rename `instanceBufferBytes()` | P1 |
| P1-g | `end2d()` should flush targets or assert `targetCommandCount() == 0` — a forgotten `flushTargets()` is silent today | P1 |
| P2-a | T1 scenes for `break:view` and `break:effect` (neither needs a GPU); remove or produce `BreakReason.Capacity`; add TESTING.md's "every break reason is reachable from an emitter" cross-check | P2 |
| P2-b | Document the `srcPremult` carve-out: the premultiply correction is disabled by any colorAdd or colour matrix — right for the silhouette, wrong for an unrelated matrix on a filtered subtree | P2 |
| P2-c | State the 192 MB cap's reason against GPUI's 256 MiB; rename "instance" to "vertex" in P1's Lands bullet until P2 makes it true | P2 |
| P2-d | Six dead imports in `draw.ms`; the stale `regressAtlasFull` and `releaseRetiredAtlases` comments; `startCommand` zeroing `CMD_EFFECT` to 0 rather than `NO_EFFECT` | P2 |

**P2 does not start and nothing lands until the blockers are fixed and the phase is
re-reviewed.**

---

## Re-review after the send-back: **SHIP WITH FOLLOW-UPS**

A third fresh reviewer, which wrote neither the code nor the first two reviews, was given the
charge sheet above and asked whether each item was fixed or merely moved. It ran T0 and the
golden self-check and **re-captured 13 of the 48 goldens** rather than trusting the gate log.

### The four blockers

| | |
|---|---|
| **B1** | **Fixed, and it can move.** `buffersAlive` is made-minus-freed at the real `sg_make_buffer` / `sg_destroy_buffer` sites. The reviewer went further than the fix claimed and cross-checked `uploadBytes` against the vertex counts — ui `293 340 × 32 = 9 386 880`, sprites `60 000 × 32 = 1 920 000` — confirming those rows are readings and not typed numbers. |
| **B2** | **Fixed, all four sub-claims**, and the reviewer traced the new retirement path for safety: bindings are re-applied on every Draw, the first bracket's draws were already submitted against the old buffer, and the drain runs after `sg_commit`, which is correct for Metal and WebGPU too. |
| **B3** | **Restated, which the reviewer called the right answer** — with the carve-out stated in the exit table and in the Known-defects line — but noted the T1 test asserting it can only record scenes with no filter and no text, which are the two sites that create images. The criterion is asserted where it was never in doubt. |
| **B4** | **Fixed and measured.** The reviewer recomputed both models independently and got the same bytes: twice-applied (75.9, 68.2, 45.3) → **(76, 68, 45)**, once-applied (131.3, 113.5, 59.9) → **(131, 113, 60)**. It also checked for the use-after-free that compositing `rt` after the blur chain invites, and found `acquireTarget` marks `rt` busy for the whole frame so `blurTargetPooled` can never recycle it. |

### What the re-review found that the first pass had not

- **D3 was only half fixed, and the unfixed half was unrecorded.** The scissor scaling is real
  and `filter/maskAtDpi150` discriminates hard. But the same root cause has a second
  consequence: `render.ms` sizes a filter target from bounds in **logical** units and hands
  that to `allocRenderTarget` as a pixel size, so at DPI 1.5 a filtered subtree renders at
  1/1.5 resolution and is upscaled. Untouched, in no doc and no row — **and the new golden is
  at dpi 1.5, so it now freezes that softness as correct.** It has a row of its own now
  (`filter-target-sized-in-logical-units`), which says explicitly that when the target is
  sized in device pixels that golden moves, and the move is the fix landing.
- **D5 was partially fixed.** `setSceneSmooth(true)` runs *after* `begin2d`, and `resetList()`
  inside `begin2d` has already computed `curSampler` from the previous value — so the first
  node still emits a spurious `break:sampler`. Latent, and exactly the process-history
  dependency D5 named.
- **D8's commit subject overclaims.** `sg_query_features()` was hoisted; the 16-entry view scan
  went from two per draw to one and **cannot** be hoisted, because it depends on the draw's
  view. The in-code comment says "one lookup, not two" and is right; the subject line says
  "two frame-invariant queries leave the draw loop" and is not. `ui.present.ms` was also not
  re-measured afterwards.
- **A comment of mine is wrong.** `blitTarget`'s note claims a grayscale sibling could tint a
  downsample; `beginTarget` already resets `curEffect`, so only the sampler half of that was
  ever possible. The fix is right; the reason given for half of it is not.
- **The paper class recurred in the very commit charged with cleaning it.** `PENDING.md` still
  said `buffersAlive` 3 while two other files said 2; `TESTING.md`'s tier table was updated to
  a P1 number under a header reading "State after P0" while T0 stayed at 431 and T4 at "ten
  counters"; the four new PENDING rows were filed under **Image budgets**, whose prose reads
  "None."; and `VOID2D.md` guardrail 9 had nested bold that renders wrong. P0's design review
  logged this same class as **G2**. One phase later, same table.
- **F13's number was not reproducible.** The row said "31 in P1's own files"; the reviewer
  counted 39 and the row named no file set and no command — which is P0's own **F4** complaint
  answered there and not here.

### Closed before this record was, with the re-review's numbering

**F-1** `PENDING.md` buffersAlive 3 → 2 · **F-2** the tier table's header and its T0 and T4 rows
now agree with what the gate prints (579 tests over 35 files; nine gated counters) · **F-3** the
four rows moved into a headed section with the right column count · **F-4** the nested bold ·
**F-6** D3's unfixed half has its row, and that row says the dpi-1.5 golden currently freezes the
defect · **F-17** the line-length row now carries the command that produces its numbers —
`awk 'length > 100' $(git ls-files '*.ms') | wc -l`, which gives **204** repo-wide and **79**
over the ten files P1 wrote or rewrote, correcting the 31 that was in the record.

**F-7**, the thing the reviewer said it trusted least: forgetting `void2dFrameEnd` used to make
the glyph atlas **silently** stop uploading before it made anything fail loudly. The batcher now
counts brackets since the last frame end and complains once past sixteen, naming the call and
what breaks without it. Proven by removing `frameEnd()` from `Scene.presentAt` for one run — the
complaint fired once — and restoring it — no complaint.

**F-5**, disclosed rather than fixed: **P1-f is two thirds done.** `uploadBytes` and
`atlasImages` are gated; `instanceBufferBytes()` is still named for an instance buffer that does
not exist and still returns `s_vbufBytes` (**F-15**, P2, with P2-c). **P1-g landed as a
`console.log`, not the assert that was asked for** — a forgotten `flushTargets()` now says so
instead of failing, which is weaker than the follow-up's wording.

### Carried into P2

| id | Follow-up |
|---|---|
| F-8 | Size filter targets in device pixels; `filter/maskAtDpi150` moves when it lands |
| F-9 | `setSceneSmooth` before `begin2d`, in `record()` and in `presentAt` |
| F-10 | `renderTargetsAlive()` beside `atlasImagesAlive()`, gated — nothing counts the 16-slot filter pool against sokol's 128 |
| F-11 | `VOID2D_MAX_RETIRED_BUFFERS` overflow falls back to the immediate destroy the list exists to prevent, silently |
| F-12 | A `golden.sh --self-check` case for "said CAPTURED and wrote no png" |
| F-13 | Correct the `blitTarget` comment |
| F-14 | ~~Re-measure `ui.present.ms` after D8~~ — **done 2026-09-21**, as P2's first step, and it found more than it was asked for: *both* millisecond baselines were unreproducible by their own commit's binary on a box proven quiet (10.8% CPU). Interleaved A/B `6a997ee` vs `544ea4a`: ui 19.95 vs 19.86, sprites 2.51 vs 2.48 — guardrail 8 holds, and 17.8 / 1.63 were simply wrong rather than stale-because-busy. Baselines re-taken to 19.9 / 2.5 with `warnFactor` untouched; the gate's permanent `WARN sprites.present.ms` is gone. P2's Measure line carried two targets derived from the phantom numbers and both were corrected — `benchSprites ≤ 1.7 ms` would have failed this phase on its first run for a reason with nothing to do with this phase |
| F-15 | `instanceBufferBytes()` → `vertexBufferBytes()` |
| F-16 | State that a glyph first needed in a second bracket is one frame late, now that `s_atlasUpdated` is per frame |
| F-17 | *(done above)* |
| P2-a..d | The design pass's own list, unchanged |

### The one thing the re-review still would not trust

> the `void2dFrameEnd` contract … it is called from exactly one function in the whole tree, and
> forgetting it makes the font atlas stop updating **silently** before it makes every frame drop
> loudly. Every other mistake in this phase now fails at the site of the mistake — this one fails
> three layers away, in text that renders from a stale atlas.

F-7 answers the *silence*, not the *contract*: the call is still one a host can omit. Folding it
into `src/sokol/gpu.ms commit()` would make it unforgettable and is the first thing P2 does if it
is not done sooner.

**Closed at `d80f9e4`, before P2 opened**, and one level lower than the line above proposed.
`src/sokol/gpu.ms` cannot call into void2d: `scene.ms:9` already imports `commit` from it, so the
fold would be a module cycle and a layering inversion — the sokol layer would depend on a layer
above it. The hook goes in the C bridge instead, where `batcher.c` already includes `bridge.h`:
`voidCommit` fires a function pointer that defaults to null, and `void2dSetup` registers
`void2dFrameEnd` into it. That ties the reset to the event that causes it — sokol rewinds a
buffer's append cursor at `sg_commit` — rather than to a caller's memory. `scene.ms` no longer
calls `frameEnd()` at all, and the export stays only so a test can close a frame it never
committed.

Shown failing before it was shown passing, as the class of fix requires. With the registration
commented out and everything else identical, `out/benchUi.exe` printed
`void2d: 17 brackets since the last void2dFrameEnd` and then dropped **every** frame —
`frame needs 206 511 360 bytes of geometry, cap is 201 326 592` — because the per-frame append
budget never rearmed. With it restored, the same binary printed all nine counters at their
`tests/bench/baseline.json` values and the full gate read `48 pass, 0 pending, 0 fail of 48`.

**The limit is now closed.** This audit found that `voidCommit` was still not the only
`sg_commit` path: `renderer.endFrame` reached the duplicate `gpu3dCommit` wrapper. The wrapper
and its C declaration are gone; void3d imports the shared bridge commit. The permanent mixed
capture draws 3D and void2d in one pass, commits once, then starts a second frame and requires
the captures to match with a fresh one-draw void2d counter each time.

### Two things about the evidence itself, recorded because they qualify it

The reviewer verified 13 of the 48 goldens by running them; the rest rest on a gate log that is
gitignored. And `harness/mustFail` is counted among the 48 and passes **by differing** — which is
its job, and worth saying out loud whenever the number 48 is used.

### Verdict

**SHIP WITH FOLLOW-UPS.** P1 is done. P2 may begin, and the phase may land.
