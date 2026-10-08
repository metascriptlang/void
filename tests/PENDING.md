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

None. Every scene in `tests/golden/table.ms` is byte-identical to its golden, across runs
and across processes, and P0 found no scene that needs a tolerance.

| id | tier | reason | phase | date | maxPixels | maxDelta |
|---|---|---|---|---|---|---|

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

## Known defects with no pixels to capture

Every line of [docs/VOID2D.md](../docs/VOID2D.md) "Known defects" is listed somewhere on
this page. These are the ones a golden image cannot see: they are cost, not colour, and the
tier that catches them is T1 — which does not exist until P1 creates the display list.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| outline:bench-bounds | T4 | `outlineBounds` in `tests/bench/baseline.json` (at most 4000 outline tiles in the zoom sweep, 0 in steady frames, 0 coverage rasterizations in steady frames, at most 8 coverage pages and 8 MiB) are the bench author's bounds, not a measurement: `benchTextOutline.ms` has not run (the 4000 is the Text bench's 3907 fill rasterizations of the same sweep, every one with an outline tile beside it; the pages are the Text bench's 2 plus the outline tiles' larger area). Closes when the human runs `sh scripts/gate.sh` natively, the `textOutline` rows of `out/gate-bench-rows.log` are PASS or the failing ones are replaced by what the bench printed, and the Profiler variant reads the same | human | 2026-10-08 |
| outline:native-gate | T0 | the outline module's native stages have never run: `scripts/gate.sh` with `-d:voidTextOutline` in the all-on stage and beside `-d:voidSdfText`, the three `tests/aborts/outline*.ms` and `glyphKeyOverflow.ms` programs, the `glyphSdfCheck.ms` byte-identity guard after the `distanceFill` refactor with both flags, the module-off object check of `scripts/wasmModuleDelta.sh` in the gate, and `src/test/index.ms` as one run (each outline file was run alone, with and without the flag). Closes when the human runs `sh scripts/gate.sh` and every stage is PASS | human | 2026-10-08 |
| outline:backends | T2 | the ten `text/outline*` rows are authored for D3D11 only. WebGL2 (ANGLE), GL core 4.3, WebGPU, Metal macOS and iOS and GLES3 Android have no outline capture; no shader changed, so the risk is the atlas upload path already proven for coverage and SDF pages. Closes per backend when `sh scripts/golden.sh --backend gl` and the web build's liveness run read the rows, or the unmeasured ones are reported as SKIP with their reason | human | 2026-10-08 |
| outline:capture-oracle | T3 | the SDF outline rows are judged by `src/test/sdfOutlineOracleCheck.ms` on the CPU emulation of the shader (mae <= 0.0325, p99 <= 0.263 at zoom 0.5, <= 0.015 and 0.126 from zoom 1), not on a capture, and no judge reads the captured pixels the way `tests/oracle/textSdfCheck.ms` reads the SDF text rows. Closes when a judge reads the `text/outlineSdf*` captures against the same Pillow outline oracle | human | 2026-10-08 |
| outline:look | T5 | nobody has looked at an outlined label: round joins at 13 px, the gamma and contrast step run with the outline colour's brightness (a dark outline under light text is corrected as dark text), and an opaque outline's slight darkening where two glyph outlines overlap. Closes when the human has looked at the `text/outline*` captures and writes down what he sees | human | 2026-10-08 |
| outline:sprite-glyph | T1 | a procedural box or block glyph (a Powerline arc, U+2588) draws no outline, and an outlined label is still valid with one in it. A design choice, not a defect: no reference outlines one (Godot's `FT_Glyph_Stroke` fails on a bitmap glyph and leaves it unoutlined, Makepad has no text outline), and refusing it by name would make a terminal-style label unusable with an outline; written in `docs/VOID2D.md` P6 "Text outline" and held by `src/test/labelOutlineCheck.ms` and `outlineEmitCheck.ms` | declared | 2026-10-08 |
| outline:translucent-interior | T1 | a fill or node alpha below 1 shows the outline colour through the glyph interior, because the outline tile is the dilated glyph and covers 1 under it. A design choice: Godot's MSDF path is the same dilation, and a band that leaves the interior clear needs the fill's coverage inside the outline tile. Written in `docs/VOID2D.md` P6 "Text outline"; the `text/outlineAlpha` capture will show it | declared | 2026-10-08 |
| outline:translucent-overlap | T1 | at tight spacing the outline tiles of neighbouring glyphs overlap, each is drawn on its own, and a translucent outline colour is blended twice where they meet. A design choice: one tile per glyph is the mechanism; an opaque outline shows nothing. Written in `docs/VOID2D.md` P6 "Text outline"; no row combines tight spacing with a translucent outline | declared | 2026-10-08 |
| outline:colour-glyph | T1 | a colour emoji draws no outline, for the same reason as `outline:sprite-glyph`: a dilation of an RGBA bitmap has no mechanism in any reference. Written in `docs/VOID2D.md` P6 "Text outline" | declared | 2026-10-08 |
| wasm:budget | T4 | guardrail 6's wasm budget per module has no linked number: `scripts/build-web.sh` cannot link Yoga for the web target (`~/metascript/.inbox/yoga/2026-10-03-yogah-has-no-web-branch-voids-wasm-cannot-link-sync.md`, owned by a session started in yoga) and emcc is not on the PATH of the box that wrote the module. What exists is `scripts/wasmModuleDelta.sh`: the default-layer and module objects in bytes, wasm32 and x86-64, recorded in `tests/bench/wasm.json` for colour emoji, SDF text, the shaper, sprites, bidi and the text outline, and `scripts/experiment-modulesWeb.sh` with its entry `tests/experiments/modulesWeb.ms` (no `node.ms`, so no Yoga), which builds the shaper and SDF text off and on per backend and is owed. Re-owned from P6 to the session started in yoga, which clears the card, and then to the human for the emcc run; every new golden's WebGL2 column (`text/colourEmoji` among them) waits on the same link. Closes when `sh scripts/experiment-modulesWeb.sh` prints a `WASM` row per module and backend on a box with emsdk 5.0.5, its numbers are written as `modulesWeb-<module> <backend> off <bytes> on <bytes>` rows in `tests/bench/wasmBudget.txt`, and, once the web build links, `build-web.sh` gives the wasm bytes of the demo with every module off and with each module on, which then replace the object numbers as the budget | human | 2026-10-08 |
| font-sbix-apple | T2 | sbix is proven on `tests/fonts/sbixSynthetic.ttf` only (png and dupe strikes, origin offsets, a refused jpg, an empty glyph): Apple Color Emoji is proprietary and not on the box that wrote the reader, and the origin and dupe rules follow the Apple sbix text as fontTools writes it, not FreeType, which was not read. Closes when the human draws a label through Apple Color Emoji on a Mac with `-d:voidColourEmoji` and the glyphs sit where the strike puts them | human | 2026-10-08 |
| colour:native-gate | T2 | the colour item's native stages have never run: the device-loss and occlusion stages built with `-d:voidColourEmoji` (an emoji label must put a colour page on the GPU and re-upload it), the `mainSokol2d.ms` module-off and module-on builds (the colour build larger, the off build naming no `void2dColour` symbol), `src/test/index.ms` and the headless checks with every module flag on, and the sampler of a zoomed tile on a real GPU. Closes when the human runs `sh scripts/gate.sh` on the native box and every colour stage is a PASS, not a SKIP | human | 2026-10-08 |
| colour:bench-bounds | T4 | `colourBounds` in `tests/bench/baseline.json` (2 pages, 8 MiB, 40 sweep rasterizations, 0 steady) are the bench author's estimate with no slack, not a measurement: `benchTextEmoji.ms` has not run, and a shifted rung boundary fails the first native run. Closes when the human runs `benchTextEmoji.ms` natively and replaces the four numbers with what it printed | human | 2026-10-08 |
| sdf:bench-bounds | T4 | `sdfBounds` in `tests/bench/baseline.json` (1 SDF page, 1 MiB, at most 40 sweep generations, 0 steady, at most 40 coverage sweep rasterizations, 0 steady) are the bench author's bounds, not a measurement: `benchTextSdf.ms` has not run (its measured frames hold the block rotated, so the zero steady counts are SDF cache hits) (the 40 is the number of distinct glyphs of the bench's code line; one generation each is the claim). Closes when the human runs `sh scripts/gate.sh` natively, the `textSdf` rows of `out/gate-bench-rows.log` are PASS or the failing ones are replaced by what the bench printed, and the Profiler variant (`out/benchTextSdfProfiler.exe`) reads the same | human | 2026-10-08 |
| style:line-length | T0 | CODE-STYLE asks for <=100 columns. Re-measured 2026-09-28 with the P0 command under a UTF-8 locale, `LC_ALL=C.UTF-8 awk 'length > 100' $(git ls-files '*.ms') | wc -l`, carriage returns stripped (the C locale counts an em dash as three): **228** lines across **38** MetaScript files; 56 are the one-row-per-scene data table. A compliant cut would touch most of those files, mostly formatting pre-existing imports, signatures and data rows, so P2 rejected that unrelated churn during renderer review. P6 "Modules and hardening" owns the repository-wide mechanical pass | P6 | 2026-09-23 |
| style:uniform-box-constructors | T0 | `uniformRadii` and `uniformBorders` in `src/void2d/boxStyle.ms` stay free functions where the human approved `CornerRadii.uniform` and `BorderWidths.uniform` (P4 step 4): two same-name static extensions exported from one module resolve only the first in an importer. Compiler card `../../.inbox/compiler/2026-09-26-same-name-static-extensions-one-module.md` | compiler | 2026-09-26 |
| compiler:bool-span-web | T4 | `scripts/build-web.sh` fails under emsdk's clang at `src/void2d/textLayout.ms` `selectedExtents` and `lineEdges`: a `Vec<boolean>` passed as `Span<boolean>` makes msc assign `uint8_t *` to `MS_BOOL *` with no cast (native clang and zig cc only warn). Not a regression: `99a851d7` emits the same C. Compiler card `../../.inbox/compiler/2026-09-26-interface-array-to-span-void-pointer.md`. Closes when the installed msc builds the card's `boolSpan.ms` under `-Werror=incompatible-pointer-types` and `sh scripts/build-web.sh` builds both backends | compiler | 2026-10-08 |

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

Guardrail 9 is "same pixels on every platform", and today it is measured on three backends, D3D11, GL core 4.3 desktop and WebGL2.
`scripts/gate.sh` prints each of these as a loud SKIP and never as a PASS.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| backend:metal-macos | T2 | no readback: `tests/capture/capture.c` has no Metal path, and the swapchain texture needs a blit to a shared `MTLBuffer` (~50 lines). Needs the human's Mac. Closes when, on that Mac, the readback is written, the golden runner captures every scene with `-DSOKOL_METAL`, and `tests/golden/compare.ms` prints a pass rate against `tests/golden/d3d11` which `scripts/gate.sh` section 7 prints in place of its `skip "metal macOS"` line; until then the gate prints that SKIP and never a PASS. Re-owned from P6 on 2026-10-08 because the run is not possible on the box that owns the code | human | 2026-10-08 |
| backend:metal-ios | T2 | no readback, and the first device run is T5. Needs the human's iPhone or iPad and the `ios/` project. Closes when the Metal readback of `backend:metal-macos` is written for the iOS bridge, the runner is installed on a device with `-DSOKOL_METAL`, every scene's PNG is copied off the device, and `tests/golden/compare.ms` prints a pass rate against `tests/golden/d3d11` which `scripts/gate.sh` section 7 prints in place of its `skip "metal iOS"` line; until then the gate prints that SKIP. Re-owned from P6 on 2026-10-08 | human | 2026-10-08 |
| backend:gles3-android | T2 | shares the `glReadPixels` path of `tests/capture/capture.c`, which has run under WebGL2 only, and needs an entry that writes the PNG off the device. Needs the human's Android device and `scripts/build-android.sh`. Closes when the runner builds with `-DSOKOL_GLES3` for Android, runs every scene on the device, the PNGs are pulled with `adb pull`, and `tests/golden/compare.ms` prints a pass rate against `tests/golden/d3d11` which `scripts/gate.sh` section 7 prints in place of its `skip "gles3 Android"` line; until then the gate prints that SKIP. Re-owned from P6 on 2026-10-08 | human | 2026-10-08 |
| backend:webgpu | T2 | needs `copyTextureToBuffer` + `mapAsync` (~60 lines plus a JS hand-off) and a headed browser, since headless Chrome hands WebGPU no adapter on this box; the WebGL2 driver in `scripts/webGolden.mjs` is the template. Moved at P3's review Re-owned 2026-10-08 to `web:runs`, which names what blocks it | compiler | 2026-09-24 |
| web:runs | T2 | the web build's runs (WebGL2 conformance by `sh scripts/golden-web.sh`, the WebGPU readback in a headed browser, the linked wasm per module) are blocked by two other repositories, not by a person: emcc refuses the `Vec<boolean>` span msc emits at `src/void2d/textLayout.ms` `selectedExtents` and `lineEdges` (`compiler:bool-span-web`, card `../../.inbox/compiler/2026-09-26-interface-array-to-span-void-pointer.md`), and Yoga has no web link (`wasm:budget`, `../../.inbox/yoga/2026-10-03-yogah-has-no-web-branch-voids-wasm-cannot-link-sync.md`). Closes when both clear and `scripts/build-web.sh`, `golden-web.sh` and the WebGPU readback run on this box, each reporting its pass rate | compiler | 2026-10-08 |
| backend:sample-count-mobile | T5 | `sample_count > 1` on the iOS and Android bridges has no device run: the Android bridge compiles under NDK 28 and links into gate3d's `libVoidAndroid.so`, the iOS bridge is not built on this box, and the D3D11 window's 1/2/4/8 run (`viewSamples.ms`) proves only that driver. Closes when the human runs a sample count of 4 with a void3d scene on an iPhone and on an Android device and reports that the pipelines build and the frame draws | human | 2026-10-08 |
| graphics:subpixel-fill | T2 | the P6 review read that a Graphics fill thinner than one device pixel inverts its body under the antialiasing inset (`graphics.ms` `contourFill` passes no inset limit to `draw.ms` `edgeMove`; only `strokePoly` passes its half width), so a 0.25-unit rect could draw a band near full alpha. Not captured. Closes when a golden of sub-pixel rects and circles at DPI 1 shows the ramp, and the fill is fixed if it does not | P6 | 2026-10-08 |
| conformance:webgl2-pixel-centre | T2 | first WebGL2 conformance run, P3 step 8 (`sh scripts/golden-web.sh`): 65 / 69 against the D3D11 goldens. `prim/strokeRect`, `prim/polygonBezier` and `xform/scale` differ structurally (max delta 179-224, one-pixel moves of horizontal edges): the mesh path put edges exactly on pixel centres and GL's bottom-left origin broke those ties the other way. Since then item 4's fringe removed those edge ties (all three pass on GL core 4.3 desktop, 2026-10-08) and the pattern part closed at its source, the pattern shader's threshold tie bias (prim/patterns byte-identical on D3D11 and GL 4.3). Kept for the WebGL2 re-measure, which needs the web build (Yoga web link, ~/metascript/.inbox/yoga/); no budget, by the guardrail 9 rule Re-owned 2026-10-08 to `web:runs`, which names what blocks it | compiler | 2026-09-24 |

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
| macos:voidRunConfigured | T1 | the six integration programs, their misuse lines, the expired draw-context line and the five bench executables fail to link: `_voidRunConfigured` has no macOS definition. `voidRequestedSize` is defined in `bridgeEmbed.m` for the same lane but was not link-tested on the Mac; `bridgeAndroid.c` answers 0×0 (host-sized surfaces, the capture guard no-ops) and no Android build ran either. Needs the human's Mac: no macOS definition of `voidRunConfigured` can be linked or run here. Closes when `_voidRunConfigured` is defined in `bridgeEmbed.m` and `bash scripts/gate.sh --quick` on that Mac links the six integration programs and the five bench executables and runs their misuse lines. Re-owned from P6 on 2026-10-08. | human | 2026-10-08 |
| macos:view-api | T1 | `twoViews` and its outside-view abort: `src/sokol/gpu.ms` exports no view API on macOS. Needs the human's Mac: the view API is not exported on macOS and `twoViews` cannot run here. Closes when `src/sokol/gpu.ms` exports the view API on macOS and `twoViews` and its outside-view abort run under `bash scripts/gate.sh --quick` on that Mac. Re-owned from P6 on 2026-10-08. | human | 2026-10-08 |
| compiler:literal-beside-float32 | T0 | `src/void2d/sdf.ms:176` (`-3.0 * …`) and `src/void2d/render.ms:1604` (`(c ? 1.0 : x) * y`): a negated literal and a ternary arm stay float64 beside a float32. Card `~/metascript/.inbox/compiler/2026-10-03-literal-beside-float32-negated-or-in-a-ternary.md` | compiler fix | 2026-10-03 |
