# Testing void — tiers, oracles, goldens and the gate (2026-09-20)

What a void change has to prove before it is committed, and who can re-run the proof.

**The problem this doc closed.** Before P0, `msc test src/test/index.ms` was the only thing in this repo that anyone else could run — 425 tests including std's prelude. Everything the last sessions used to judge their work lived in `out/tmp/`, which `.gitignore:5` excludes: the D3D11 readback harness (`out/tmp/capture/capture.{c,h}`, `demo2dCapture.ms`, `cmp.py`, twelve 800×600 `base_*.ppm` goldens) and the two seven-line entry points that made `src/examples/bench2d.ms` runnable. The baseline in [VOID2D.md](VOID2D.md) and the "byte-identical readback" acceptance clauses in [VOID3D.md](VOID3D.md) were produced by files no one could check out, and there was no gate script anywhere in the repo.

**As of P0 (2026-09-20) that is fixed**: `tests/capture/`, `tests/golden/`, `tests/bench/`, `tests/PENDING.md`, `scripts/gate.sh`, `scripts/golden.sh` and `scripts/web-liveness.sh` are committed, and `sh scripts/gate.sh` runs the whole thing in about 35 seconds. What each tier actually covers today is at the end of this doc.

**The model.** Taken from `~/projects/rexa` (`AGENTS.md:132-147`, the Testing block of "Engineering workflow"), which runs it against Neovim for vim and pyte for the terminal: an oracle instead of hand-written expectations wherever a reference implementation exists; cases as data rows with a regenerated, committed snapshot, so CI never needs the oracle; a `PENDING` list of known divergences with reasons, where **a listed case that starts passing fails the run** (`crates/rexa-editor/tests/vim_spec.rs:877-899`); pass rate as the correctness metric with an absolute build-breaking condition; distrust the harness before the engine; a hand-written suite for what the oracle cannot express; a regression test in the same change as the bug; green before every commit.

What follows is that model translated to a renderer, where "reference implementation" is sometimes a maths definition, sometimes a font library, and sometimes another GPU backend.

## The tiers

| Tier | What | GPU | Where it runs | Speed |
|---|---|---|---|---|
| **T0 pure** | Maths, layout, packing, colour, bit layouts | no | everywhere, `msc test` | seconds |
| **T1 display list** | The recorded command and instance streams | no | everywhere, `msc test` | seconds |
| **T2 golden images** | Captured pixels against committed PNGs | yes | per backend | ~a minute |
| **T3 oracles** | Ground truth from outside void | no (mostly) | wherever the tool is | seconds, regen is manual |
| **T4 budget** | Deterministic counters and wasm size; times reported | yes | per backend | ~a minute |
| **T5 judgement** | What no harness can decide | — | a human | — |

The split that matters: **T0, T1 and T3 are the tiers that run in every gate on every machine.** T2 and T4 need a GPU and, for three of the five backends, a machine that is not this one. So everything that can be pushed down into T1 should be — the display list is the lever that makes most of the frame assertable with no GPU at all.

## T0 — pure tests

Already exists. `src/test/index.ms` is eleven imports; `msc test` runs the import graph, and that is the whole registration mechanism. Tests are top-level `test "name" { assert expr; }` (`~/metascript/docs/CODE-STYLE.md:377-390`). `src/test/helpers.ms` is the only shared helper: `approx` (absolute 0.005), `approxRel`, `meshTriArea`, `meshHasVert`/`meshHasVertUV`.

Two constraints on everything below come from the language, not from taste:

- **`assert` takes a bare boolean and carries no message.** `expect` does not exist. A snapshot or table comparator must `console.log` the differing rows itself before asserting the difference count is zero, or a failure reports only that an assert failed.
- **`==` on a struct over 24 bytes fails to compile on msc 0.2.53** (`src/test/pipelineCheck.ms:24-35` works around it with a field-by-field `sameState`). Comparators over instance structs are written out by field, or over their packed bytes.

Data-driven tables are already the local idiom — `blendModes(): Vec<BlendMode>` looped over in `pipelineCheck.ms:123`, the fixture builders at `rendererCheck.ms:34-89`. Keep that; there is no framework to add.

What T0 gains through the roadmap: the snapping rules as arithmetic, wrap and truncation boundaries over a shaped line, the atlas packer, complementary rounding, Oklab and sRGB interpolation, the gamma/contrast table, instance bit packing, the display-list growth policy.

`tests/layout.test.ms` at the repo root is a separate, older mechanism — a standalone binary with its own `expectEq(label, actual, expected)` runner (`tests/layout.test.ms:13-21`) that does not build on msc 0.2.53. It is not part of this model; either port its cases into `src/test/` or delete it.

## T1 — the display list is assertable with no GPU

**Created at P1.** `tests/displayList/snapshot.ms`, reached from `src/test/index.ms`, with the snapshots beside it as `tests/displayList/<scene>.txt`.

**What it costs, stated rather than glossed.** The tier is GPU-free because the walk records and stops - `finishRecording` closes the open run and the replay is never called. That works because `void2dWhiteView()` on an unset batcher returns 0 and `void2dFrameBegin` only resets statics, so nothing on the recording path calls sokol. The price is that a scene needing a real resource cannot be in a snapshot: a filter allocates a render target and text needs a fontstash context. Target ordering and nesting are therefore asserted in `src/void2d/displayList.ms` directly - where they need no scene at all - and the golden scenes are **not** shared with this tier, which is a divergence from the plan below.

It is the largest single win in this doc.

**What it buys.** Every conclusion in VOID2D.md "Frame shape" and "Order and batching" is a statement about a POD stream, not about pixels. Recorded as data, the stream can be asserted in the existing `msc test` tier, in seconds, on every platform, with no GPU, no capture and no golden. It catches exactly what a golden image cannot see — identical pixels produced with ten times the draw calls or ten times the uploaded bytes — and it is the only tier that can assert a **negative**: that nothing was uploaded, that no pass was opened, that a culled subtree contributed no instances.

**What it should assert.**

- **Order.** Painter's order is preserved; a target's command list appears before its consumer's, and no pass is nested at replay (sokol asserts `!in_pass`; Makepad records the bug it had when it got this wrong, MAKEPAD.md:99).
- **Batching, with reasons.** Each command carries why it broke the previous batch (atlas, pipeline, blend, custom shader, clip kind). The snapshot then says `break: atlas`, not just a number, so a regression names its own cause. VOID2D.md's claim that a UI subtree in tree order is about one draw call becomes an assertion on the bench scene.
- **Instances.** Count per mode, total bytes, the growth policy at its boundary — `max(2×, pow2)`, no shrink, and the dropped frame with an error past the cap (GPUI.md:63).
- **Culling.** A node fully outside the *active clip* — not merely outside the viewport — emits nothing. A scrolled list is the case that matters.
- **Snapping as numbers.** The instance a fractional box produces at DPI 1.0, 1.25 and 1.5: independently rounded edges, `snap_stroke` 0→0 else ≥ 1 device pixel, complementary rounding of a fractional split. These are arithmetic, and checking them by eye in a capture is how they stay wrong.
- **Idempotence.** Recording the same unchanged tree twice produces a byte-identical stream. This is the precondition for persistent instance ranges (P5); without it, "a node that did not change has byte-identical instance data" is a hope.
- **Dirty behaviour.** After P5: mutating one node produces exactly one dirty byte range of a known size; a caret blink and a hover produce zero tree walks and zero structural change.
- **Glyph placement.** After P3: the four x-variants and the whole-pixel baseline appear in the instance data as exact numbers.

**Form.** One line per command and per instance, fixed-precision floats, committed as `tests/displayList/<scene>.txt`, regenerated with `VOID_SNAPSHOT=1` on the same run that compares — rexa's shape (`vim_spec.rs:855-857`), so regen and compare never drift apart. The scenes are the golden scenes below, so one table drives both tiers.

## T2 — golden images

**Out of `out/tmp/`.** Proposed layout, all committed:

```
tests/capture/capture.{c,h}       one readback signature, a backend behind it
tests/golden/scenes.ms            the scene table: name, builder, size, dpi, frames
tests/golden/runner.ms            entry: build, render, capture, write
tests/golden/compare.ms           diff, tolerance policy, report
tests/golden/d3d11/<scene>.png    the goldens
```

`out/tmp/capture/capture.c` moves in unchanged: it reads the resolved D3D11 swapchain through sokol's native-handle getters (`sg_d3d11_device()`, `sapp_d3d11_get_swap_chain()`), clones the backbuffer desc as `D3D11_USAGE_STAGING | D3D11_CPU_ACCESS_READ`, `CopyResource`, `Map`. sokol has no readback API and async `read-buffer`/`read-image` is only announced (docs/SOKOL.md:34), so this stays hand-written per backend for now.

**PNG, not PPM.** A committed 800×600 `P6` is 1.44 MB and `out/tmp/capture` holds twelve of them. The scenes below are 256²–512×256; PNG at that size is 3–15 KB for flat UI, so the whole suite fits in well under a megabyte. `deps/stb/stb_image_write.h` is already fetched by `setup.sh`, so the writer is one include and the gate stays on one toolchain. `cmp.py`'s hand-rolled PNG writer becomes a dev tool for diff masks, not a gate dependency.

**The scenes.** Small, static, frame-indexed — never time-indexed. Grouped so a change
regenerates only its group. The **from** column is the phase whose renderer can produce the
scene: rows marked later than the phase you are in are entries in `tests/PENDING.md`
(`golden-missing:<scene>`), and the phase that lands the feature adds the row to
`tests/golden/table.ms` and deletes the entry in the same commit.

| Group | from | Scenes |
|---|---|---|
| `harness/` | P0 | solid (hand-computed) · mustFail (deliberately wrong golden) |
| `prim/` | P0 | roundedRect · strokeRect · ellipsePieRing · polygonBezier · gradientLinear · gradientRadial |
| `prim/` | P2 | per-corner radii · per-side borders · dashed border · drop shadow · inset shadow · shadow+fill+border in one instance · gradient Oklab · multi-stop · dither band · slash and checkerboard |
| `xform/` | P0 | rotate (0 / 7° / 37° / 45°) · scale (0.5 / 1 / 2) · pivot · nonUniform |
| `xform/` | P2 | pivot from `Tile.dx/dy` |
| `snap/` | P0 | hairline at DPI 1.0 / 1.25 / 1.5 · fractionalSplit of 7 px · fractionalOrigin |
| `snap/` | P2 | zero border stays zero |
| `clip/` | P0 | nestedMasks · rotatedMask · scrolledList |
| `clip/` | P5 | mask + scroll offset |
| `text/` | P0 | a code line at 13 px, DPI 1.0 / 1.25 / 1.5 · wrapped · multilineAlign |
| `text/` | P3 | mixed Latin + CJK fallback |
| `text/` | P4 | decorations (underline, strikethrough, wavy) · caret and selection |
| `text/` | P6 | a ligature line · a colour-emoji line |
| `image/` | P0 | nearestLinear · subFlip · colorPipeline (colorMatrix, colorAdd, colorKey, Add blend) · scaleGrid |
| `image/` | P1 | tileWrap (clamp beside repeat, u1 = 3) · sceneSmooth (`Smooth.Inherit` against a scene default of nearest, beside an explicit `Smooth.On`) |
| `image/` | P2 | `ObjectFit` variants · `corner_radii` on an image · the `grayscale` image mode |
| `filter/` | P1 | blur · glow · dropShadow · groupOpacity — **built but not capturable at P0**, see below |
| `regress/` | P0 | nodeCap · dpiTruncation · samplerRepeat · vertexCap |
| `regress/` | P1 | atlasFull · filterNestedPass — **not capturable at P0**, see below |
| `demo/` | P0 | `src/examples/renderer2d.ms` at 800×600, animation steps 1 / 30 / 90 / 200 |

Thirty-seven rows are live. The demo is the one big integration capture, because it is what
the last three sessions compared.

**Two groups P0 could not capture, and why.** Both are findings, not omissions:

- **Every `filter/` row, and `regress/filterNestedPass`.** `drawFiltered`
  (`render.ms:216-283`) opens a render-target pass while the swapchain pass is open. A
  debug build trips sokol's `Assertion failed: !_sg.cur_pass.valid` (`sokol_gfx.h:27214`)
  and the process dies; a release build presents a frame that is nothing but the clear
  colour — the siblings drawn *before* and *after* the filtered node disappear with it.
  The path has never had a caller: no example and no test sets `Node2D.filter`
  (`src/test/nodeCheck.ms` only builds the `Filter` structs). The builders are written and
  sit in `tests/golden/scenes.ms`; P1 adds the rows.
- **`regress/atlasFull`.** Once the 512×512 fontstash atlas fills, *which* glyphs survive
  varies between runs of the same binary: three distinct outputs in ten runs, worst pair
  28 740 of 80 000 pixels (35.9%) at max delta 207. A golden with a 36% budget asserts
  nothing, so the row is a `tests/PENDING.md` entry with those numbers until P1 handles
  `FONS_ATLAS_FULL`. "Atlas-full drops glyphs silently" understates it: it drops a
  *different* set of glyphs each run.

**How a capture is taken.** `tests/golden/runner.ms`, one scene per process, driven by
`scripts/golden.sh`:

- **One scene per process**, so each capture starts from the same GPU-resource and atlas
  state; a scene can neither inherit pooled targets nor hide a leak behind another scene.
- **`sample_count` 1**. 4× MSAA is on only for the sokol_app entry (`bridgeWin.c` `voidRun`) and off
  on iOS, Android and the embed bridges, so a golden taken with it could never be the one
  golden set every backend is compared against. It is also not reproducible: at
  `sample_count` 4 the demo's D3D11 resolve differs by one or two pixels between runs of
  the same binary, and at 1 it is byte-identical. That is what the "frame 90 moves" note in
  earlier sessions was — an MSAA resolve artifact, not a renderer property.
- **`high_dpi` off**, so the framebuffer is exactly the size the table asks for and
  `voidDpiScale()` is 1.0 whatever the host display reports. A scene's DPI comes from the
  table, through `Scene.presentAt`.
- **A `--release` build.** sokol's validation layer, which a debug build links, aborts the
  process on two of the defects this suite exists to record (`tests/PENDING.md`
  `debug-abort:*`). A golden records what the renderer draws; the validation layer is a
  separate check.
- **Three draws**: one to warm up — the first draw of a Label rasterizes its glyphs — then
  two into separate capture slots, which must be identical before either is written out.
- **Counters before pixels.** The table-order vectors beside `sceneRows` pin draw calls and
  live pooled render targets for every row. A mismatch fails before the PNG is written, so
  identical pixels cannot hide multiplied draws or a target leak.
- **RGB, not RGBA.** The swapchain is opaque, so its alpha carries no information about what
  was drawn; storing it would cost about a quarter of the suite and would add a
  cross-backend difference that means nothing. Alpha inside the frame is still tested — it
  is what blending turned into colour.

**Size, measured in bytes rather than `du` blocks.** The 67 D3D11 goldens total
**1 328 179 B**: **683 201 B** for the 63 harness/UI scenes and **644 978 B** for the four
800×600 demo frames. The suite passed the original sub-megabyte estimate at P2 because 30
scenes were added; the integration captures still account for nearly half. The lever, if this
becomes material, remains the demo frames.

**Tolerance: byte-identical is the default.** All **69** live rows are byte-identical to
their goldens, between two draws in one process and between full suite runs in separate
processes. `tests/PENDING.md` carries **zero** image budgets. A tolerance is not a property
of this machine; it is a property of a scene, and a scene that needs one is a finding.

The rule:

- The comparator always reports `N px differ, max delta M, bbox` — `cmp.py`'s line, kept.
- The gate fails on any `N > 0` unless the scene has a `PENDING` entry carrying a budget (`maxPixels`, `maxDelta`) and a reason.
- A pending scene that comes back byte-identical **fails**, and the entry must be deleted — rexa's graduation rule (`vim_spec.rs:877-886`), applied to images.
- A scene in the table with no golden is an error, not a skip (rexa's `missing` assert, `vim_spec.rs:892-895`).

**Regeneration.** `sh scripts/golden.sh --update [scene…]`, never automatic. It refuses to
update if the capture step failed, and it never regenerates `harness/mustFail`, whose golden
is deliberately wrong. A normal run writes into `out/golden/` and never touches
`tests/golden/`, so a gate can never quietly rewrite what it is checking against. A golden changes only inside a commit that says why, and the PNG diff is the review artifact. A golden records what the renderer *does*, not what it should do: P0 generates them from today's renderer, defects and all, and each later phase regenerates the group it is supposed to move — which is how the phase proves it moved nothing else.

**Determinism preconditions.** Fixed DPI per scene, from the table; animation step index,
never wall clock; `sample_count` 1 and `high_dpi` off; the font bytes committed
(`assets/font.ttf`, sha256 `40d692fc…`); a fixed clear colour with alpha written; and the
output path built from the scene name rather than from an environment variable that could
default into a golden path, as the old scratch `capture.c:32-34` did.

## T3 — oracles

Where ground truth can come from outside void, it should, because a hand-written expectation is only ever as good as the session that wrote it.

| Domain | Oracle | Committed form | Verdict |
|---|---|---|---|
| Shaping: glyph ids, clusters, advances, offsets, OpenType features | **HarfBuzz** (`hb-shape --output-format=json`) over (font, size, text, features) rows | `tests/oracle/shape.json` | **Subset wired at P3 step 7**: 10 rows over Inter and the Noto Sans SC subset, uharfbuzz 0.56.2 / HarfBuzz 14.5.0 with every GSUB feature off and `kern` on, glyph ids and pen x at size = unitsPerEm: **268 / 268 agree**. Full version at P6 with the shaper |
| Font metrics: `unitsPerEm`, ascent/descent/lineGap, underline and strikethrough position and thickness, broken-table fallbacks (GHOSTTY.md:62) | **fontTools**, reading `head`/`hhea`/`OS_2`/`post` directly | `tests/oracle/metrics.json` | **Wired at P3 step 7**: fontTools 4.65.0 reads the raw tables and the generator re-implements Ghostty's decoration and height fallbacks on its own, over Inter, the Noto subset and the two broken-table fixtures — 14 values per font, **56 / 56 agree**. It covers a GPUI weakness (GPUI ignores the font's underline metric, GPUI.md:54) |
| Grapheme clusters, line-break opportunities | **The Unicode UCD conformance files** `GraphemeBreakTest.txt`, `LineBreakTest.txt` | vendored under `tests/oracle/ucd/` with their version | **Wire it** at P4. Ground truth from the standard, so there is no second implementation to distrust |
| Analytic coverage of the SDF primitives | **A CPU reference**: exact rounded-rect geometry supersampled 16×16 per device pixel, and a numerical Gaussian integral for the `erf` shadow | `tests/oracle/coverage.ms`, `tests/oracle/captureCheck.ms` | **Wired at P2 in T0 and against captures.** The T0 controls reject `smoothstep` by 0.09375 and a blur one fifth wrong; the accepted arithmetic measures 0 on a straight edge and 0.0078 on the tested shadow. The capture check independently judges the committed or freshly captured shader output: rotated AA measures 0.0502 against 0.06, and the shadow 0.0251 against 0.035. |
| h2d semantics: `getBounds`, `localToGlobal`/`globalToLocal`, mask intersection, scale modes, text metrics | **Heaps compiled to JS**, which SCENE-SCALE.md:204 records as already runnable here | `tests/oracle/h2d.json` | **Wire it, second priority.** It is the only mechanical check that "void2d stays h2d in interface and semantics" (VOID2D.md "The rule") is still true. Its PENDING list is already written: the deliberate divergences in HEAPS.md "The h2d contract" and "Do not copy from h2d" — four-corner mask AABB, `ScaleMode.Zoom`/`AutoZoom`, `lineSpacing` units, the looser `colorKey` threshold |
| Oklab / sRGB interpolation, the gamma/contrast table | the published matrices; GPUI's 13-row `gamma_ratios` (`gpui/src/platform.rs:1344-1378`) is itself the source constant | — | **T0, not an oracle.** Our table equals theirs, or it does not |
| Glyph rasterization | FreeType, unhinted, same size and offset | — | **Not ground truth.** void2d deliberately does not match FreeType: stb_truetype in the pixel-exact regime with its own four x-variants. Usable as a shape smoke check with a loose coverage bound — is the outline right? — and never as a gate on pixels. Say so rather than implying otherwise |
| GPUI / Zed parity | a Zed screenshot | — | **Manual, and not a gate.** See T5 |

**Regeneration and CI.** Same shape as rexa: the snapshot is committed and the gate never needs the tool (`AGENTS.md:135-136`). The font oracles regenerate with `python tests/oracle/fonts.py regen` (fontTools and uharfbuzz from pip) rather than inside the test, because the tool is Python and the test is MetaScript; `src/test/fontOracleCheck.ms` compares and prints the pass count the gate reads. A case row is data with no expected output. Divergences go to PENDING with a reason, and the pass rate against each oracle is printed.

The interesting number here is the UAX #14 one. void2d's wrap rule breaks at U+0020 only since P3; GPUI's rule — after a space, or at any non-word char (GPUI.md:49) — is P4's, and neither is UAX #14, so most `LineBreakTest.txt` rows will land in PENDING under one shared reason. That is the honest use of a pass rate: it says how far the cheap rule is from the standard, and the number is the argument for or against replacing it, instead of nobody knowing.

## T4 — budget

`src/examples/bench2d.ms` is committed (`168cea9`); what is missing is the two seven-line entries that make it runnable, `out/tmp/bench/bench{Ui,Sprites}.ms`. Commit them as `tests/bench/bench{Ui,Sprites}.ms` and the whole perf story becomes reproducible.

**Rows, not prose.** `bench2d.ms:63` prints ``present ${presentMs / 120} ms, ${drawCallCount()} draws``. Emit one machine-readable row per metric instead — `ui.present.ms`, `ui.draws`, `ui.labelsDrawn`, `ui.instances`, `ui.uploadBytes`, `ui.buffersAlive`, `sprites.*` — and commit `tests/bench/baseline.json`.

**What gates and what only reports.**

- **Gates, hard, against the committed baseline:** draw calls, instances, uploaded bytes, GPU buffers/images/pipelines alive, glyph rasterizations per frame, atlas pages and bytes, and wasm size per backend and per compile-time module. All of these are deterministic for a given build.
- **Reports, with a warn threshold, and never fails a commit:** milliseconds. SCENE-SCALE.md:197 records its own numbers being taken with the machine at load average 14–17; a wall-clock gate on a shared developer box produces flakes and then gets disabled, which is worse than a number nobody gates.

Most of the gating half is assertable with no GPU at all, in T1. That is the point of putting the display list first.

**wasm.** `scripts/build-web.sh` already builds both backends; the gate adds a size row per backend and per module against a committed budget, which is how guardrail 6 ("text is where the weight goes, so it is modular") stops being an intention.

## T5 — judgement

What stays with a human, stated so nobody builds a harness for it:

- **The Zed comparison.** There is no license-clean way to commit Zed's output, and a pixel comparison would be meaningless anyway — different font, different shaper, different snapping. What it needs is a protocol, not a harness: same font file, same px size, same DPI, same text, same foreground and background, screenshot cropped to the same box, at 1× and 1.5×. The verdict is written into VOID2D.md as a sentence; *our* two captures are committed as goldens and Zed's are not. Judged on three things: stem darkness, whether stems land on the pixel grid, and advance drift over a long line. It is evidence for a decision, not a pass/fail.
- Whether scrolling and caret motion feel smooth on a real device.
- The first run of anything on the Android and iOS devices.

## PENDING

One file, `tests/PENDING.md`, read by the harnesses. An entry is `id · tier · reason · the phase that removes it · date`, and for an image scene also its `maxPixels` / `maxDelta` budget.

The rule is rexa's, unchanged: **a listed case that starts passing fails the run.** That is what keeps the list from going stale, and it is why the list can be seeded aggressively. Three sources seed it:

1. Every line of [VOID2D.md](VOID2D.md) "Known defects" — so each defect is a listed failing case before it is a fixed defect, and the phase that fixes it deletes its entry in the same commit.
2. HEAPS.md's divergence lists, against the h2d oracle.
3. Every backend with no readback yet, and every scene that a backend cannot match (guardrail 9, below).

Pass rate is printed per tier and per backend and is the correctness metric. The build-breaking condition is absolute, as in rexa: zero unlisted failures, zero graduated entries, zero missing snapshots.

## Distrust the harness before the engine

Concrete mechanisms, because the phrase on its own does nothing:

- **A computed scene, not a captured one.** One golden whose expected pixels are written by hand — clear to a known colour, one solid rect at a known position — so that a comparator that passes everything, a readback that returns zeros, and a channel-order bug all fail loudly. `capture.c:40` swizzles BGRA→RGB by hand today and nothing checks it.
- **A scene that must fail.** One case whose golden is deliberately wrong, asserted to be *reported* as a failure. It proves the comparator can fail at all.
- **Determinism before comparison.** Every golden run renders each scene twice in one process and requires the two captures to be identical before either is compared to its golden. A flaky scene then surfaces as a harness finding, not as a renderer finding — which is exactly what frame 90 is today.
- **The verdict decision is itself an input-driven test.** Whether a scene's log means "captured" is one function, `verdictOk` in `scripts/golden.sh`, and `sh scripts/golden.sh --self-check` runs it against six fixed blocks: a lone `CAPTURED`, an empty block, a lone `FAIL`, a lone `SKIP`, and `CAPTURED` followed by each of the other two. The gate runs it **before** the suite it gates, and without a build or a GPU, so it runs under `--quick` too. It exists because the decision used to be `case "$verdict" in CAPTURED*)` over grep output that can hold several lines - and a shell glob's `*` spans newlines, so a scene that printed `CAPTURED` and then `FAIL` was counted captured, and `--update` would have taken its output as the golden. The self-check was written first and watched fail on exactly those two inputs before the function was changed.
- **A run that captured nothing is a failure, at three levels.** `capture()` used to return success whenever its loop body never executed. Now the scene table is checked for content before the loop (`tableUsable`, also in `--self-check`), and a filter that matched no scene fails by name. Measured before the fix: `sh scripts/golden.sh --capture zzz/nothing` exited 0 having printed nothing at all, which is what a mistyped scene name looks like. Downstream did catch the empty-table case - `--update` died on `cp: cannot stat` with every golden intact and the comparator reported all 44 missing - but a function that reports success for doing nothing is wrong at its own boundary.
- **Capture shape checks.** Assert the readback's width, height and row pitch, and that the image is not uniformly the clear colour — the "captured before the draw" bug.
- **Input pinning.** Font bytes hashed; DPI fixed per scene; frame index, not wall clock; `CAPTURE_PREFIX` required.
- **Cross-checks between our own tables**, rexa's `the_command_table_agrees_with_the_parser`
  (`crates/rexa-editor/src/vim/parser.rs:667`) in renderer form: the instance layout the
  shader declares agrees with the one the emitter writes; every shader `mode` is reachable
  from an emitter; production T1 scenes reach every `BreakReason` including view, effect and
  pipeline, while a target bracket reaches barrier; every command kind has a batch-break rule.
- **The build trap is part of the gate.** `msc build` answers "Up to date" after a header that a compiled `.c` includes has changed, and the global object cache is keyed on the `.c` and not its includes — `--force` does not bypass it (`~/metascript/.inbox/compiler/2026-09-20-object-cache-ignores-headers.md`). Every shader regeneration hits this. The gate's first step deletes the output binary, `out/debug/.cache` and this checkout's objects under `~/.metascript/cache/objects`. A gate that silently tests the previous binary is worse than no gate.

## The gate

`scripts/gate.sh`, the first one this repo has had. Each step prints PASS, FAIL or SKIP
**with a reason**; a SKIP is loud and counted, and nothing may report PASS for a backend it
did not run — the conformance line for a backend is the comparator's own output, never a
number typed into the script.

1. Evict the caches (above): the output binaries, `out/{debug,release}/.cache`, and this
   checkout's objects under `~/.metascript/cache/objects`.
2. `msc test src/test/index.ms` — T0, and T1 once it exists.
3. The demo entry builds.
4. `scripts/golden.sh`: build the runner `--release`, render every scene in its own process,
   twice, compare the two, gate per-scene counters, write the PNG, then
   `tests/golden/compare.ms` judges all **69** against `tests/golden/d3d11/` and prints
   `N px differ, max delta M, bbox` and a pass rate.
5. The three coverage oracles and the two font oracles, plus two named SKIPs for oracles not wired yet.
6. `tests/bench/check.ms` — counters gated against `tests/bench/baseline.json`, milliseconds
   reported with a warn threshold. Plus a SKIP for the wasm budget, which P6 owns.
7. Guardrail 9: the D3D11 conformance line, then one named SKIP per backend that has no
   readback. With `--web`, also `scripts/build-web.sh` and `scripts/web-liveness.sh`.
8. The tier table, the PENDING count, and the SKIP and FAIL totals.

Measured 2026-09-20: **GATE GREEN, 13 loud skips, about 40 seconds** on this box, starting
from a tree with no `out/` directory at all.
`--quick` skips the golden suite; `--web` adds the two web builds and the headless-Chrome
liveness check.

Green before every commit, as in rexa (`AGENTS.md:301-302`). A bug gets its regression case
in the same change as the fix.

## Guardrail 9 — how "same pixels on every platform" is actually checked

**Current status, 2026-09-24 (P3 review): two backends of seven measured, and both numbers are printed. P3's exit asked for five; GLES3 desktop and WebGPU are P6's, Metal and Android wait on the human's hardware.**

| Backend | Conformance | Runs |
|---|---|---|
| D3D11 | **69 / 69 scenes byte-identical** | every full gate, this box |
| GLES3 desktop | not run — the `glReadPixels` path now runs under WebGL2, but no desktop GL build exists: `src/sokol/sokolWin.c` is D3D11 only and the shaders carry no `glsl430`. P6 | SKIP |
| Metal macOS | no readback; the Mac is the human's | SKIP |
| Metal iOS | no readback; the first device run is T5, on the human's device | SKIP |
| GLES3 Android | shares the `glReadPixels` path; needs the human's device | SKIP |
| WebGPU | no readback in the wasm build, and headless Chrome has no adapter here, so the run is headed. P6 | SKIP |
| WebGL2 | **65 / 69**: 45 byte-identical, 20 within the cross-backend bound, 4 structural failures (`tests/PENDING.md conformance:webgl2-pixel-centre`); all seven `text/` scenes byte-identical. It runs through ANGLE on D3D11 on the same GPU (the script prints the `RENDERER` line), so it proves the GLSL ES path and GL's conventions, not a second driver | `sh scripts/golden-web.sh`, and the gate with `--web`; headless Chrome on this box |

So guardrail 9 is a number now, and the number is **2 of 7 surfaces measured**. The WebGL2 path is the golden runner itself compiled with `--os=emcc`: `tests/golden/web/runner.html` passes the scene in the query, `tests/capture/capture.c` reads the frame with `glReadPixels` into the in-memory file system and sets `window.voidDone`, and `scripts/webGolden.mjs` drives headless Chrome over the DevTools protocol (node's own `WebSocket`) and copies each PNG out; `tests/golden/compare.ms` judges it against the D3D11 goldens with `VOID_CONFORM=webgl2`. Its first run found a real cross-backend bug, not a tolerance: the Bayer dither was indexed by `gl_FragCoord`, whose origin is bottom-left on GL, so the 4x4 pattern flipped and every dithered pixel moved by up to 5 levels (gradients, `prim/ditherBand`, all four demo frames). The mesh pipeline now carries the fragment's device pixel as a varying and D3D11 stayed byte-identical. The first run also taught one harness lesson: `golden-web.sh` reused a stale `goldenCompare.exe`, which compared the D3D11 captures with themselves and printed 100 %; the script now always rebuilds the comparator. What exists
for the web today is liveness, not conformance: `scripts/web-liveness.sh` loads the built
demo in headless Chrome and checks that the canvas is not blank. Measured 2026-09-20:
**WebGL2 draws the demo; WebGPU builds and runs but headless Chrome hands it no adapter**
(both `--use-angle=swiftshader` and the real adapter give a black canvas), so WebGPU
liveness is unproven headless and is reported as a SKIP, not a pass.

**The design: one golden set, authored on D3D11; five backends compared against it.** Not five golden sets — five golden sets would record five different renderers and prove exactly nothing. The output is a per-backend conformance report: scenes identical, scenes within a stated bound, scenes failing, and a pass rate. That report *is* guardrail 9, and it belongs in VOID2D.md as a number that moves per phase.

What each readback costs:

| Backend | Mechanism | Runs on | Effort |
|---|---|---|---|
| D3D11 | staging texture + `CopyResource` + `Map` | this Windows box | exists; needs moving into the repo |
| GL / GLES3 | `glReadPixels` | this box (desktop GL), the Android device | ~30 lines, and it is shared with WebGL2 |
| Metal | blit to a shared `MTLBuffer`, or `MTLTexture.getBytes` | the Mac, the iOS device | ~50 lines |
| WebGPU | `copyTextureToBuffer` + `mapAsync`; `-sASYNCIFY` is already on for the emdawnwebgpu build (`src/sokol/sokolWeb.c`) | headless Chrome on this box | ~60 lines plus a JS hand-off |
| WebGL2 | the GLES3 path | headless Chrome on this box | shared |

**What browser conformance would take**, written down rather than attempted at P0, because
the missing piece is the readback and not the driver:

1. A wasm-side capture: `glReadPixels` for WebGL2 (the same code already in
   `tests/capture/capture.c`, which compiles under `SOKOL_GLES3`), and
   `copyTextureToBuffer` + `mapAsync` for WebGPU, where `-sASYNCIFY` is already on for the
   emdawnwebgpu build (`src/sokol/sokolWeb.c`).
2. A hand-off out of the sandbox: the module writes the RGBA bytes to a JS-visible buffer
   and the page exposes them, or writes into emscripten's virtual FS and the driver reads
   them through `FS.readFile`.
3. A web entry that takes a scene index the way `tests/golden/runner.ms` takes `VOID_SCENE`
   — an environment variable does not exist in a browser, so it becomes a query parameter.
4. A driver: `chrome.exe --headless=new --screenshot` is enough for liveness, but
   conformance needs to pull bytes out, so it needs CDP (node 22+ has a global `WebSocket`,
   so this needs no dependency) or playwright-core.
5. **A headless Chrome that actually has WebGPU.** The blocker measured above. Until then
   WebGPU conformance can only be taken headed.

The comparator does not change: `tests/golden/compare.ms` reads two PNGs and knows nothing
about where they came from.

**Cadence**, because three of the five backends are not this machine: D3D11 runs in every gate, and WebGPU and WebGL2 will once they have a readback. Metal (macOS and iOS) and GLES3 on the Android device run **once per phase**, and additionally at every change that touches a shader, the snapping rules or the atlas — the three places where backends actually diverge. The conformance report carries the date and the commit it was taken at, so a stale one is visible rather than assumed.

**Cross-backend tolerance is not the same as within-backend tolerance.** Different GPUs round rasterization and interpolation differently. The starting bound is: delta ≤ 1 ignored, fail at max delta ≥ 4 or above 0.05% of pixels at delta 2–3; every scene that cannot meet it gets a PENDING entry naming the backend and the cause. A scene that differs **structurally** between backends — a glyph one pixel over, a border one device pixel wide instead of two, a gradient banded on one backend and dithered on another — is not a tolerance question and never gets a budget. That is the class of bug guardrail 9 exists to catch, and it is the class that hand-ported shaders produce in all three references (GPUI's gradients and dither, Ghostty's cursor colour, Makepad's `modf` — VOID2D.md "Frame shape").

## Where each tier lands

| Phase | Tier work landing in it |
|---|---|
| **P0** ✅ | The harness: 37 T2 scenes, T4 rows and baseline, PENDING, gate scripts, harness self-checks, D3D11 readback, GLES3 readback written but unrun, and web liveness |
| **P1** ✅ | T1 display-list assertions; filter and atlas-regression rows; **48** T2 scenes; deterministic T4 counters |
| **P2** ✅ | T3 coverage oracle; T1 snapping and complete batch-reason reachability; **67** T2 scenes with per-scene draw/target counters; regenerated primitive groups |
| **P3** | T3 fontTools metrics and the HarfBuzz kerning subset; `text/` at three DPIs; T4 atlas and rasterization budgets; **69** T2 scenes; the first cross-backend run, WebGL2 at 65 / 69 — the five-backend run was not reached and moved to P6 |
| **P4** | T3 UCD segmentation; T1 glyph and run placement; editor scenes |
| **P5** | T1 dirty-range and idempotence assertions; T4 scroll and idle budgets; the h2d oracle |
| **P6** | T3 full HarfBuzz shaping; T4 wasm budget per module; device-loss fault injection as a test switch (MAKEPAD.md:104); GLES3 desktop and WebGPU conformance |

**What each tier covers today**, so the table above is read against something real:

| Tier | State after P2 |
|---|---|
| T0 | 708 tests over 43 files, `msc test src/test/index.ms`; twelve are harness parsers |
| T1 | 11 display-list snapshots plus no-GPU reachability and invariant assertions |
| T2 | 67 scenes, D3D11, byte-identical, zero budgets; six backends SKIP |
| T3 | three coverage oracles and two font oracles green; two current-roadmap SKIPs, plus full HarfBuzz at P6 |
| T4 | twelve counters gated per bench scene, two milliseconds reported; wasm budget SKIPs |
| T5 | human only |
The roadmap those phases belong to is [VOID2D.md](VOID2D.md) "Roadmap".
