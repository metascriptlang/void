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
