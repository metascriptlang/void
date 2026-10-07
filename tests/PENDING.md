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
and across processes, and P0 found no scene that needs a tolerance. Two scenes that would
have needed one are not in the table at all — see "Scenes that cannot be captured yet".

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
| golden-missing:image/animatedFrames | T2 | frame-indexed animation exists on `Anim` but has no deterministic frame input yet; folded into P6's animated image frames | P6 | 2026-09-20 |

## Known defects with no pixels to capture

Every line of [docs/VOID2D.md](../docs/VOID2D.md) "Known defects" is listed somewhere on
this page. These are the ones a golden image cannot see: they are cost, not colour, and the
tier that catches them is T1 — which does not exist until P1 creates the display list.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| wasm:budget | T4 | guardrail 6's wasm budget per module has no linked number: `scripts/build-web.sh` cannot link Yoga for the web target (`~/metascript/.inbox/yoga/2026-10-03-yogah-has-no-web-branch-voids-wasm-cannot-link-sync.md`, owned by a session started in yoga) and emcc is not on the PATH of the box that wrote the module. What exists is `scripts/wasmModuleDelta.sh`: the default-layer and module objects in bytes, wasm32 and x86-64, recorded in `tests/bench/wasm.json`. Re-owned from P6 to the session started in yoga, which clears the card, and then to the human for the emcc run; every new golden's WebGL2 column (`text/colourEmoji` among them) waits on the same link. Closes when the web build links and `build-web.sh` gives the wasm bytes of the demo with every module off and with each module on, which then replace the object numbers as the budget | human | 2026-10-08 |
| font-sbix-apple | T2 | sbix is proven on `tests/fonts/sbixSynthetic.ttf` only (png and dupe strikes, origin offsets, a refused jpg, an empty glyph): Apple Color Emoji is proprietary and not on the box that wrote the reader, and the origin and dupe rules follow the Apple sbix text as fontTools writes it, not FreeType, which was not read. Closes when the human draws a label through Apple Color Emoji on a Mac with `-d:voidColourEmoji` and the glyphs sit where the strike puts them | human | 2026-10-08 |
| style:line-length | T0 | CODE-STYLE asks for <=100 columns. Re-measured 2026-09-28 with the P0 command under a UTF-8 locale, `LC_ALL=C.UTF-8 awk 'length > 100' $(git ls-files '*.ms') | wc -l`, carriage returns stripped (the C locale counts an em dash as three): **228** lines across **38** MetaScript files; 56 are the one-row-per-scene data table. A compliant cut would touch most of those files, mostly formatting pre-existing imports, signatures and data rows, so P2 rejected that unrelated churn during renderer review. P6 "Modules and hardening" owns the repository-wide mechanical pass | P6 | 2026-09-23 |
| style:uniform-box-constructors | T0 | `uniformRadii` and `uniformBorders` in `src/void2d/boxStyle.ms` stay free functions where the human approved `CornerRadii.uniform` and `BorderWidths.uniform` (P4 step 4): two same-name static extensions exported from one module resolve only the first in an importer. Compiler card `../../.inbox/compiler/2026-09-26-same-name-static-extensions-one-module.md` | compiler | 2026-09-26 |
| sdf-non-uniform-bound | T3 | Local-space box and `erf` shadow AA use the affine axes' geometric mean under non-uniform scale. P6 must bound that approximation with an independent coverage case; the legacy `xform/nonUniform` golden only pins its pixels and cannot prove the error | P6 | 2026-09-23 |

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

Guardrail 9 is "same pixels on every platform", and today it is measured on two backends, D3D11 and WebGL2.
`scripts/gate.sh` prints each of these as a loud SKIP and never as a PASS.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| backend:gles3-desktop | T2 | no desktop GLES3 build of the runner exists: `src/sokol/sokolWin.c` is D3D11 only and the shaders carry no `glsl430`. The `glReadPixels` path in `tests/capture/capture.c` itself has run under WebGL2 since P3 step 8. Moved at P3's review: the five-backend run P3's exit asked for was not reached, and this box can run this one | P6 | 2026-09-24 |
| backend:metal-macos | T2 | no readback; needs the blit to a shared `MTLBuffer` (~50 lines) and the human's Mac. Moved at P3's review | P6 | 2026-09-24 |
| backend:metal-ios | T2 | no readback, and the device run is T5 the first time, on the human's device. Moved at P3's review | P6 | 2026-09-24 |
| backend:gles3-android | T2 | shares the `glReadPixels` path; needs the human's device and an entry that writes the PNG off-device. Moved at P3's review | P6 | 2026-09-24 |
| backend:webgpu | T2 | needs `copyTextureToBuffer` + `mapAsync` (~60 lines plus a JS hand-off) and a headed browser, since headless Chrome hands WebGPU no adapter on this box; the WebGL2 driver in `scripts/webGolden.mjs` is the template. Moved at P3's review | P6 | 2026-09-24 |
| conformance:webgl2-pixel-centre | T2 | first WebGL2 conformance run, P3 step 8 (`sh scripts/golden-web.sh`): 65 / 69 against the D3D11 goldens. `prim/strokeRect`, `prim/polygonBezier`, `prim/patterns` and `xform/scale` differ structurally (max delta 179-224, one-pixel moves of horizontal edges and hatch lines): the mesh path puts edges and pattern thresholds exactly on pixel centres, and GL's bottom-left window origin breaks those ties on the other side of the top-left rule. No budget, by the guardrail 9 rule. Proposed root fix: bias mesh geometry by -1/64 px in x and y in device space, which keeps D3D11's tie results and gives GL the same | P6 | 2026-09-24 |

## Shaping oracle divergences

`src/test/shapeOracleCheck.ms` reads a row `shape:<id>` here as a listed difference in glyph
count, glyph ids, advances, offsets or run direction, and a row `shape-cluster:<id>` as a listed
difference in the cluster index, compared on its own whenever the glyph counts are equal and so
also for a row listed under `shape:`, from `tests/oracle/shapeFull.json`
([docs/TESTING.md](../docs/TESTING.md) "T3"). The rows are `tests/oracle/shape.rows`. A listed row
that agrees fails the run; an unlisted row that differs fails it.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| shape:inter-mark-pair | T3 | `o` U+0302 U+0323 in Inter: HarfBuzz composes the three codepoints to one glyph, kb_text_shape keeps the base and a mark with a GPOS offset (two glyphs) | P6 | 2026-10-07 |
| shape-cluster:devanagari-0 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:devanagari-1 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:devanagari-2 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:devanagari-3 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:devanagari-4 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:devanagari-5 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:devanagari-6 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:thai-variable-0 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:thai-variable-2 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:thai-variable-3 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:thai-variable-4 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:thai-variable-kern-off | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:khmer-0 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:khmer-1 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:khmer-2 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape-cluster:khmer-3 | T3 | kb_text_shape gives every glyph its own codepoint's index, HarfBuzz (cluster level 0) gives a mark or a reordered vowel its base's; glyph ids, advances and offsets agree | P6 | 2026-10-07 |
| shape:arabic-ltr-explicit | T3 | an explicit `ltr` on Arabic text: HarfBuzz forces the run direction, so the glyphs come in text order and unjoined; kb_text_shape takes the direction as the paragraph's and still shapes the Arabic run right to left, as BiDi does | P7 | 2026-10-07 |
| shape-cluster:arabic-ltr-explicit | T3 | same cause as `shape:arabic-ltr-explicit`: the clusters follow the run order each engine chose | P7 | 2026-10-07 |
| shape-cluster:missing-inter-zwj | T3 | U+200D with no glyph in the font: HarfBuzz folds the joiner into the preceding cluster, kb_text_shape gives its glyph its own codepoint's index; glyph ids, advances and offsets agree | declared | 2026-10-07 |
| shape:missing-mixed-direction | T3 | Latin and Arabic in one buffer: HarfBuzz shapes the whole buffer as one left-to-right run in logical order (it does no BiDi), kb_text_shape splits an Arabic run and reverses it; the layer's own BiDi decision, not this engine's, governs mixed text | P7 | 2026-10-07 |
| shape-cluster:missing-mixed-direction | T3 | same cause as `shape:missing-mixed-direction`: the clusters follow the run order each engine chose | P7 | 2026-10-07 |

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

## macOS and compiler gaps (msc e5e932d0)

Measured 2026-10-03 on macOS with `bash scripts/gate.sh --quick`, branch `wt/void-latest-msc`. Each one is red at origin `2be9cf5` and none was caused by that branch.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| macos:voidRunConfigured | T1 | the six integration programs, their misuse lines, the expired draw-context line and the five bench executables fail to link: `_voidRunConfigured` has no macOS definition. `voidRequestedSize` is defined in `bridgeEmbed.m` for the same lane but was not link-tested on the Mac; `bridgeAndroid.c` answers 0×0 (host-sized surfaces, the capture guard no-ops) and no Android build ran either | P6 | 2026-10-03 |
| macos:view-api | T1 | `twoViews` and its outside-view abort: `src/sokol/gpu.ms` exports no view API on macOS | P6 | 2026-10-03 |
| compiler:literal-beside-float32 | T0 | `src/void2d/sdf.ms:176` (`-3.0 * …`) and `src/void2d/render.ms:1604` (`(c ? 1.0 : x) * y`): a negated literal and a ternary arm stay float64 beside a float32. Card `~/metascript/.inbox/compiler/2026-10-03-literal-beside-float32-negated-or-in-a-ternary.md` | compiler fix | 2026-10-03 |
