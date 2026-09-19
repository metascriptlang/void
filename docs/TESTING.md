# Testing void — tiers, oracles, goldens and the gate (2026-09-20)

What a void change has to prove before it is committed, and who can re-run the proof.

**The problem this doc closes.** `msc test src/test/index.ms` is the only thing in this repo that anyone else can run: 133 `test` blocks and 457 `assert`s across `src/test/*.ms` (`msc test` also runs std's prelude tests, which is why the recorded gate figure is 380/380). Everything else that the last sessions used to judge their work lives in `out/tmp/`, which `.gitignore:5` excludes — the D3D11 readback harness (`out/tmp/capture/capture.{c,h}`, `demo2dCapture.ms`, `cmp.py`, twelve 800×600 `base_*.ppm` goldens) and the two seven-line entry points that make `src/examples/bench2d.ms` runnable (`out/tmp/bench/bench{Ui,Sprites}.ms`). The baseline in [VOID2D.md](VOID2D.md) and the "byte-identical readback" acceptance clauses in [VOID3D.md](VOID3D.md) were produced by files no one can check out. There is no gate script, no Makefile and no `.github/` anywhere in the repo; the gate is prose in `~/metascript/.wt/sokol-latest.md`.

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

This tier does not exist yet and cannot until the display list does ([VOID2D.md](VOID2D.md) P1). It is the largest single win in this doc.

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

**The scenes.** Small, static, frame-indexed — never time-indexed. Grouped so a change regenerates only its group.

| Group | Scenes |
|---|---|
| `prim/` | rounded rect per-corner radii · per-side borders · dashed border · drop shadow · inset shadow · shadow+fill+border in one instance · linear gradient sRGB · linear gradient Oklab · radial · multi-stop · dither band · slash and checkerboard patterns |
| `xform/` | the same card at rotation 0 / 7° / 45° · scale 0.5 / 1 / 2 · pivot from `Tile.dx/dy` · non-uniform scale (the approximation VOID2D.md "Open" records) |
| `snap/` | hairline at DPI 1.0 / 1.25 / 1.5 · zero border stays zero · fractional split of 7 px · fractional origin box · fractional scene size |
| `clip/` | nested masks · rotated mask · mask + scroll offset · a list scrolled so most rows are outside the clip |
| `text/` | a code line at 13 px, DPI 1.0 / 1.25 / 1.5 · a wrapped paragraph · decorations (underline, strikethrough, wavy) · caret and selection · mixed Latin + CJK fallback · a ligature line · a colour-emoji line |
| `image/` | sprite nearest and linear · `ObjectFit` variants · `corner_radii` on an image · `grayscale` |
| `filter/` | blur, glow, drop shadow on a subtree · group opacity over overlapping children |
| `regress/` | one scene per entry that leaves [VOID2D.md](VOID2D.md) "Known defects" |
| `harness/` | the three self-checks below |

Plus the existing demo (`src/examples/renderer2d.ms`, 800×600, frames 1/30/90/200), kept as the one big integration capture, because it is what the last three sessions compared and its goldens already exist.

**Tolerance: byte-identical is the default.** The existing captures earn that. `base`, `base2` and `pin` — three runs across two sokol pins — are byte-identical at frames 1, 30 and 200; only frame 90 moves, and by 1–2 pixels at delta 1 (`base_90 vs pin_90: 1 px differ, max delta 1, bbox (355,419)-(355,419)`). So a tolerance is not a property of this machine; it is a property of a scene, and a scene that needs one is a finding.

The rule:

- The comparator always reports `N px differ, max delta M, bbox` — `cmp.py`'s line, kept.
- The gate fails on any `N > 0` unless the scene has a `PENDING` entry carrying a budget (`maxPixels`, `maxDelta`) and a reason.
- A pending scene that comes back byte-identical **fails**, and the entry must be deleted — rexa's graduation rule (`vim_spec.rs:877-886`), applied to images.
- A scene in the table with no golden is an error, not a skip (rexa's `missing` assert, `vim_spec.rs:892-895`).

**Regeneration.** `sh scripts/golden.sh --update [scene…]`, never automatic. A golden changes only inside a commit that says why, and the PNG diff is the review artifact. A golden records what the renderer *does*, not what it should do: P0 generates them from today's renderer, defects and all, and each later phase regenerates the group it is supposed to move — which is how the phase proves it moved nothing else.

**Determinism preconditions.** Fixed DPI per scene; frame index, never wall clock (today's driver already captures at frames 1/30/90/200); the font bytes committed and hashed (`assets/font.ttf` already is); a fixed clear colour with alpha written; `CAPTURE_PREFIX` required, never defaulting into a golden path as `capture.c:32-34` does today.

## T3 — oracles

Where ground truth can come from outside void, it should, because a hand-written expectation is only ever as good as the session that wrote it.

| Domain | Oracle | Committed form | Verdict |
|---|---|---|---|
| Shaping: glyph ids, clusters, advances, offsets, OpenType features | **HarfBuzz** (`hb-shape --output-format=json`) over (font, size, text, features) rows | `tests/oracle/shape.json` | **Wire it.** Full version at P6 with the shaper; a subset (cmap + GPOS kerning, features off) is usable at P3 |
| Font metrics: `unitsPerEm`, ascent/descent/lineGap, underline and strikethrough position and thickness, broken-table fallbacks (GHOSTTY.md:62) | **fontTools**, reading `head`/`hhea`/`OS_2`/`post` directly | `tests/oracle/metrics.json` | **Wire it.** Exact, cheap, and it covers a GPUI weakness (GPUI ignores the font's underline metric, GPUI.md:54) |
| Grapheme clusters, line-break opportunities | **The Unicode UCD conformance files** `GraphemeBreakTest.txt`, `LineBreakTest.txt` | vendored under `tests/oracle/ucd/` with their version | **Wire it** at P4. Ground truth from the standard, so there is no second implementation to distrust |
| Analytic coverage of the SDF primitives | **A CPU reference**: the same rounded-rect and `erf`-shadow definitions supersampled 16×16 per pixel | `tests/oracle/coverage.ms` | **Wire it** at P2. No external dependency, and it is the only thing that says the AA is *correct* rather than merely stable — a golden only says "same as last week" |
| h2d semantics: `getBounds`, `localToGlobal`/`globalToLocal`, mask intersection, scale modes, text metrics | **Heaps compiled to JS**, which SCENE-SCALE.md:204 records as already runnable here | `tests/oracle/h2d.json` | **Wire it, second priority.** It is the only mechanical check that "void2d stays h2d in interface and semantics" (VOID2D.md "The rule") is still true. Its PENDING list is already written: the deliberate divergences in HEAPS.md "The h2d contract" and "Do not copy from h2d" — four-corner mask AABB, `ScaleMode.Zoom`/`AutoZoom`, `lineSpacing` units, the looser `colorKey` threshold |
| Oklab / sRGB interpolation, the gamma/contrast table | the published matrices; GPUI's 13-row `gamma_ratios` (`gpui/src/platform.rs:1344-1378`) is itself the source constant | — | **T0, not an oracle.** Our table equals theirs, or it does not |
| Glyph rasterization | FreeType, unhinted, same size and offset | — | **Not ground truth.** void2d deliberately does not match FreeType: stb_truetype in the pixel-exact regime with its own four x-variants. Usable as a shape smoke check with a loose coverage bound — is the outline right? — and never as a gate on pixels. Say so rather than implying otherwise |
| GPUI / Zed parity | a Zed screenshot | — | **Manual, and not a gate.** See T5 |

**Regeneration and CI.** Same shape as rexa: `VOID_ORACLE=1` regenerates inside the same test that otherwise compares, the snapshot is committed, and the gate never needs the tool (`AGENTS.md:135-136`). A case row is data with no expected output. Divergences go to PENDING with a reason, and the pass rate against each oracle is printed.

The interesting number here is the UAX #14 one. void2d's wrap rule is GPUI's — after a space, or at any non-word char (GPUI.md:49) — not UAX #14, so most `LineBreakTest.txt` rows will land in PENDING under one shared reason. That is the honest use of a pass rate: it says how far the cheap rule is from the standard, and the number is the argument for or against replacing it, instead of nobody knowing.

## T4 — budget

`src/examples/bench2d.ms` is committed (`90369b3`); what is missing is the two seven-line entries that make it runnable, `out/tmp/bench/bench{Ui,Sprites}.ms`. Commit them as `tests/bench/bench{Ui,Sprites}.ms` and the whole perf story becomes reproducible.

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
- **Capture shape checks.** Assert the readback's width, height and row pitch, and that the image is not uniformly the clear colour — the "captured before the draw" bug.
- **Input pinning.** Font bytes hashed; DPI fixed per scene; frame index, not wall clock; `CAPTURE_PREFIX` required.
- **Cross-checks between our own tables**, rexa's `the_command_table_agrees_with_the_parser` (`crates/rexa-editor/src/vim/parser.rs:667`) in renderer form: the instance layout the shader declares agrees with the one the emitter writes; every `mode` the shader branches on is reachable from an emitter; every command kind has a batch-break rule.
- **The build trap is part of the gate.** `msc build` answers "Up to date" after a header that a compiled `.c` includes has changed, and the global object cache is keyed on the `.c` and not its includes — `--force` does not bypass it (`~/metascript/.inbox/compiler/2026-09-20-object-cache-ignores-headers.md`). Every shader regeneration hits this. The gate's first step deletes the output binary, `out/debug/.cache` and this checkout's objects under `~/.metascript/cache/objects`. A gate that silently tests the previous binary is worse than no gate.

## The gate

`scripts/gate.sh`, the first one this repo has had. Each step prints PASS, FAIL or SKIP **with a reason**; a SKIP is loud and counted, and nothing may report PASS for a backend it did not run.

1. Evict the caches (above).
2. `msc test src/test/index.ms` — T0 and T1.
3. Build the golden runner; render every scene twice; determinism check; compare to `tests/golden/d3d11/`; report `N px differ, max delta M` per scene and the pass rate.
4. Oracles present on this machine: compare against the committed snapshots. Absent tool → SKIP, named.
5. `scripts/build-web.sh`, then capture both web backends in headless Chrome and compare to the **same** D3D11 goldens.
6. `tests/bench/` — counters gated against `tests/bench/baseline.json`, milliseconds reported.
7. wasm sizes against the budget.
8. Print the tier table, the per-backend conformance pass rates, and the PENDING count.

Green before every commit, as in rexa (`AGENTS.md:301-302`). A bug gets its regression case in the same change as the fix.

## Guardrail 9 — how "same pixels on every platform" is actually checked

**Honest status today: it is not.** Only D3D11 has a readback path, and it is gitignored. Metal, GLES3, WebGPU and WebGL2 have never had their pixels compared to anything; the existing web check is "WebGPU and WebGL2 render in headless Chrome" (`~/metascript/.wt/sokol-latest.md`), which is a liveness check, not a conformance one.

**The design: one golden set, authored on D3D11; five backends compared against it.** Not five golden sets — five golden sets would record five different renderers and prove exactly nothing. The output is a per-backend conformance report: scenes identical, scenes within a stated bound, scenes failing, and a pass rate. That report *is* guardrail 9, and it belongs in VOID2D.md as a number that moves per phase.

What each readback costs:

| Backend | Mechanism | Runs on | Effort |
|---|---|---|---|
| D3D11 | staging texture + `CopyResource` + `Map` | this Windows box | exists; needs moving into the repo |
| GL / GLES3 | `glReadPixels` | this box (desktop GL), the Android device | ~30 lines, and it is shared with WebGL2 |
| Metal | blit to a shared `MTLBuffer`, or `MTLTexture.getBytes` | the Mac, the iOS device | ~50 lines |
| WebGPU | `copyTextureToBuffer` + `mapAsync`; `-sASYNCIFY` is already on for the emdawnwebgpu build (`src/sokol/sokolWeb.c`) | headless Chrome on this box | ~60 lines plus a JS hand-off |
| WebGL2 | the GLES3 path | headless Chrome on this box | shared |

Browser capture is driven by Playwright — `.playwright-mcp/` in `.gitignore:23` says it has driven this repo's web builds before. The wasm side writes the RGBA bytes out, the driver saves the PNG, and the comparator is the same one.

**Cadence**, because three of the five backends are not this machine: D3D11, WebGPU and WebGL2 run in every gate. Metal (macOS and iOS) and GLES3 on the Android device run **once per phase**, and additionally at every change that touches a shader, the snapping rules or the atlas — the three places where backends actually diverge. The conformance report carries the date and the commit it was taken at, so a stale one is visible rather than assumed.

**Cross-backend tolerance is not the same as within-backend tolerance.** Different GPUs round rasterization and interpolation differently. The starting bound is: delta ≤ 1 ignored, fail at max delta ≥ 4 or above 0.05% of pixels at delta 2–3; every scene that cannot meet it gets a PENDING entry naming the backend and the cause. A scene that differs **structurally** between backends — a glyph one pixel over, a border one device pixel wide instead of two, a gradient banded on one backend and dithered on another — is not a tolerance question and never gets a budget. That is the class of bug guardrail 9 exists to catch, and it is the class that hand-ported shaders produce in all three references (GPUI's gradients and dither, Ghostty's cursor colour, Makepad's `modf` — VOID2D.md "Frame shape").

## Where each tier lands

| Phase | Tier work landing in it |
|---|---|
| **P0** | The whole harness: T2 suite, T4 rows and baseline, PENDING, `scripts/gate.sh`, the harness self-checks, D3D11 + GL readback, browser capture |
| **P1** | T1 created — the display list is what makes it possible; regression scenes for six defects; T4 counters |
| **P2** | T3 coverage oracle; T1 snapping and batch-break assertions; `prim/`, `xform/`, `snap/`, `clip/` regenerated |
| **P3** | T3 fontTools metrics and the HarfBuzz kerning subset; `text/` at three DPIs; T4 atlas budget; the first full five-backend conformance run |
| **P4** | T3 UCD segmentation; T1 glyph and run placement; editor scenes |
| **P5** | T1 dirty-range and idempotence assertions; T4 scroll and idle budgets; the h2d oracle |
| **P6** | T3 full HarfBuzz shaping; T4 wasm budget per module; device-loss fault injection as a test switch (MAKEPAD.md:104) |

The roadmap those phases belong to is [VOID2D.md](VOID2D.md) "Roadmap".
