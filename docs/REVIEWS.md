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

**Diff:** `f2ca41d..HEAD`, 16 commits.
**Defect pass: 10 findings, all confirmed, all fixed** (`f1d088c`).
**Design pass: SEND BACK** on four blockers, then fixed (`829aa5f`) and re-reviewed.
**Final verdict: see "Design pass — re-review" below.**

## Defect pass — `/code-review high`

Ten findings, every one real. Fixed in a commit of its own, `f1d088c`.

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

The same reviewer, re-reading after `829aa5f`. All four blockers closed, each demonstrated
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

Diff reviewed: `b17bb7c..77b5054`, 70 files, +4628 / −865. Ten commits.

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
| F-14 | ~~Re-measure `ui.present.ms` after D8~~ — **done 2026-09-21**, as P2's first step, and it found more than it was asked for: *both* millisecond baselines were unreproducible by their own commit's binary on a box proven quiet (10.8% CPU). Interleaved A/B `da36060` vs `817f2c8`: ui 19.95 vs 19.86, sprites 2.51 vs 2.48 — guardrail 8 holds, and 17.8 / 1.63 were simply wrong rather than stale-because-busy. Baselines re-taken to 19.9 / 2.5 with `warnFactor` untouched; the gate's permanent `WARN sprites.present.ms` is gone. P2's Measure line carried two targets derived from the phantom numbers and both were corrected — `benchSprites ≤ 1.7 ms` would have failed this phase on its first run for a reason with nothing to do with this phase |
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

**Closed at `46d939b`, before P2 opened**, and one level lower than the line above proposed.
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

---

## P2 design review: **SEND BACK**

A fresh reviewer that wrote none of P2 read the phase diff, roadmap, guardrails and test plan.
It accepted the one-draw UI stream, unified instance layout, sprite/UI separation, filter-target
repair, resource counters and buffer-retirement fix, but refused the phase on seven findings:

| id | Finding | Resolution before re-review |
|---|---|---|
| P2-R1 | CPU box snapping and shader AA ignored the active target's DPI | `currentRenderScale()` now follows the target stack; CPU edges/strokes round in device space and `ui_params.viewport.w` carries the same scale into AA. T1 pins swapchain/target restoration and the DPI goldens moved |
| P2-R2 | A styled Rect with a colour effect silently became a flat square quad | The combination now reports a named rejection and emits no lossy fallback. T1 pins zero UI instances, vertices and draws; `ui-box-color-effect` assigns full unified-shader support to P6 |
| P2-R3 | The fractional-split test compared one expression with itself | It now snaps two independently positioned adjacent boxes and checks both the shared edge and the rounded outer extent at all three DPIs |
| P2-R4 | The one-instance card and rotated Mask were separate scenes | `prim/cardOneInstance` now puts the styled card inside the 37-degree Mask, keeps rounded corners visible, crosses the clip with its shadow, and remains one draw/instance |
| P2-R5 | The Measure text called 20 000 × 108 B the measured stream | Corrected to the gated **48 890 instances / 5 280 120 B**; 20 000 remains the node count |
| P2-R6 | Guardrail 9 still reported 56 D3D11 scenes | Corrected to the current **67 / 67** suite and dated to the P2 review gate |
| P2-R7 | Tracked docs disagreed on ownership of the legacy Yoga tests | Both now name compiler card `2026-09-22-imported-interface-literal-reachability.md`, the parked standalone file and compiler ownership |

The same pass called out CODE-STYLE review discipline. P2's new Bayer dispatch is now a `match`;
the repository-wide 278-line length debt remains measured and assigned to P6. Its reference to
counted loops is not a §14 violation: §14 forbids a counted `while`, while the changed code uses
`for`. No compiler workaround was introduced; the imported-interface failure remains parked at
the compiler card.

---

## P2 re-review: **SEND BACK**

A second fresh reviewer verified all seven first-pass findings as closed, then found three
different omissions inside the adopted GPUI snapping row. This is not the stride-risk fallback
case in P2: splitting the 108-byte instance layout would change none of these device-space
rules. The response was to make each rule explicit at the layer that owns it:

| id | Finding | Resolution before second re-review |
|---|---|---|
| P2-R8 | sokol truncated fractional mask scissor arguments independently and could move the far edge inward | The replay now floors the near device edge, ceils the far edge, clamps that rectangle to the target, and passes only integer-valued floats to sokol. T0 calls the same C helpers at fractional and negative edges |
| P2-R9 | A shadowed axis-aligned box snapped the inflated shadow quad, so a fractional margin moved the reconstructed fill edge off-grid | The visible box snaps first; the shadow offset snaps separately; only then does the margin inflate the quad. T1 reconstructs both visible x edges from the recorded instance and requires device integers |
| P2-R10 | A rotated positive border could remain thinner than one device pixel | The UI vertex shader now mirrors `dilateStroke`: per local axis, zero stays zero and a positive box border is at least one physical pixel. T0 pins the arithmetic and `prim/perSideBorders` carries a rotated 0.2-unit side at DPI 1.25 |

The re-review also found two new counted `while` loops in P2-touched gradient/texture
triangulation despite CODE-STYLE §14. They are counted `for` loops now. The remaining
non-uniform-SDF approximation was already disclosed in `VOID2D.md`; `sdf-non-uniform-bound`
now assigns its independent numerical bound to P6 instead of pretending the old pixel golden
proves one.

---

## P2 final re-review: **SEND BACK**

The fresh final reviewer verified R1-R10 closed, then found one bounds-design omission with two
observable failures: the emitter knew the analytic shadow quad, but culling and filter-target
sizing still knew only the fill box. This is unrelated to P2's stride fallback. The repair removes
the split ownership rather than adding two exceptions:

| id | Finding | Resolution before final review |
|---|---|---|
| P2-R11 | A box wholly outside a viewport or active Mask was dropped even when its outset shadow reached the visible area | `boxRenderBounds` now computes the snapped box and outset-shadow quad once; both emission and viewport/Mask culling consume it. T1 places the fill beyond the viewport and requires the shadow instance |
| P2-R12 | A node filter sized its render target from the fill box and clipped an analytic BoxStyle shadow before applying the filter | Public `getBounds` consumes the same rendered bounds, so `drawFiltered` allocates for the analytic shadow before adding its own radius. T0 pins the exact outset bound and `filter/blur` combines the two mechanisms in a D3D11 golden |

Inset shadows remain fill-bounded. The combined golden's extra UI pipeline run changes only
`filter/blur` from five to six draws; its five pooled render targets remain unchanged.

---

## P2 ship review: **SHIP WITH FOLLOW-UPS**

A fourth fresh reviewer read the repaired live tree and all three SEND BACK records. It found no
P2 blocker: R1-R12 are closed, and the remaining work is already named under P3-P6 or the
compiler card. The final `sh scripts/gate.sh --web` ran **708 / 708** tests, **67 / 67** D3D11
goldens, three coverage oracles, twelve loud skips and zero failures; the demo and mixed 3D/2D
frame ran, both web backends built, and WebGL2 drew the demo headlessly.

| Question | Decision and evidence |
|---|---|
| 1. Exit criteria | SHIP: the UI bench is one draw, the 37-degree masked card is one instance, DPI/split/zero-border behavior is pinned, and the sprite-only path remains 64 B with no SDF mode |
| 2. Measurements | The six-pair A/B remains UI **21.36 → 12.13 ms** and sprites **2.11 → 1.77 ms**; the gate owns one UI draw, **48 890** instances and **5 280 120 B** uploaded |
| 3. Guardrails 1-9 | Preserved: side tables, retained filter targets, analytic AA without MSAA, the narrow sprite path and the honest **1 / 7** measured-backend conformance status |
| 4. GPUI dispositions | Display-list batching, local-space SDF, clipping, snapping, gradients and image modes keep the accepted Take/Take-adapted choices; no W/P exclusion moved |
| 5. h2d spirit | Retained painter order, S·R·T transforms, Mask/filter nodes, bounds, Tile offsets and pivots remain h2d-shaped; unsupported styled colour effects fail loudly |
| 6. Defects | The rotated-Mask, active-clip, pivot, gradient and batching defects plus R1-R12 are fixed at their owner. R11/R12 now share `boxRenderBounds` instead of parallel exceptions |
| 7. Test tiers | T0 owns arithmetic and bounds, T1 owns streams and negative reachability, T2 owns pixels and counters, T3 owns independent coverage, and T4 owns deterministic budgets |
| 8. Compiler discipline | The imported `FlexStyle` TypeInfo failure remains parked at `2026-09-22-imported-interface-literal-reachability.md`; no workaround entered void |
| 9. CODE-STYLE §14 | P2 Bayer dispatch is a `match`, its counted loops are `for`, and the measured **215-line / 31-file** repository debt plus non-uniform-SDF bound remain assigned to P6 |
| 10. Refusal to merge | None. Emission, viewport/Mask culling, public bounds, filter allocation and outset/inset behavior now consume one rendered-bounds contract |

Follow-ups are not P2 escape hatches: P3 owns atlas/text metrics and the first multi-backend
conformance run; P4 owns editor text and UCD; P5 owns retained ranges, Mask scrolling and the
h2d oracle; P6 owns styled-box colour effects, the non-uniform-SDF bound, line-length hardening
and per-module wasm budgets.

---

# P3 — The glyph layer

The phase diff is `2fe84d3..333b70c`, steps 1-8; steps 1-3 reached `main` mid-phase as `2936e0b`.
The defect pass was `/code-review high` in Claude Code, verified finding by finding in the main
session. The design pass was a fresh Claude subagent that had written none of P3.

## Defect pass — `/code-review high`

Ten findings; eight confirmed and fixed, each in its own commit. `sh scripts/gate.sh` was GREEN
after them: 859 tests, D3D11 69 / 69, no golden moved.

| Finding | Resolution |
|---|---|
| The empty line after a trailing newline had `byteStart` 0, so a caret or click there jumped to the start of the text | `efa0c7c`: it starts at the text's byte length; T0 pins `byteForX` and `xForByte` on it |
| `splitText` sliced codepoint indices out of a UTF-16 `slice`, so an astral character shifted every later line | `329dab9`: slices each line's byte range; T0 wraps text holding an emoji |
| Label bounds had become line boxes only, so synthetic italic, negative bearings or a taller fallback lost their ink to filter targets and culling | `cc00e7d`: bounds are line boxes ∪ glyph ink boxes at the layout size; T1 fails without the union |
| A label placed twice in one frame released its tiles mid-frame; at 16 pages another label could reclaim that page while this frame's quads still sampled it | `5a2e85e`: a page drawn from in the current frame is never reclaimed. The frame serial comes from `void2dFrameEnd`, `begin2d` hands it to the atlas, `emitLabel` marks each page it draws from. T0 pins the fence, T1 the wiring |
| `glyph.c` handed out unbounded page handles while the GPU side keeps 64 views and returned view 0 past them | `7721356`: one shared cap, `VOID2D_MAX_GLYPH_PAGES`; a page past it is refused with an error and the atlas reports `Full` |
| An atlas refusal was reported once per process, and then glyphs vanished silently | `a241496`: every placement that loses glyphs reports how many and why |
| `sizeAdjust` divided by a fallback's line height with no zero guard | `9674309`: a face without a line height is reported and keeps the primary size |
| A comment carried narrative | `0e4607b`: trimmed to its one hazard |
| Kept: a glyph rasterized into a page an earlier bracket already uploaded is one frame late | Already `tests/PENDING.md glyph-page-second-upload`: sokol allows one `sg_update_image` per image per frame |
| Kept: 64 page views scanned per draw command, a synthetic outline parsed twice per rasterization | No steady-state cost: rasterizations are 0 and the UI bench is one draw |

## Design pass: **SEND BACK** — three defects in the record, none in the code

The reviewer found no code it would refuse to merge. It refused the phase on three record
defects, the pattern P1-B3 and P2-R6 were sent back for.

| id | Finding | Resolution before re-review |
|---|---|---|
| P3-R1 | The exit's five-backend conformance run was not met (2 of 7 surfaces), and the record did not say so: guardrail 9 still read "67/67 at P2 … the full five-backend run is P3", TESTING.md still said 67, and five `backend:*` rows still named P3, so closing P3 would orphan them | `39097c2`: "Measured at P3 step 8" states both unmet halves (2 of 7 backends; the Zed capture owed by the human). Guardrail 9 reads 69 / 69 plus WebGL2 65 / 69. GLES3 desktop and WebGPU move into P6's Lands and Exit; Metal and Android wait on the human's hardware. `ae04731` makes the web run print its renderer, `ANGLE (NVIDIA, NVIDIA GeForce RTX 5090 ... Direct3D11 vs_5_0 ps_5_0, D3D11)`: the WebGL2 number is the GLSL ES path and GL's conventions on the same GPU and driver, not a second driver, and the record says so. All seven `text/` scenes are byte-identical there |
| P3-R2 | Step 8 decided the rasterizer, but colour emoji and explicit-versus-fallback presentation still "wait on step 8's decision" and no phase owns them. P3's Lands promised both, and P6 takes emoji "only if P3's captures asked" | `d32839a`, on the human's decision: colour emoji is a P6 compile-time module (guardrail 6) that reads CBDT/sbix strikes through `stb_image` and COLRv0 layers into P3's RGBA pages, with presentation and deferred faces beside it (PENDING `font-colour-emoji`). Whole-grapheme selection goes to P4's Lands (`font-grapheme-selection`), and `glyph-page-second-upload` to P5's with F7's fix direction |
| P3-R3 | The `present` debt, UI +1.4 to +1.8 ms, lived only in P3's text. P5's Measure said only "must not regress", so P5 would inherit the gap as its baseline. The reviewer judged P5 the right owner: its retained ranges remove the per-label re-emission that carries the cost | `155603e`: P5's Measure requires UI `present` at or below the pre-P3 control `8a473f3` under `scripts/bench-ab.sh`, on a box checked quiet |

Recorded with the send-back: `7552dc2` writes down two divergences from GPUI that were not
written — the interim bitmap transformed regime (the SDF regime is P6's) and the refusal of a
glyph larger than a page, where GPUI gives it its own texture — and marks the atlas page kinds
and the rasterizer resolved. `572d863` closes "text lines centred on fractional pixels" in Known
defects and states that wrapping breaks at U+0020 only. `a33ec36` gives a Label dropped without
`dispose` a PENDING row owned by P5.

### Follow-ups the design pass carried

| id | Follow-up | Owner |
|---|---|---|
| F1 | `placeLabel` marks a placement valid even when glyphs were refused, so a static label loses them for good once the atlas pressure passes | P4 |
| F2 | Every layout call, `calcTextWidth` and `splitText` included, recomputes the face's decoration metrics from 95 glyph lookups, and `textWidth()` / `textHeight()` copy the whole layout. Cache heights per face and gate a measure call in T4 before the host's Yoga measure binds to it | P4 |
| F3 | Filter targets open at an unsnapped `xMin`, so pixel-exact text inside a filter at DPI 1.25 or 1.5 is resampled. Snap the target and add `text/filteredDpi125` | P4 |
| F4 | `\r` and tab draw `.notdef` and probe every fallback face; wrapping follows GPUI's break rule; `align` is centred about the origin, where h2d centres inside `maxWidth` | P4 |
| F5 | The two undocumented GPUI divergences, the interim bitmap transformed regime and the oversized-glyph refusal | closed in `7552dc2` |
| F6 | A Label dropped without `dispose` pins its page: PENDING `label-dispose-pins-page` | P5 |
| F7 | Fix direction for `glyph-page-second-upload`: never place new tiles on, or reclaim, a page already uploaded this frame; C knows `s_pageUploaded` | P5 |
| F8 | Pins for `7721356`, `a241496` and `9674309`. The first cannot run in the shared test process, since exhausting the process-wide page table starves every later test; it needs a standalone T0 entry | P4 |
| F9 | CODE-STYLE §14: `NO_FONT` and `-1` returns in place of `Result`, struct-first free functions, an atlas page index and a C page handle that are both bare `int32`, module data as `T[]`, 30 new lines over 100 columns, stale fontstash comments in the harness | P4, before the host binds |
| F10 | Both A/B arms read about 2.2× P2's absolute UI milliseconds at 25-33 % load: re-take `8a473f3` against the head on a quiet box before any P4 change, and file a compiler perf card if the shift follows msc 0.2.53 → 0.2.55. Then a perf card, or a stated DRC reason, for the "reference counting in the generated C" behind the `present` gap | re-take: start of P4 (P4 Measure); the card: P5 |
| F11 | Zero-area tiles are cached with no page and never reclaimed (P6). The line box uses only the primary face's ascent and descent, which P4's caret, selection and IME geometry would inherit (P4 Lands) | P6 / P4 |
| F12 | The T5 look beside Zed at 13 px, 1× and 1.5× | the human, before P4's editor exit |

### What the reviewer checked and found sound

T0 859 / 859 and both font oracles (56 / 56, 268 / 268) re-run. The GPOS reader, the gamma and
contrast table, the port of `FT_Outline_EmboldenXY` and the CSS weight order match their sources.
Every pixel-exact glyph origin is an integer, and a whole-pixel move rasterizes nothing. The
reclaim fence's serial advances only in `void2dFrameEnd`, so every bracket of a frame shares it.
The four WebGL2 failures are all mesh-path scenes, owned by P6's fringe rewrite. No compiler
workaround is hidden: the `uint64` Map lookup was parked on its card and unparked after the
recompiler fix landed.

## P3 re-review: **SEND BACK** — the fixes overstated two things and missed residue

A second fresh reviewer verified R1, R2 and R3 closed at every site the first pass named, and
again found nothing in the code. It sent the phase back on three record defects. Two of them
came from the fixes themselves.

| id | Finding | Resolution before the third pass |
|---|---|---|
| P3-B1 | `7552dc2` put "resolved" in front of the rasterizer line and left its last sentence, "Decided from captures beside Zed", a false past-tense claim about the capture R1 declares owed. The same fix and P6's emoji bullet spoke of "the RGBA pages P3 reserved", but only R8 glyph pages exist (`batcher.c` makes one page format) | `9f89d3d`: the rasterizer was decided by the FreeType experiment and its wasm cost, and the Zed look is owed. The RGBA page kind is decided and not built, and P6's emoji module builds it: the format, its view and a colour draw path |
| P3-B2 | R1's stale counts survived in TESTING.md's tier table ("State after P2", 708 tests, 67 scenes, six backends SKIP), its golden-size paragraph (67 goldens, 1 328 179 B) and PENDING's "checked on one backend" | `a667c16`, re-measured: 859 tests over 55 files; 69 goldens, **1 394 175 B**, of which 748 008 B are the 65 scenes and 646 167 B the four demo frames; 18 counters per bench scene. PENDING says two backends. `9f89d3d` also updates VOID2D's two present-tense golden counts |
| P3-B3 | Two PENDING rows named an owner whose Lands and Exit do not carry the work: `label-dispose-pins-page` (P5) and the Metal and Android backend rows (P6) | `9f89d3d`: P5's Lands release a Label's glyph tiles when it leaves the scene, on h2d's `onAdd`/`onRemove` allocation, with a T1 assertion. P6's Exit makes Metal and Android either report a pass rate from the human's hardware or stay a SKIP that names the missing run |

It also moved three follow-ups and found new record items for the P3 close. All of them are in
`9f89d3d`, `a667c16` and `f112d61`:
- **The follow-up table is corrected above.** F10's quiet-box re-take moves to the start of P4, because P4's `present` becomes P5's baseline. F11's line-box half moves to P4. F5 is closed.
- **F2 and F9 clash with P3's Unblocks**, which hands the Neon host its Yoga measure callback now. Unblocks now says the measure cost and the font API's shape move in P4.
- **Deferred faces** serve the lazy CJK families too, so they belong in the default glyph layer rather than in the emoji module. P6's Exit tests them with the module on or off.
- **P4's Tests** name whole-grapheme selection as a T1 assertion.
- **Reference docs:** GHOSTTY.md's variable-axes row, MAKEPAD.md's four-plane row (declined at step 8) and its emoji size buckets (now in P6's emoji bullet), and HEAPS.md's "P3 in progress".
- **TESTING.md:** its scene table gains `text/fontStyles`, and its cadence says WebGL2 runs with `--web`.

The phase rule on two consecutive send-backs does not apply. Neither pass found a design fault;
both found the record behind the code. The lesson is procedural: a count or an owner that moves
is swept across every tracked doc in the same commit, not only at the sites a reviewer named.

## P3 ship review: **SHIP WITH FOLLOW-UPS**

A third fresh reviewer checked B1-B3 at `ed4de3c`, file by file, against the disk. The golden
count and bytes, the tier table and the gate logs of `682966f` all match. It found nothing in the
code it would refuse. `sh scripts/gate.sh --web` was GREEN at `682966f`, and everything after it
is docs only: 859 tests over 55 files, D3D11 69 / 69, WebGL2 65 / 69 with the four listed
structural failures and all seven `text/` scenes byte-identical, through
`ANGLE (NVIDIA ... Direct3D11 ...)`. Both web backends built, at 761 810 B and 667 012 B.

| Question | Decision and evidence |
|---|---|
| 1. Exit criteria | Met and gated: `text/` byte-identical at DPI 1.0, 1.25 and 1.5; 0 rasterizations in the steady state; 2 pages after the zoom sweep; `textWidth` and per-glyph x from the painted layout; fallback with cached misses. **Two halves unmet and declared, each with an owner:** the Zed look (the human, before P4's exit) and the five-backend run, 2 of 7 (GLES3 desktop and WebGPU in P6's Lands and Exit; Metal and Android in P6's Exit, on the human's hardware) |
| 2. Measurements | Every count in the tracked docs matches the `682966f` logs. The wasm delta after the fixes is +30 169 / +30 046 B. The `present` A/B was taken at step 8, and P4 re-takes it first on a quiet box (F10) |
| 3. Guardrails 1-9 | None violated. Guardrail 9 is two measured surfaces, and the record says that WebGL2 runs through ANGLE on the same GPU. Guardrail 6 carries colour emoji as a P6 module. Guardrail 8 holds: sprites 4.93 → 4.93 ms |
| 4. GPUI fidelity | Float unhinted layout, four x-variants, the key, 1:1 sprites and the gamma and contrast table are GPUI's. The interim bitmap transformed regime and the oversized-glyph refusal are written down in VOID2D.md and GPUI.md |
| 5. h2d spirit | `textWidth`, `calcTextWidth`, `splitText`, `maxWidth`, `letterSpacing` and `lineSpacing` in px are h2d's. What is foreign is carried to P4 (F4, F9) |
| 6. Known defects | Closed at their owner, including fractional baselines. Atlas-full is closed as a class, and the refusal is now loud per placement |
| 7. Test tiers | Right tiers. The weak and missing pins are F8, and the gate's missing graduation rule for `conformance:*` rows is F13 |
| 8. Compiler discipline | No hidden workaround; the `uint64` Map card was unparked after the recompiler fix |
| 9. CODE-STYLE §14 | F9, P4, before the host binds |
| 10. Refusal to merge | None |

New follow-ups from this pass, recorded in `docs/VOID2D.md` in the commit that records this pass:

| id | Follow-up | Owner |
|---|---|---|
| F13 | `scripts/gate.sh` does not apply the graduation rule to `conformance:webgl2-pixel-centre`: a listed scene that starts passing prints SKIP or PASS instead of failing | P4, in its carried list |
| F14 | P6's Lands and Exit did not name four P6 rows: the WebGL2 pixel-centre bias and the P2 rows `ui-box-color-effect`, `sdf-non-uniform-bound` and `style:line-length` | done: P6 Lands name all four, and P6 Exit requires no structural failure and every P6 row closed or re-owned |
| F15 | P4's section carried only F10 and F11 | done: P4 Lands carry F1-F4, F8, F9 and F13; P4 Exit carries F12 |
| F16 | Small record errors: GPUI.md's oversized row, fontstash still listed as today's text path, "100 ns" where the numbers give 140-180 ns per label, the wasm delta before the fixes, the `firstPaint` rows, and `removeChild` / `removeChildren` beside `remove()` in P5 | done |

P4 may assume a float shaped layout on stb_truetype with GPOS kerning; quarter-pixel pixel-exact
placement with a frame-fenced, page-reclaiming R8 atlas; per-codepoint fallback with cached misses;
the `Font` value with synthetic styles; decoration metrics from `post`/`OS/2`; and GPUI's gamma
table. It may not assume grapheme-level face selection, colour glyphs, a `present` at the pre-P3
level, or text that stays pixel-exact inside a filter at fractional DPI.

# P3.5 — Solidify before P4

P3.5 is not a roadmap phase. P3 shipped with follow-ups, and before P4 builds the editor surface
on it the human asked for three things to be made solid: numbers that can be trusted, a record
that checks itself, and MetaScript written to the 0.2.55 compiler rather than to 0.2.53's limits.
It takes F2, F9, F10 and F13 from P4's list. The brief is
`~/metascript/.wt/void2d-p35-solidify-prompt.md`; the model for the audit is REVIEWS-3D.md
"Audit before M13".

## Audit before P4 — `src/void2d` read against CODE-STYLE and the 0.2.55 compiler

**Verdict: no defect in the paths the gates exercise; one latent defect in how the display list
stores a view; the idiom debt fixed where it is internal, and sent to the human where an app
author would see it.** Read in the main session, line by line, from `05b4b9d`: all 6 188 lines of
`src/void2d/*.ms`. The C files were read where a finding crossed into them.

### Compiler workarounds, re-probed on msc 0.2.55

One small probe each, under `out/tmp/p35probes/` (gitignored), msc v0.2.55 BUILD `8cdd91c6`,
2026-09-25. The cards named here carry the result as a sighting.

| Workaround | Where void2d carried it | On 0.2.55 | What was done |
|---|---|---|---|
| The object cache ignores a `.c`'s headers | the gate's cache eviction; the worktree `CLAUDE.md` | Does not reproduce, for `@compile` and for a `.c` compiled through `import from "./x.h"` that includes a second header | Eviction kept until the card is pinned; the card has the re-probe |
| `msc test` exits 0 for a crashed test binary | the gate requires the `Tests N passed (N)` line | Still exits 0; `msc run` now exits non-zero | Kept; card `2026-09-23-crash-exit-status-lost` updated |
| A function cannot return a `Span` | `displayList.ms` exports its streams | Still refused, as a borrow of its source; CODE-STYLE §5 says it works | Kept; the comment states the rule (`4e4f6e9`) |
| A `Vec` parameter is a read-only copy | six hand-inlined growth loops | A `ref` `Vec` parameter pushes through | Finding 2 |
| `==` on a struct over 24 bytes fails; a struct parameter is copied per call | field-by-field compares; `drawUiInstance`'s 25 lanes | `==` works on a 32-byte struct, and a struct value parameter is emitted as `const T*` | Findings 1, 7, 8, 19; TESTING.md corrected (`75b286b`) |
| A union payload as an interface field fails in C | `node.ms`'s header comment | The probed shape builds and runs | Comment removed (`17ab4b4`); a union `Node2D` is P5's design question |
| Nothing calls `function main()` | `mainSokol2d.ms` blamed 0.2.53 | Unchanged, and CODE-STYLE §9 states it as the rule | Comment removed (`17ab4b4`); the gate's demo run pins it |
| A float literal widens `float32` arithmetic | typed `float32` locals in `textGamma.ms`, `effect.ms`, `graphics.ms` | Unchanged | Kept; design card `2026-09-20-float32-literal-widens` |
| No `BitSet`, no `distinct`, no generic `ref` | — | All three work. Two `distinct` values do arithmetic, a swapped one is a type error, and `-1 as T` parses as `-(1 as T)`: write `(-1) as T` | `distinct` adopted (finding 3); `BitSet` carried (finding 24) |
| No `ref` receiver | `ref` free functions | Still a parse error | Kept; card `2026-09-20-ref-receiver-not-an-extension` |
| `Math.min` / `Math.max` on `int32` return `float64` | no site | They return `int32` | Nothing to do |
| `msc check` ignores relative imports | no site | It resolves them and reports an error in the imported module | A correction to the work order's TRAPS |
| The same header from two directories compiles its `.c` twice | three comments in `draw.ms` | Builds and links | Comments corrected (`4e4f6e9`); the re-exports stay |
| An extension imported by name merges with a same-name local one | none: void2d imports no extension by name | Still wrong: the local type's `toString` runs the imported one | New card `2026-09-25-extension-imported-by-name-shadows-local` |
| `span[0]` passed to a header-imported pointer is a copy | none: void2d passes `arr[0]` on `Vec`s | Still wrong code | New card `2026-09-25-span-index-to-header-pointer-copies` |
| A `Vec` parameter copied into a local and grown corrupts the heap | none | Wider than the card said: `let b = vec` from any source emits no copy, and growing `b` leaves the source reading freed memory (`738` read where `7` was stored, or `0xC0000374`) | Second sighting on `2026-09-23-vec-param-copy-corrupts-heap`; void2d grows only fresh `Vec`s (read in the emitted C) |
| A partial literal assigned to an imported interface field loses its TypeInfo | PENDING `legacy:tests/layout.test.ms` | The card's repro passes | Card updated; the unpark waits on its pin |
| A struct literal may leave fields out, zeroed silently | review | Unchanged | A review rule |

The installed compiler changed twice during P3.5 (`8cdd91c6` → `2f306532` → `cf69e040`). The
first change turned void3d's `rendererCheck.ms` red: a `ref` parameter of a `this typeof T` static
extension had always landed on the next parameter, a silent copy that a new argument check
exposed. It was fixed in recompiler (`15af5b04`); void2d has no such parameter.

### Findings

| # | Layer | Finding | What was done |
|---|---|---|---|
| 1 | display list | The clip was 12 loose scalars and a 13-float save stack in `displayList.ms`, and 12 parallel `Vec` columns in `draw.ms`, compared field by field | `Clip` and `MaskClip` structs compared with `==` (`8724733`); T1 snapshots unchanged |
| 2 | display list | Six hand-inlined growth loops, because a `Vec` parameter was a read-only copy | One `growTo(ref stream: Vec<float32>, …)` (`6dbcff5`) |
| 3 | glyph layer | An atlas page index and a C page handle were both bare `int32`, and `firstGlyphPage()` returned a handle (F9c) | `GlyphPage` and `GlyphPageHandle` are `distinct` (`52224ff`). Control: an index where a handle is wanted is now `Argument type mismatch` |
| 4 | core | `if / else if` chains on `DrawKind` (`emitNode`, `dispose`), `Pipeline` and `ScaleMode` | Exhaustive `match` (`2d68987`) |
| 5 | glyph, font | Struct-first helpers `packKey`, `uvRect`, `sameFont`, `needsBold`, `needsItalic` (F9b) | Extensions (`a1409e2`) |
| 6 | font, label | Module data one layer owns, as `T[]` (F9d) | `Vec` (`ce84c13`) |
| 7 | draw, scene | Colours and transforms compared field by field | `==` (`d2754e8`) |
| 8 | label | The placement key was seven loose floats compared one by one | `PlacementKey` (`1599dd2`); the per-label check keeps its early exits rather than one `==` (`19f9f5b`) |
| 9 | draw | `useState`, `useSpriteState` and `useUiState` differed only in the pipeline | One `useRun` (`679b31c`) |
| 10 | glyph atlas | `placeOnPage` returned `[-1, -1]` and `reclaimPage` `-1` | `Result<…, AtlasError>` (`42b7de8`). `ensurePage` keeps its named sentinel, which crosses into C |
| 11 | core | 18 counted `while` loops | `for` (`36ce70b`); `while` stays where a loop converges or walks a list |
| 12 | frame path | `snapBoxEdges` returned a `Vec`, one heap array per Rect per frame, and `renderScaleGrid` built four `float32[]` per call. The ported stage saw copies, not allocations | A tuple and `float32[4]` (`9115c7b`): UI `present` 14.01 → 13.32 ms, eight clean pairs. The stage now fails a frame-path allocation and no longer mistakes a call that starts a line for a definition (`cb87dcb`) |
| 13 | draw | A layout mismatch between the emitter and `batcher.c` only logged, then drew with the wrong layout | It stops the renderer (`6ee454b`). Control: a planted mismatch stops the demo with the message |
| 14 | measure | F2: every layout call measured the face's heights and decoration with 96 glyph lookups, and `textWidth` / `textHeight` deep-copied the layout | Measured once per face (`fdaa291`), read without a copy (`e72f0d4`), gated as `text.measureGlyphLookups`: 80, was 176 (`f67cce1`) |
| 15 | style | 23 lines that P3 and P3.5 wrote past 100 columns (F9e) | Wrapped (`36de95a`, `d56e513`). The older ones stay with `tests/PENDING.md style:line-length`, P6's mechanical pass |
| 16 | harness | Comments still describing fontstash (F9f) | Corrected (`2f9ec9d`) |
| 17 | style | The gamma table was a heap `float32[]`; the box-style builders mutated a copied `const` | `float32[52]` (`07374d1`); spread (`8bb1841`) |
| 18 | display list | A sokol id is `(generation << 16) \| slot`, and the display list stores `view` as `float32` (`CMD_VIEW`, and `savedView` in `draw.ms`), exact only to 2^24. After the 256th reuse of one view slot the replay's `(uint32_t)cmd[CMD_VIEW]` names another slot. Latent: nothing here recycles a view that often | In "Known defects", `tests/PENDING.md display-list-view-id-float32` and P5's Lands: the id's two 16-bit halves in the two spare command floats, rejoined in the replay and the T1 printer, with a T1 test on a synthetic id past 2^24 |
| 19 | draw | `drawUiInstance` takes 25 positional lanes, and its stated reason is false on 0.2.55 | Comment corrected (`4e4f6e9`); a record struct in P5's Lands, whose persistent instance ranges rewrite the emission |
| 20 | render | `fmin4` / `fmax4` and `minFour` / `maxFour` duplicate each other, but keep different operands on a tie (`-0.0` against `0.0`) | Kept: merging them changes which zero a clip records, for no gain |
| 21 | render | The filter path allocates two arrays per filtered node per frame (`setEffect([])`, `colorMatrixAlphaOnly`) | In P5's Lands: a filtered node that did not change reuses its target |
| 22 | protocols | `breakReasonName` / `commandKindName` are the enums' text | Kept as functions: a `toString` extension on an enum makes `"" + e` a C compile error (CODE-STYLE §15). `TextLayout`'s lines and glyphs are already iterated as `Vec`s, so no `toItems` |
| 23 | metaprogramming | The UI instance's 108 bytes are packed field by field in `instance.ms` and in C, held together by a runtime layout check | In P5's Lands, which rewrite the record: one table generating both sides. Not built |
| 24 | flags | `Node2D`'s `visible`, `tileWrap` and four dirty booleans | In P5's Lands, which redefine dirtiness for retention; `visible` and `tileWrap` are h2d's app-facing properties and stay |
| 25 | API | The idiom changes an app author would see | Sent to the human on 2026-09-25: `addFont` / `resolveFont` as `Result` with a `FontId` (Neon's `window.ms:278` calls `addFont`); the BoxStyle builders as extensions without forwarding constructors; `textLayout()` on a non-Label failing loud. Face ids in `LaidGlyph`, `Tile.view` as a distinct type and `Node2D.payload` wait on the same decision and on P5 |
| 26 | compile-time | `@comptime` for constant tables | The gamma table is a fixed array (finding 17); the instance offsets are literals, not computed; no finding needs `when` or `-d:` yet |

**Confirmed, with the check named:**
- no refactor moved a pixel: D3D11 69 / 69 byte-identical at every gate of P3.5, and the bench counters unchanged apart from the new `text.measureGlyphLookups`;
- the frame path copies no array and builds no fresh one (the `allocation` stage, 51 functions, proven by a planted copy and a planted array literal; it does not see stream growth or allocation inside C);
- the record checks itself (the gate's "the record against the code", proven by five planted drifts), and a `conformance:*` row now fails the run when its scenes pass or a run is clean (F13, proven by three planted logs).

### Numbers

`present` on a quiet box, `scripts/bench-ab.sh`, eight pairs each. The first three rows had every
pair clean under the 40 % limit then in force (13-25 %); the last was taken under 25 %, with 7 UI
and 5 sprite pairs of 8 clean, and the P3 head against the P3.5 head got no clean UI pair in the
same window:

| A | B | UI | Sprites |
|---|---|---:|---:|
| P2 ship `2255d9f` | pre-P3 `8a473f3` | 13.43 → 13.37 ms | 2.54 → 2.47 ms |
| pre-P3 `8a473f3` | P3 head `05b4b9d` | 12.76 → 13.29 ms | 1.84 → 1.81 ms |
| `42b7de8` | no frame-path arrays `9115c7b` | 14.01 → 13.32 ms | 2.40 → 2.44 ms |
| pre-P3 `8a473f3` | P3.5 head `d56e513` | 13.54 → 13.05 ms | 2.61 → 2.59 ms |

Absolute numbers move by about 0.6 ms between windows ten minutes apart on this box, which is why
only the pairs compare. P3's 2.2× (VOID2D.md P3 "Measured") was load. One measure call costs 80
glyph lookups for 80 glyphs, where it cost 176. The final gate's web build is 744 307 B (WebGPU) and
649 510 B (WebGL2), against P3's 761 810 B and 667 012 B; the 17.5 KB went somewhere between msc
0.2.53 and 0.2.55 and P3.5's refactors, and nothing separated the two.

## P3.5 review

The diff is `05b4b9d..HEAD`. The defect pass was `/code-review high` in Claude Code, verified
finding by finding in the main session. The design pass was a fresh Claude subagent that had
written none of P3.5.

### Defect pass — `/code-review high`

Ten findings: eight confirmed and fixed, one plausible and fixed, one kept.

| Finding | Resolution |
|---|---|
| The record check wanted `N / N` from `table.ms` where the gate wanted `pass / total` from the run: with a pending D3D11 scene the row could satisfy neither | `8ef78b9`: the record check reads only the total; the run's line owns the pass count |
| The record parsers skipped a PENDING row whose id was not lower-case, and counted a commented-out golden row | `8ef78b9`: a row is recognised by its tier cell, and a golden row only when a line starts with it; T0 tests for both |
| The WebGL2 graduation block used bash's `<(…)` under `#!/bin/sh` | `4750f3e`: POSIX loops. The gate's older skip-line check still uses `<(…)`, from before P3.5 |
| An unreadable `golden webgl2` line made `$(( + ))` stop the gate with no FAIL and no summary | `4750f3e`: the claim is built by awk, or the gate fails naming the line. Control: a suffixed line fails loud |
| The allocation stage's PASS said the frame path "neither copies nor allocates", but it cannot see stream growth (`growTo`) or allocation inside C (`ensurePage`) | `f5fdd67`: it claims no array copy and no fresh array; the audit's "Confirmed" corrected |
| Comments over three lines in `gate.sh` and `bench-ab.sh` (the comment playbook) | `f5fdd67`, `a030751` |
| `bench-ab.sh` read fields by position, so a run that printed no number counted as a clean pair at 0 ms | `a030751`: the pair is BROKEN, left out and counted. Tested on a planted row |
| `placementCurrent` built the whole key, fractions included, for every label on every frame, where the old code exited early | `19f9f5b`: early exits restored; the key stays one struct for storing |
| The glyph-lookup counter was a signed `int` bumped on every lookup, undefined at overflow | `b66232e`: unsigned |
| Kept: the three text-metric fallbacks build an empty layout "to return 0" | `textHeight`'s fallback is one empty line's height, not 0, and what a non-Label should do is the human's question (audit finding 25) |

`sh scripts/gate.sh` was GREEN after them, at `b66232e`: 868 tests, D3D11 69 / 69, the bench
counters unchanged but for the new `text.measureGlyphLookups`.

### Design pass: **SEND BACK** — two defects in the record, none in the code

A fresh Claude subagent that had written none of P3.5 read the diff at `b66232e` against the
brief, the guardrails and the decision rule. It verified that no behaviour changed: struct `==`
compiles to field-by-field float compares, so `-0` and NaN compare as before; every `match`
covers the chain it replaced; `growTo` grows the stream in place; the atlas `Result` paths behave
as the sentinels did; a synthetic face may share the measured heights, which read outline boxes
only. It refused the step on two record defects, the P3-B3 class again.

| id | Finding | Resolution before re-review |
|---|---|---|
| P3.5-S1 | The audit carried #18, #19, #23 and #24 "to P5" and #21 "with the filter path", but P5's Lands, Closes and `tests/PENDING.md` named none of them, and #18, a latent defect, was not in "Known defects". The record check compares PENDING rows against Closes lines, so it could not see it | `0a68769`: #18 in "Known defects" and as `tests/PENDING.md display-list-view-id-float32`, owned by P5 and on its Closes line; #18, #19, #21, #23 and #24 as one P5 Lands bullet; the audit rows point there |
| P3.5-S2 | P4 "Measure" pointed at a P3.5-head number that did not exist. The only P3.5 number was `9115c7b`, before `e72f0d4`, `fdaa291` and `19f9f5b`; the refactors were never A/B'd against `05b4b9d`, and `19f9f5b` was a `perf` commit with no measurement | `31c68b1`: the P3.5 head against the pre-P3 control `8a473f3`, UI 13.54 → 13.05 ms over 7 clean pairs of 8, in P3 "Measured at P3 step 8" (bullet "The P3.5 head") and in "Numbers" above; P4 "Measure" points at it and takes its own pairs. The P3 head against the P3.5 head got no clean UI pair in the same window (samples 17-68 %), so P3.5's own delta, about −1 ms, is read across two windows, not from one pair |

### Follow-ups the design pass carried

| id | Follow-up | Owner |
|---|---|---|
| F-a | The record check passed a row owned by `P7` and missing from every Closes line: it read only P4-P6 | done, `416ee58`: the phases come from VOID2D.md's headings, and an owner that is neither a phase nor `compiler` or `human` fails. TESTING.md says a Closes line lists ids, not work (`0c2ea48`). Controls: a `P7` owner and a `robot` owner each fail the stage |
| F-b | The allocation stage could not see a struct's deep copy, which emits `<Type>…OmsCopy(`, not `ArrayCopy(`; `textWidth` and `textHeight`, where P3.5 removed exactly that copy, were on no list | done, `153f70e`: `OmsCopy(` in the pattern; `benchText` emits the measure path, and `textWidth`, `textHeight` and `shapedLabel` are held to no copy and to no `textLayout` call. Control: `textWidth` through `textLayout` again fails. The wider pattern found one more copy, `shapeLabel` returned a copy of the layout, which `shapeIfChanged` read and the tests dropped; the caller now reads the stored one (`3f2c3d6`). Not timed: a reshape runs only when a label's text or style changes, which the bench does not do in steady state. The list is still named rather than followed through calls; the seven per-frame helpers the reviewer found unlisted allocate nothing today |
| F-c | CODE-STYLE §14's "parameters are `Span<T>`": private `T[]` parameters remain in `sortByZ`, `effectMatrixSame`, `sameStrings`, `pushEffect`, `setEffect`, `polyArea2`, `isEar` and `triangulate` | P4, with F9 (`a3c918d`) |
| F-d | F9's half no app sees: `faceAtPath`, `bestFace`, `styled`, `loadFace` and `syntheticFace` still answer `-1` | P4, with F9 (`a3c918d`) |

The reviewer's notes, and what became of them:

- Audit #8 still said `PlacementKey` was "compared with `==`": corrected (`0a68769`).
- `dispose` ended in `_ => {}`, the one match where a new kind with a payload would leak in
  silence: it names every kind (`821f906`).
- `sceneViewMatrix`'s `Resize` arm could never run, because the function returns for `Resize`
  before the match: the arm returns, the early exit keeps only the missing design size
  (`9d8b139`), and a T0 test holds a `Resize` scene with a design size to the identity
  (`be3c150`).
- Two lines P3.5 wrote, and four in its new files, were over 100 columns: wrapped (`d56e513`);
  `style:line-length` re-measured at 246 lines (`a8593b6`).
- TESTING.md said "a `conformance:*` row" where the gate handles one named row, and did not say
  that a listed WebGL2 scene can get worse without bound: both written (`0c2ea48`).
- `bench-ab.sh`'s 40 % limit sat above the 25-33 % band P3's inflated numbers came from: 25 %,
  and T4 says interleaving protects the difference, not the absolute (`186aaa2`).
- `-1 as T` is a checker error with no card: now
  `~/metascript/.inbox/compiler/2026-09-25-unary-minus-looser-than-as.md`.
- For the human, not changed here: `draw.ms`'s layout checks stop the renderer with
  `unreachable`, which traps in release too, where LANG.md says "crashes in debug"; and CODE-STYLE
  §5 says arithmetic on a `distinct` crashes, which the audit found it does not.
- The allocation stage's awk range ends at the entry's column-0 `}` and does not read the
  `BeforeRet_` tail. Harmless today: no listed function lives there.

### The gate after the send-back

`sh scripts/gate.sh --web` was GREEN at `2d1fba9`, with 10 loud skips: 870 tests, D3D11 69 / 69
byte-identical, WebGL2 65 / 69 with the four listed structural failures (`prim/strokeRect`,
`prim/polygonBezier`, `prim/patterns`, `xform/scale`), the bench counters matching, the
allocation stage over 51 frame, 14 rebuild and 3 measure functions, and the record stage at 28
rows against 7 phases. The controls were re-run on the final stages: the record stage fails a
moved owner, a `P7` owner, a `robot` owner, a dropped Closes id and both drifted conformance rows;
the allocation stage fails a struct copy, an array literal and `textWidth` through `textLayout`.

The run before it went RED at the golden stage and nowhere else: deleting
`~/.metascript/cache/objects` failed with "Directory not empty" while another session's `msc`
wrote into it. TESTING.md said the gate evicted only this checkout's objects; it evicts the
whole machine-wide store, and now says so, with the race (`1cf6bf7`).

## P3.5 re-review: **SHIP WITH FOLLOW-UPS**

A second fresh Claude subagent, which had written none of P3.5 and had not sent it back, read
`b66232e..2dd062a` against the brief. It recomputed every median in "Numbers" from the A/B logs
and found each one right, and it found S1, S2, F-a and F-b resolved on disk. No behaviour changed
after the send-back: msc 0.2.55 rejects a non-exhaustive enum `match`, so `dispose` cannot miss a
new kind, and no golden or T1 snapshot changed across `05b4b9d..HEAD`. It would refuse nothing in
the code. It would refuse a land whose record still had its findings 1 and 2, which `96b60bd`
fixes.

| # | Finding | Resolution |
|---|---|---|
| 1 | P4 "Measure" pointed at P3 "Measured"'s last bullet; the P3.5-head number is the fourth | `96b60bd`: it names the bullet |
| 2 | P5 "Defects closed" did not name the view-id defect, though P5 closes it | `96b60bd` |
| 3 | `pendingRows` skips a PENDING row it cannot parse, in silence: a tier of `T2/T4`, an id with a space and a row without its date cell each stayed green. Nothing is skipped today | P4, in its carried list: such a line fails the gate and is named |
| 4 | The allocation stage reads only the functions it names: a private helper returning `labelTexts[i].layout`, called from `textWidth`, puts F2's copy back one call deeper and passes | P5, in its Lands: follow calls. TESTING.md's T4 row now states the stage's limits (`96b60bd`) |
| 5 | `shapeLabel`'s one production caller used the copy it returned; only tests dropped it. `3f2c3d6` has no number | `96b60bd`: described, and why it is not timed |
| 6 | The P3-against-P3.5 window's load was 17.3-67.8 %, not 20-68 % | `96b60bd` |
| 7 | The audit read 6 188 lines, not 6 182 | `96b60bd` |
| 8 | The installed msc became BUILD `8b4ed972` after the final gate, and no gate log names its compiler | P4, in its carried list. The land re-runs the gate after the rebase |
| 9 | The web build shrank by 17.5 KB since P3, recorded nowhere | `96b60bd`: in "Numbers", cause not separated |
| 10 | `style:line-length`'s 246 holds only under a UTF-8 locale; the C locale reads 248 | `96b60bd`: the command pins `LC_ALL=C.UTF-8` |

Also noted for P4's F9 pass: `cornerArc` (`graphics.ms`) takes a `Node2D` it never reads.

P4 may assume a record that checks its owners, its Closes lines and its conformance rows against
the code; a frame path whose named functions copy no array and build none; one glyph lookup per
glyph in a measure call; and a `present` at or below the pre-P3 control. It may not assume the
record check reads every PENDING line, the allocation stage sees through calls, or a gate log that
names its compiler.
