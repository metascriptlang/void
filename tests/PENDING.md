# PENDING — known divergences, read by the harnesses

One entry per known failure, with the reason and the phase that removes it
([docs/TESTING.md](../docs/TESTING.md) "PENDING"). The rule is rexa's, unchanged:

> **A listed case that starts passing fails the run**, and its entry is deleted in the same
> commit as the fix.

That is what keeps the list from going stale, and it is why the list can be seeded
aggressively. The build-breaking condition is absolute: zero unlisted failures, zero
graduated entries, zero missing snapshots.

**The contract, stated exactly.** Every line of [docs/VOID2D.md](../docs/VOID2D.md)
"Known defects" is covered on this page in one of two ways, and the index below says which:

- **a row here** — the defect has no picture, or its picture cannot be captured yet. The
  graduation rule is what forces the row to be deleted when the defect is fixed.
- **a `regress/` golden** — the defect *has* a picture, and a golden is a stronger record
  than a list row, because it says what the defect looks like and not merely that it
  exists. The forcing function is different but real: fixing the defect changes those
  pixels, the gate goes red, and the only way to green is `sh scripts/golden.sh --update`
  in a commit that says why — which is the commit that also edits the "Known defects" line.

A defect that is in neither column is a hole, and the index is how that stays visible.

## Index — every "Known defects" line, and where it is covered

| docs/VOID2D.md "Known defects" line | covered by | phase |
|---|---|---|
| ~~Atlas-full drops a different set of glyphs each run~~ | **closed (held)** - `FONS_ATLAS_FULL` grows the atlas and lets fontstash retry, and the retired image/view are freed one frame later instead of leaked. Golden `regress/atlasFull` is on: **10 runs, 1 output**, against 3 outputs in 10 before. **Removed in P3 with fontstash**: glyph pages are fixed 1024² R8, never grown and never moved; a page with no live tile is reclaimed whole and a glyph with no room fails loud (`AtlasError.Full`). `regress/atlasFull` re-recorded: no report, two captures byte-identical | done |
| ~~At most ~126 Labels/Graphics render~~ | **closed `d05601c`** — golden `regress/nodeCap` shows all 200 labels; `ui.buffersAlive` 2, constant in node count. `ui.buffersRefused` deleted with the defect | done |
| ~~Node filters do not work at all~~ | **closed** - per-target command lists are hoisted out of the swapchain list, so the replay runs each target as its own pass before it. Goldens `filter/blur`, `filter/glow`, `filter/dropShadow`, `filter/groupOpacity`, `regress/filterNestedPass` are on. Re-measured in a debug build with sokol's validation layer linked: all five capture, no `!_sg.cur_pass.valid` | done |
| ~~Filter semantics differ from h2d~~ | **closed** - the node itself enters the target, alpha applied once, object-local space through the emitter's filter matrix, bounds clipped to the viewport, one sync, a frame-linear target pool. `filter/groupOpacity` is the proof and was read pixel by pixel against both models | done |
| ~~Fractional DPI puts every glyph off-grid~~ | **closed `d05601c`** — `begin2d` takes a float logical size; golden `regress/dpiTruncation` moved. The `text/` and `snap/` goldens did not move: integer glyph origins are a separate defect | done / P3 for glyph origins |
| ~~Samplers are hard-wired REPEAT~~ | **closed** — four samplers indexed by `smooth * 2 + tileWrap`, clamp by default. `regress/samplerRepeat` moved but is weak (448 px at max delta 2: both sheet edges are near-black); `image/tileWrap` is the scene that shows the mechanism, and `image/sceneSmooth` covers the tri-state | done |
| ~~Per-frame vertex cap~~ | **closed `d05601c`** — one growing buffer, cap plus dropped frame past it; golden `regress/vertexCap` moved; `debug-abort:vertex-cap` deleted after a debug build was re-run and did not abort | done |
| ~~GPU calls are issued while the tree is walked~~ | **closed** - behaviour at `d05601c`, and the assertion that holds it at the T1 tier: `tests/displayList/snapshot.ms` records three scenes with no GPU at all and asserts that after a walk the stream is full and `uploadCount()` has not moved. The three rows are deleted | done |
| ~~A rotated Mask clips to its AABB~~ | **closed** — T1 snapshot `rotatedClip` carries the two projection intervals; T2 golden `clip/rotatedMask` is the exact rotated rectangle rather than its AABB | done |
| ~~Culling tests the viewport rather than the active clip~~ | **closed** — T1 `active-clip culling drops rows outside a Mask` records four visible instances from forty rows; `clip/scrolledList` keeps the pixels | done |
| ~~No fallback chain; integer glyph origins, rounded advances, `kern`-only metrics, `split(" ")` wrapping, no `textWidth`, ≤ 16 fonts, the R8→RGBA CPU expansion~~ closed at P3 steps 3 and 5. Colour emoji landed in P6; whole-grapheme selection landed in P4 | goldens `text/*`, `text/cjkFallback` | done / P3 |
| ~~The h2d surface still missing~~ | **closed at P5 step 11** — `TileGroup`, the last of it: T0 `src/test/tileGroupCheck.ms`, T1 snapshot `tileGroup` and the retained-against-full writes in `tests/displayList/retain.ms`, T2 `image/tileGroup`; `Mask.scrollX/Y` at step 10, `parent`, `remove()`, reparenting and the index queries at step 6, `Tile.dx/dy`, uniform node pivots and the text metrics before it. Row `h2d-tilegroup` deleted | P5 |
| ~~Idle costs a draw~~ | **closed at P5 step 9** — `Scene2D.isDirty()` gates the host's frame; T4 `idleDirty` 0 on every bench scene | P5 |
| ~~A sokol view id past 2^24 names another slot in the replay~~ | **closed in P5** — the id travels as two 16-bit halves; T1 "a view id past 2^24 reaches the replay whole" in `displayList.ms` | P5 |
| ~~Entry points declare `function main()` and nothing calls it~~ | **closed.** `src/examples/mainSokol2d.ms` at P0, and the gate runs the demo rather than only building it; the four void3d entries by the void3d arc at `7b7f163`, on `main` in `3860752`. Row `entry-main-not-called` deleted here, in the commit that rebased onto that main | P0 / void3d arc |

## How a row is read

| Column | Meaning |
|---|---|
| `id` | `golden:<scene>` for an image budget; otherwise a free identifier |
| `tier` | T0..T5 ([docs/TESTING.md](../docs/TESTING.md) "The tiers") |
| `reason` | why it fails, in one line |
| `phase` | the phase that deletes this row |
| `date` | when the row was added |
| `maxPixels` / `maxDelta` | image budget; `-` when the row is not an image budget |

`tests/golden/compare.ms` parses only rows whose `id` starts with `golden:`, and only the
last two columns of those. Everything else on this page is for a reader.

## Image budgets

On D3D11 none: every scene in `tests/golden/table.ms` is byte-identical to its golden, across
runs and across processes. The `@metal` rows hold Metal captures judged against the D3D11 set
(`scripts/golden.sh --backend metal`) at exactly the pixels and delta measured, so any change
to those scenes on the Apple GPU shows.

| id | tier | reason | phase | date | maxPixels | maxDelta |
|---|---|---|---|---|---|---|
| golden:prim/shadowStack@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 12098 | 2 |
| golden:text/caretSelection@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 7367 | 2 |
| golden:filter/blur@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 7861 | 2 |
| golden:filter/dropShadow@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 3860 | 2 |
| golden:filter/afterTintedSibling@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 5014 | 2 |
| golden:filter/maskAtDpi150@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 2479 | 2 |
| golden:regress/atlasFull@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 17543 | 2 |
| golden:regress/filterNestedPass@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 4660 | 2 |
| golden:demo/frame001@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 36914 | 3 |
| golden:demo/frame030@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 37182 | 3 |
| golden:demo/frame090@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 37979 | 3 |
| golden:demo/frame200@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 37281 | 3 |
| golden:prim/effectOnUi@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 25385 | 2 |
| golden:text/sdfZoom4@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 1244 | 4 |
| golden:text/bidiSelection@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 4119 | 2 |
| golden:text/outlineAlpha@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 5773 | 2 |
| golden:text/outlineSdfZoom4@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 2365 | 4 |
| golden:text/outlineSdfScaleDown@metal | T2 | the Apple GPU rasterizes and filters a few levels off the D3D11 golden; sokol Metal at `6d577fd` captured it byte-identical to this backend (2026-10-22) | declared, D3D11 stays the authored set | 2026-10-23 | 1391 | 2 |

An empty table means the graduation rule has nothing to run on, so it was exercised by hand
at P0 and the result is written down here rather than described. Add a row to the table
above for a scene that currently passes, with a budget of 50 pixels at delta 3, and
`out/goldenCompare.exe` answers

> FAIL prim/roundedRect is byte-identical and still listed in tests/PENDING.md — delete the entry

and exits 1. Give the same row a budget of `9 874` and `-` and it answers

> FAIL tests/PENDING.md row golden:prim/roundedRect has an unreadable budget

and exits 1 — a budget that does not parse is never quietly read as zero. Delete the row and
the suite is green again. The first phase that needs a real budget inherits a mechanism that
has been seen to work in both directions.

Note for whoever writes the next row: the parser splits a line on `|` and looks at cells 1,
6 and 7, and it knows nothing about markdown. A pipe-delimited example anywhere on this page
— inside a fenced block included — is read as a real row. That is why the two examples above
are block quotes and not a table.



## Scenes that cannot be captured yet

These are rows of the scene table in [docs/TESTING.md](../docs/TESTING.md) "T2" that today's
renderer cannot produce. The phase that lands the feature adds the row to
`tests/golden/table.ms` and deletes the entry here, in the same commit.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| bidi:weak-caret-and-visual-motion | T1 | a second (weak) caret at a direction boundary and cursor motion in visual order are not built: `xForIndex` and `indexAt` answer the strong caret only (VOID2D.md P7, mechanism C), and a boundary between a Latin and a Hebrew run has a second position that nothing can reach. The references are Pango's `get_cursor_pos` (strong and weak) and cosmic-text's `Affinity`; GPUI and Makepad have neither. New public surface with no rendering-layer reference, so the human decides whether Neon needs it; Neon owns focus and key handling. Closes when the human says yes and the surface is specified, or says no and the row is deleted | human | 2026-10-08 |

## Human inputs for end-game verification

These are missing comparison inputs, not renderer passes or automatic-test failures.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| gpui:current-editor-terminal | T4 | Matched editor/terminal fixture correctness passed within the stated raster/selection limits; performance remains unmeasured. User-authorized setup passed on `b961b495` with exact Rust `1.98.1-x86_64-pc-windows-msvc`, upstream tree/lockfile and GNU global default unchanged. Optimized `hello_world` + profiler built exit 0; one named native proof opened, captured a nonblank 500x500 client and closed exit 0, without timing. Ordinary logs/capture: `projects/gpui/target/voidBench/{build,proof}/`. Both matched binaries now compile: Void `editorTerminal.ms` release/all-feature on `3f9d01d8` (tree `f955fd7c2fe6311614b38bba4c61bbd95388943c`, SDK `8a9fc02dd`) and current GPUI release optimized+debuginfo on `b961b495` (upstream tree `6881d1c8267b7f3734e860cb8e48f1e66a199a57`). Post-reboot named correctness GO ran only GPUI terminal/still: glyph identity/force-width validation and ordered 120 sample/cycle rows passed, 1280x720 DPI1 capture retained, RTX 5090 confirmed by `gpu_specs` and PID/LUID `0x00000000_0x0000F65C`; owned window closed exit 0. The pass stopped on the controller's background check: screenshot row 0 contained native frame chrome, while rows 1–7 and the other clip bands were exact background `(10,13,18)`. GPUI `events.rs` `handle_calc_client_size` preserves that hidden-titlebar top boundary. Consumer-only correction names/excludes that one GPUI DPI1 chrome row; native readback still checks row 0. Eleven CPU controls passed, including blank-with-chrome and four clip-edge refusals; raw capture and app binaries are unchanged. Evidence: `out/tmp/currentMatch/correctness/gpui-terminal-still/` and `controllerControls/chrome/`. Renewed correctness GO completed only unrun producers: two finite Void runs and twelve GPUI holds in total, reusing the first terminal/still capture, all fourteen positive exits 0 with no forced cleanup. All twelve matched phase pairs produced twenty-four PNGs; 6,600 sample rows and 6,600 cycle rows were structurally checked, not used as timing evidence. Both engines used RTX 5090 LUID `F65C`. Inter-terminal negative control exited 1 before samples: `GPUI force_width differs from Void ASCII cluster policy at byte1: actual=3.7387695 expected=8`. Parent inspected both phase-pair contact sheets and full still/per-cell images; content, mutations and clipping match. DirectWrite/stb glyph coverage and GPUI-path/Makepad-SDF selection corners differ: no byte-identical raster, human T5, actual Zed/Haro-app or universal parity claim. Exact Inter editor/default Cascadia subset terminal bytes remain fixed. The first quiet timing attempt on 2026-10-21 stopped before samples because the Void window was not observed in foreground: process exit 0, no forced cleanup, zero sample/cycle rows, official SDK HOLD released. Evidence: `out/tmp/currentMatch/timing20261021/`. The original immediate focus check did not record the API return, so Windows refusal versus asynchronous activation is unresolved. A bounded passive observation now records that distinction; eight mocked runner controls passed. A separately authorized retry reached quiet admission (CPU 8%, build-procs 0, no gates), but `SetForegroundWindow` returned false and all 98 foreground observations over 1.0 s still named another window. GetLastError was 0 and is diagnostic only; it does not identify which Windows activation restriction applied. Void closed exit 0 without forced cleanup; HOLD released. Its 79 sample/78 cycle background rows are invalid, no parsed-result file was produced, and the result consumer refused that actual run. No GPUI timing process or valid pair exists. Retry evidence: `out/tmp/currentMatch/timing20261021Retry/`. A third named quiet window at 13:48:50 (CPU 16%, build-procs 0, no gates) again returned false, with 97 observations over 1.0 s never reaching the target window. Void exited 0 without forced cleanup, HOLD released; its 64 sample/63 cycle background rows are invalid and no parsed-result file exists. Evidence: `out/tmp/currentMatch/timing20261021Afternoon/`. No GPUI timing process or valid pair exists across these attempts. Further active-workload timing needs an actual interactive foreground handoff plus a new quiet window, not merely an assumption that the user is awake. Source tracing shows GPUI defaults to a 33,333-us inactive callback cap while the frozen Void host has no equivalent unfocused cap; background timing is not a substitute for this active-workload comparison. Fresh named quiet GO and observed foreground on every process remain required; no focus-lock bypass or background-protocol substitution is authorized. Read-only DirectWrite defaults match Void gamma/contrast defaults; that is not rasterizer or quality parity. Next measure separately scoped timing under named bench GO, keeping these matched inputs unchanged. CPU cycles/frame intervals alone do not prove GPU elapsed time. Nsight Systems 2024.6 documentation distinguishes D3D11 CPU API timing and GPU frame cadence from GPU-busy execution; its WDDM queue coverage is not automatically per-frame GPU work. Separate collector privilege/data-scope permission and actual PID/adapter/frame attribution qualification remain open; no profiler has run. Closes with those measured receipts, not hello-world liveness, old registry GPUI 0.2.2 primitive timings or source-only comparison | human | 2026-10-19 |
| font:real13-human-look | T5 | The 13 logical px Inter/Cascadia native panel in `tests/integration/fontPanel.ms` has agent-inspected D3D11/GL captures at DPI 1/1.5/2/3, not human quality acceptance. Needs the human's target device/OS/backend/GPU and DPI, the actual font bytes/features, AA, gamma/contrast, line height and theme, plus a recorded review of dark/light stems, counters, spacing, fractional origins and transformed SDF. If judging Zed parity, supply the current Zed build and identical settings too. Closes with an explicit human accept/reject and the named captures/settings; cross-backend agreement, a demo screenshot or an agent's look does not close it | human | 2026-10-19 |

## Known defects with no pixels to capture

Every line of [docs/VOID2D.md](../docs/VOID2D.md) "Known defects" is listed somewhere on
this page. These are the ones a golden image cannot see: they are cost, not colour, and the
tier that catches them is T1 — which does not exist until P1 creates the display list.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| outline:backends | T2 | D3D11 and GL core outline rows passed in the native `35b8128b` gate on BUILD `4fe2a5eec`; the upstream `b0402ebf` full-feature WebGL2 land log reports all 120 scenes passing or bounded, including these rows, but its individual web PNGs were not retained. WebGPU readback and Metal macOS/iOS or GLES3 Android device evidence remain unmeasured. Closes per backend with the corresponding captured-row run, or a SKIP naming the missing hardware/readback; demo liveness alone is not outline conformance | human | 2026-10-08 |
| outline:look | T5 | nobody has looked at an outlined label: round joins at 13 px, the gamma and contrast step run with the outline colour's brightness (a dark outline under light text is corrected as dark text), and an opaque outline's slight darkening where two glyph outlines overlap. Closes when the human has looked at the `text/outline*` captures and writes down what he sees | human | 2026-10-08 |
| outline:sprite-glyph | T1 | a procedural box or block glyph (a Powerline arc, U+2588) draws no outline, and an outlined label is still valid with one in it. A design choice, not a defect: no reference outlines one (Godot's `FT_Glyph_Stroke` fails on a bitmap glyph and leaves it unoutlined, Makepad has no text outline), and refusing it by name would make a terminal-style label unusable with an outline; written in `docs/VOID2D.md` P6 "Text outline" and held by `src/test/labelOutlineCheck.ms` and `outlineEmitCheck.ms` | declared | 2026-10-08 |
| outline:translucent-interior | T1 | a fill or node alpha below 1 shows the outline colour through the glyph interior, because the outline tile is the dilated glyph and covers 1 under it. A design choice: Godot's MSDF path is the same dilation, and a band that leaves the interior clear needs the fill's coverage inside the outline tile. Written in `docs/VOID2D.md` P6 "Text outline"; the `text/outlineAlpha` capture will show it | declared | 2026-10-08 |
| outline:translucent-overlap | T1 | at tight spacing the outline tiles of neighbouring glyphs overlap, each is drawn on its own, and a translucent outline colour is blended twice where they meet. A design choice: one tile per glyph is the mechanism; an opaque outline shows nothing. Written in `docs/VOID2D.md` P6 "Text outline"; no row combines tight spacing with a translucent outline | declared | 2026-10-08 |
| outline:colour-glyph | T1 | a colour emoji draws no outline, for the same reason as `outline:sprite-glyph`: a dilation of an RGBA bitmap has no mechanism in any reference. Written in `docs/VOID2D.md` P6 "Text outline" | declared | 2026-10-08 |
| font-sbix-apple | T2 | sbix is proven on `tests/fonts/sbixSynthetic.ttf` only (png and dupe strikes, origin offsets, a refused jpg, an empty glyph): Apple Color Emoji is proprietary and not on the box that wrote the reader, and the origin and dupe rules follow the Apple sbix text as fontTools writes it, not FreeType, which was not read. Closes when the human draws a label through Apple Color Emoji on a Mac with `-d:voidColourEmoji` and the glyphs sit where the strike puts them | human | 2026-10-08 |
| style:line-length | T0 | CODE-STYLE asks for <=100 columns. Re-measured 2026-10-08 (characters per line, carriage returns stripped): **2** lines across 2 MetaScript files, the two `// expect:` first lines below. The void2d pass (branch `wt/void2d-lines`, targeted wraps, token-identical but six shortened test names; `msc fmt` was rejected because it rewrites whole files, 3 972 changed lines on `render.ms`) left none in `src/void2d`, void2d's tests, `tests/golden`, `tests/displayList`, `tests/bench`, `tests/integration`, `tests/experiments`, `tests/oracle`, `tests/harness` or `examples`, except the two `// expect:` first lines of `tests/aborts/target*.ms`, which `scripts/gate.sh` reads whole. void3d's half (`src/math/math3d.ms`, `math3dCheck`, `gltfCheck`, `particlesCheck`, `renderOrderCheck`) was wrapped the same way, token-identical but four split JSON literals, eight shortened test names and two trailing commas; the shared `src/examples` and `src/sokol/gpu.ms` were wrapped in this pass. P6 "Modules and hardening" owns the repository-wide pass | P6 | 2026-09-23 |
| style:uniform-box-constructors | T0 | `uniformRadii` and `uniformBorders` in `src/void2d/boxStyle.ms` stay free functions where the human approved `CornerRadii.uniform` and `BorderWidths.uniform` (P4 step 4): two same-name static extensions exported from one module resolve only the first in an importer. Compiler card `../../.inbox/compiler/2026-09-26-same-name-static-extensions-one-module.md` | compiler | 2026-09-26 |

## h2d oracle divergences

`src/test/h2dOracleCheck.ms` reads a row `h2d:<case>` or `h2d:scale-<Mode>` here as a listed
divergence from `tests/oracle/h2d.json` ([docs/TESTING.md](../docs/TESTING.md) "T3").

| id | tier | reason | phase | date |
|---|---|---|---|---|

## Debug-build aborts

Found at P0 and not previously recorded. The golden suite is captured from a `--release`
build, where sokol's validation layer is compiled out; a debug build aborts on these before
it can capture anything.

| id | tier | reason | phase | date |
|---|---|---|---|---|

## Backends with no conformance run

Guardrail 9 is "same pixels on every platform", and today it is measured on four backends, D3D11, GL core 4.3 desktop, WebGL2 and Metal on macOS.
`scripts/gate.sh` prints each of these as a loud SKIP and never as a PASS.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| backend:gles3-android | T2 | shares the `glReadPixels` path of `tests/capture/capture.c`, which has run under WebGL2 only, and needs an entry that writes the PNG off the device. Needs the human's Android device and `scripts/build-android.sh`. Closes when the runner builds with `-DVOID_GLES3` for Android, runs every scene on the device, the PNGs are pulled with `adb pull`, and `tests/golden/compare.ms` prints a pass rate against `tests/golden/d3d11` which `scripts/gate.sh` section 7 prints in place of its `skip "gles3 Android"` line; until then the gate prints that SKIP. Re-owned from P6 on 2026-10-08 | human | 2026-10-08 |
| backend:webgpu | T2 | needs `copyTextureToBuffer` + `mapAsync` (~60 lines plus a JS hand-off) in headless Chrome, which does hand WebGPU the real adapter on this box (2026-10-20, `docs/TESTING.md`); the WebGL2 driver in `scripts/webGolden.mjs` is the template. Moved at P3's review Re-owned 2026-10-08 to `web:runs`, which names what blocks it | compiler | 2026-09-24 |
| web:runs | T2 | the web build's runs (WebGL2 conformance by `sh scripts/golden-web.sh`, the WebGPU readback, the linked wasm per module) wait for a browser on this box. The build no longer blocks them: since yoga `b2d4f7e` compiles its sources for emcc, msc BUILD `5631dd3e5` (2026-10-16) builds `mainSokol2d` on both backends and `cardTable`, `worldLabel` and `targetTexture` on WebGL2 with `scripts/build-web.sh`, exit 0, no undefined `YGNode*` symbol. Closes when `scripts/build-web.sh`, `golden-web.sh` and the WebGPU readback run on this box, each reporting its pass rate. 2026-10-19: `build-web.sh` and `golden-web.sh` run on this box (WebGL2 120 / 120, msc BUILD `4fe2a5eec`); the WebGPU readback remains | human | 2026-10-08 |
| backend:sample-count-mobile | T5 | `sample_count > 1` on the Android bridge has no device run: it compiles under NDK 28 and links into gate3d's `libVoidAndroid.so`. iOS is in the gate (`bash scripts/iosDevice.sh samples`: `viewSamples.ms` PASSes at 1, 2 and 4 samples with void3d and void2d in one pass, and 8 stops by name because these GPUs do not support it). Closes when the human runs a sample count of 4 with a void3d scene on an Android device and reports that the pipelines build and the frame draws | human | 2026-10-08 |

## Shaping oracle divergences

`src/test/shapeOracleCheck.ms` reads a row `shape:<id>` here as a listed difference in glyph
count, glyph ids, advances, offsets or run direction, and a row `shape-cluster:<id>` as a listed
difference in the cluster index, compared on its own whenever the glyph counts are equal and so
also for a row listed under `shape:`, from `tests/oracle/shapeFull.json`
([docs/TESTING.md](../docs/TESTING.md) "T3"). The rows are `tests/oracle/shape.rows`. A listed row
that agrees fails the run; an unlisted row that differs fails it.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| shape:inter-mark-pair | T3 | `o` U+0302 U+0323 in Inter: HarfBuzz composes the three codepoints to one glyph, kb_text_shape keeps the base and a mark with a GPOS offset (two glyphs) | declared | 2026-10-07 |
| shape-cluster:devanagari-0 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:devanagari-1 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:devanagari-2 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:devanagari-3 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:devanagari-4 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:devanagari-5 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:devanagari-6 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:thai-variable-0 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:thai-variable-2 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:thai-variable-3 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:thai-variable-4 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:thai-variable-kern-off | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:khmer-0 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:khmer-1 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:khmer-2 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape-cluster:khmer-3 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape:arabic-ltr-explicit | T3 | an explicit `ltr` on Arabic text, shaped by kb_text_shape in a manual left-to-right run (measured 2026-10-08): the glyph count, clusters, advances and order agree, but the joining forms differ. kb_text_shape picks each letter's form from the text order, ids 43 19 15 8 47 3, the forms of the right-to-left row read in text order; HarfBuzz forced to left to right picks other forms for four of the six glyphs, ids 38 19 14 47 10 2. Void keeps kb_text_shape's answer, because joining belongs to the logical order whatever the paint direction | declared | 2026-10-08 |
| shape-cluster:missing-inter-zwj | T3 | U+200D with no glyph in the font: HarfBuzz folds the joiner into the preceding cluster, kb_text_shape gives its glyph its own codepoint's index; glyph ids, advances and offsets agree | declared | 2026-10-07 |

## SVG oracle divergences

`src/test/svgOracleCheck.ms` reads a row `svg:<id>` here as a listed difference from resvg, a mean
error past 3.5 or a worst pixel past 70 (of 255), or a refusal by name, from `tests/oracle/svg.json`
([docs/TESTING.md](../docs/TESTING.md) "T3"). The rows are `tests/oracle/svg.rows`. A listed row
that agrees fails the run; an unlisted row that differs fails it.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| svg:use-symbol-24 | T3 | `<use>` is outside the module's allowlist (nanosvg draws no `<use>`); refused by name, resvg draws both squares | declared | 2026-10-07 |
| svg:clip-path-24 | T3 | `clip-path` and `<clipPath>` are outside the allowlist (nanosvg has no clipping); refused by name, resvg clips | declared | 2026-10-07 |
| svg:mask-24 | T3 | `<mask>` and `mask` are outside the allowlist (nanosvg has no masks); refused by name, resvg masks | declared | 2026-10-07 |
| svg:pattern-fill-24 | T3 | `<pattern>` is outside the allowlist (nanosvg has no patterns); refused by name, resvg tiles it | declared | 2026-10-07 |
| svg:group-opacity-24 | T3 | `opacity` on a `<g>` is refused by name (`attribute opacity on <g>`): nanosvg multiplies it into each shape, so overlapping shapes composite twice (0.75 where the group should read 0.5); resvg composes the group as one layer | declared | 2026-10-07 |
| svg:gear-24 | T3 | a stroked path of many 1.65 radius arcs draws 2.9% less ink in nanosvg (200.7 against 206.6 pixels of coverage), scattered along the curved edges, mean error 5.03 against a 3.5 bound; lowering `tessTol` further (0.02, 0.01) gains nothing, cause not isolated | declared | 2026-10-07 |
| svg:dashed-24 | T3 | a dash edge of the 3 2 pattern on a triangle's closing corner lands on a different pixel: 2 pixels past 32, one by 124 | declared | 2026-10-07 |

## Sprite oracle budgets

`src/test/spriteOracleCheck.ms` compares the anti-aliased sprites with Ghostty's reference PNGs
(`tests/oracle/ghostty/`, [docs/TESTING.md](../docs/TESTING.md) "T3") under the budget a row
here gives its family: `maxPixels` is the most pixels in any one cell whose coverage differs by
more than 16 (one step of the reference's 4 by 4 supersampling), `maxDelta` the largest
difference in any cell. The numbers are the first measurement, on 2026-10-08, over four cell
sizes; the reference antialiases with z2d and the sprites with stb_truetype's rasterizer (the one
glyphs use), so no pixel is expected to agree to the byte. Raising a number needs a reason
written in its row.

| id | tier | reason | phase | date | maxPixels | maxDelta |
|---|---|---|---|---|---|---|
| sprite-aa:arcs | T3 | U+256D-2570: the cubic is flattened to line segments and stroked with butt caps, z2d strokes the curve itself | declared | 2026-10-08 | 4 | 26 |
| sprite-aa:diagonals | T3 | U+2571-2573: one stroked segment, the edges land on different sixteenths; maxDelta 17 became 18 when the sprites moved from an own exact-area accumulator to stbtt_Rasterize, whose float32 coverage differs from the old double accumulator by one level on some pixels (6 of the 11x21 cell, 14 of U+2573 there; every difference measured is 1) | declared | 2026-10-08 | 2 | 18 |
| sprite-aa:triangles | T3 | U+25E2-25E5, 25F8-25FA, 25FF: filled corner triangles and their inset outlines, every pixel within one step | declared | 2026-10-08 | 0 | 16 |
| sprite-aa:powerline | T3 | U+E0B0-E0BF, E0D2, E0D4: the long slanted edge of a 18x36 triangle puts 36 pixels about two steps from z2d's sample pattern; no pixel is more than 33 away | declared | 2026-10-08 | 36 | 33 |

## macOS and compiler gaps (msc e5e932d0)

Measured 2026-10-03 on macOS with `bash scripts/gate.sh --quick`, branch `wt/void-latest-msc`. Each one is red at origin `2be9cf5` and none was caused by that branch.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| compiler:literal-beside-float32 | T0 | `src/void2d/sdf.ms:176` (`-3.0 * …`) and `src/void2d/render.ms:1604` (`(c ? 1.0 : x) * y`): a negated literal and a ternary arm stay float64 beside a float32. Card `~/metascript/.inbox/compiler/2026-10-03-literal-beside-float32-negated-or-in-a-ternary.md` | compiler fix | 2026-10-03 |
