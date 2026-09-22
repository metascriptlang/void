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
| ~~Atlas-full drops a different set of glyphs each run~~ | **closed (held)** - `FONS_ATLAS_FULL` grows the atlas and lets fontstash retry, and the retired image/view are freed one frame later instead of leaked. Golden `regress/atlasFull` is on: **10 runs, 1 output**, against 3 outputs in 10 before. P3 still removes the class with fontstash | done / P3 |
| ~~At most ~126 Labels/Graphics render~~ | **closed `747127f`** — golden `regress/nodeCap` shows all 200 labels; `ui.buffersAlive` 2, constant in node count. `ui.buffersRefused` deleted with the defect | done |
| ~~Node filters do not work at all~~ | **closed** - per-target command lists are hoisted out of the swapchain list, so the replay runs each target as its own pass before it. Goldens `filter/blur`, `filter/glow`, `filter/dropShadow`, `filter/groupOpacity`, `regress/filterNestedPass` are on. Re-measured in a debug build with sokol's validation layer linked: all five capture, no `!_sg.cur_pass.valid` | done |
| ~~Filter semantics differ from h2d~~ | **closed** - the node itself enters the target, alpha applied once, object-local space through the emitter's filter matrix, bounds clipped to the viewport, one sync, a frame-linear target pool. `filter/groupOpacity` is the proof and was read pixel by pixel against both models | done |
| ~~Fractional DPI puts every glyph off-grid~~ | **closed `747127f`** — `begin2d` takes a float logical size; golden `regress/dpiTruncation` moved. The `text/` and `snap/` goldens did not move: integer glyph origins are a separate defect | done / P3 for glyph origins |
| ~~Samplers are hard-wired REPEAT~~ | **closed** — four samplers indexed by `smooth * 2 + tileWrap`, clamp by default. `regress/samplerRepeat` moved but is weak (448 px at max delta 2: both sheet edges are near-black); `image/tileWrap` is the scene that shows the mechanism, and `image/sceneSmooth` covers the tri-state | done |
| ~~Per-frame vertex cap~~ | **closed `747127f`** — one growing buffer, cap plus dropped frame past it; golden `regress/vertexCap` moved; `debug-abort:vertex-cap` deleted after a debug build was re-run and did not abort | done |
| ~~GPU calls are issued while the tree is walked~~ | **closed** - behaviour at `747127f`, and the assertion that holds it at the T1 tier: `tests/displayList/snapshot.ms` records three scenes with no GPU at all and asserts that after a walk the stream is full and `uploadCount()` has not moved. The three rows are deleted | done |
| A rotated Mask clips to its AABB | golden `clip/rotatedMask` | P2 |
| Culling tests the viewport rather than the active clip | row `cull-against-viewport` (the golden `clip/scrolledList` looks right; only the cost is wrong) | P2 |
| Integer glyph origins and rounded advances, `kern`-only metrics, `split(" ")` wrapping, no `textWidth`, no fallback, ≤ 16 fonts, the R8→RGBA CPU expansion | goldens `text/code13Dpi100` and `text/wrapped` for the pixels, rows `h2d-text-metrics` and `golden-missing:text/cjkFallback` for the surface that does not exist | P3 |
| The h2d surface still missing — `parent`, `TileGroup`, `Tile.dx/dy`, `Mask.scrollX/Y`, text metrics | rows `h2d-object-surface`, `h2d-tilegroup`, `h2d-text-metrics`, `one-node-two-parents`, `golden-missing:xform/tilePivot`, `golden-missing:clip/maskScroll` | P2 / P3 / P5 |
| Idle costs a full walk and draw | row `idle-costs-a-walk` | P5 |
| ~~Entry points declare `function main()` and nothing calls it~~ | **closed.** `src/examples/mainSokol2d.ms` at P0, and the gate runs the demo rather than only building it; the four void3d entries by the void3d arc at `e4a1a05`, on `main` in `c2019b5`. Row `entry-main-not-called` deleted here, in the commit that rebased onto that main | P0 / void3d arc |

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
| golden-missing:prim/dashedBorder | T2 | scene not renderable until P2 | P2 | 2026-09-20 |
| golden-missing:prim/cardOneInstance | T2 | scene not renderable until P2 — shadow, fill and border in one instance | P2 | 2026-09-20 |
| golden-missing:prim/gradientOklab | T2 | scene not renderable until P2 — gradients are per-vertex sRGB today | P2 | 2026-09-20 |
| golden-missing:prim/gradientMultiStop | T2 | scene not renderable until P2 | P2 | 2026-09-20 |
| golden-missing:prim/ditherBand | T2 | scene not renderable until P2 — no dither today | P2 | 2026-09-20 |
| golden-missing:prim/patterns | T2 | scene not renderable until P2 — slash and checkerboard | P2 | 2026-09-20 |
| golden-missing:xform/tilePivot | T2 | scene not renderable until P2 — `Tile.dx/dy` does not exist | P2 | 2026-09-20 |
| golden-missing:snap/zeroBorder | T2 | scene not renderable until P2 — no border primitive, so "zero stays zero" has nothing to assert | P2 | 2026-09-20 |
| golden-missing:image/objectFit | T2 | scene not renderable until P2 | P2 | 2026-09-20 |
| golden-missing:image/cornerRadii | T2 | scene not renderable until P2 | P2 | 2026-09-20 |
| golden-missing:image/grayscale | T2 | scene not renderable until P2 — the image mode; the `colorMatrix` form is captured as `image/colorPipeline` | P2 | 2026-09-20 |
| golden-missing:text/cjkFallback | T2 | scene not renderable until P3 — no fallback chain, one font | P3 | 2026-09-20 |
| golden-missing:clip/maskScroll | T2 | scene not renderable until P5 — `Mask.scrollX/Y` does not exist | P5 | 2026-09-20 |
| golden-missing:text/decorations | T2 | scene not renderable until P4 — no underline, strikethrough or wavy | P4 | 2026-09-20 |
| golden-missing:text/caretSelection | T2 | scene not renderable until P4 | P4 | 2026-09-20 |
| golden-missing:text/ligature | T2 | scene not renderable until P6 — no shaper, so `calt` never fires | P6 | 2026-09-20 |
| golden-missing:text/colourEmoji | T2 | scene not renderable until P6 | P6 | 2026-09-20 |
| golden-missing:image/animatedFrames | T2 | frame-indexed animation exists on `Anim` but has no deterministic frame input yet; folded into P6's animated image frames | P6 | 2026-09-20 |

## Known defects with no pixels to capture

Every line of [docs/VOID2D.md](../docs/VOID2D.md) "Known defects" is listed somewhere on
this page. These are the ones a golden image cannot see: they are cost, not colour, and the
tier that catches them is T1 — which does not exist until P1 creates the display list.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| atlas-resize-transient-frame | T2 | when the glyph atlas grows during a frame, labels already laid out in that frame hold UVs normalised to the old atlas size for that one frame; each corrects itself on its next sync, and `lastAtlasGen` is now read before layout so the label that triggered the growth is not permanently wrong. A golden cannot see it (the runner draws three frames and captures the last two) and an app sees it once, on first use of a new glyph size | P3 | 2026-09-20 |
| style:line-length | T0 | CODE-STYLE asks for <=100 columns. Measured 2026-09-20 with `awk 'length > 100' $(git ls-files '*.ms') | wc -l` -> **204** repo-wide, and over the ten files P1 wrote or rewrote (`displayList draw render node scene filter snapshot benchRows table scenes`) -> **79**. Every one is code, not a comment: the compressed conditions in `render.ms sync`, long `imageQuad` argument lists, import lines, and the 46 data rows of `table.ms`. Carried as F13 since P0 and deliberately not done at P1 - wrapping code by hand across ten files while the diff is about a send-back's blockers is risk for no behavioural gain. The command is here because P0's own F4 was that the numbers were not reproducible | P2 | 2026-09-20 |
| style:dpi-on-scene | T0 | P0's F2: fold the DPI into `Scene` state rather than `presentAt(dpi)`'s parameter. `begin2d` takes a float logical size since P1, which was the blocker; the argument is still a parameter because every caller - the golden runner above all - wants to pin it per scene. Decide the shape in P2, when `Scene` grows the retained state it needs anyway | P2 | 2026-09-20 |
| test:counter-snapshot-per-golden | T2 | P0's F3: commit a per-scene counter snapshot beside each golden, so a scene that draws the same pixels with ten times the draw calls fails. The runner already computes the draw count and prints it in the CAPTURED line, then discards it. T1 now covers this for three synthetic scenes; the 48 real ones do not have it | P2 | 2026-09-20 |
| filter-target-sized-in-logical-units | T2 | `render.ms` computes a filter target's size from bounds in LOGICAL units (`rtW = ceilToInt(xMax - xMin)`) and hands it to `allocRenderTarget` as a pixel size, so at DPI 1.5 a filtered subtree renders at 1/1.5 resolution and is upscaled on composite - visibly softer than everything around it. Same root cause as the scissor scaling fixed at P1, one level down, and found by P1's re-review. **`filter/maskAtDpi150` is captured at dpi 1.5 and therefore freezes this softness as expected**; when the target is sized in device pixels that golden moves, and that move is the fix landing | P2 | 2026-09-20 |
| cull-against-viewport | T1 | culling tests the viewport, not the active clip (`render.ms:191-201`), so `clip/scrolledList` draws forty rows to show four. The picture is right and the cost is wrong | P2 | 2026-09-20 |
| idle-costs-a-walk | T4 | `Scene.present` walks and draws every frame; nothing knows whether the tree changed | P5 | 2026-09-20 |
| h2d-object-surface | T0 | `parent`, `remove()`, `getChildAt`, `getChildIndex`, `numChildren`, `name`, and `localToGlobal` returning last frame's matrix (`node.ms:174-180`) | P5 | 2026-09-20 |
| h2d-tilegroup | T1 | `TileGroup` does not exist | P5 | 2026-09-20 |
| h2d-text-metrics | T0 | no `textWidth`, no `calcTextWidth`, no `splitText`, no per-glyph x | P3 | 2026-09-20 |
| one-node-two-parents | T0 | `addChild` does not detach from a previous parent (`node.ms:133-137`) | P5 | 2026-09-20 |

## Debug-build aborts

Found at P0 and not previously recorded. The golden suite is captured from a `--release`
build, where sokol's validation layer is compiled out; a debug build aborts on these before
it can capture anything.

| id | tier | reason | phase | date |
|---|---|---|---|---|

## Backends with no conformance run

Guardrail 9 is "same pixels on every platform", and today it is checked on one backend.
`scripts/gate.sh` prints each of these as a loud SKIP and never as a PASS.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| backend:gles3-desktop | T2 | `glReadPixels` is written (`tests/capture/capture.c`) but no GLES3 build of the runner has been run; the path is untested. Re-dated at P1's review: P1 never owned a second backend - guardrail 9's full five-backend run is P3's, and this row belongs with it | P3 | 2026-09-20 |
| backend:metal-macos | T2 | no readback; needs the blit to a shared `MTLBuffer` (~50 lines) and the Mac | P3 | 2026-09-20 |
| backend:metal-ios | T2 | no readback, and the device run is T5 the first time | P3 | 2026-09-20 |
| backend:gles3-android | T2 | shares the `glReadPixels` path; needs the device and an entry that writes the PNG off-device | P3 | 2026-09-20 |
| backend:webgpu | T2 | needs `copyTextureToBuffer` + `mapAsync` (~60 lines plus a JS hand-off) and a browser driver; see docs/TESTING.md "Guardrail 9" | P3 | 2026-09-20 |
| backend:webgl2 | T2 | shares the GLES3 path in wasm; needs the same browser driver | P3 | 2026-09-20 |

## Oracles not wired

[docs/TESTING.md](../docs/TESTING.md) "T3" lists these as "wire it". None exists yet.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| oracle:font-metrics | T3 | fontTools over `head`/`hhea`/`OS_2`/`post` | P3 | 2026-09-20 |
| oracle:coverage-shadow | T3 | the CAPTURE half of the shadow oracle: judge a captured soft shadow per pixel against the kernel integral. The T0 half is wired — `tests/oracle/coverage.ms` `blurredPixelCoverage` judges `shadowCoverage` in `src/test/coverageOracleCheck.ms` within 0.02 (worst 0.0078, wrong-blur convicted at 0.127). An axis-aligned scene keeps the truth one Riemann sum per pixel | P2 | 2026-09-22 |
| oracle:harfbuzz-kerning | T3 | the cmap + GPOS-kerning subset, features off | P3 | 2026-09-20 |
| oracle:ucd-segmentation | T3 | `GraphemeBreakTest.txt` and `LineBreakTest.txt` | P4 | 2026-09-20 |
| oracle:h2d | T3 | Heaps compiled to JS, for `getBounds`, `localToGlobal`, mask intersection and scale modes | P5 | 2026-09-20 |
| oracle:harfbuzz-full | T3 | the full shaping oracle | P6 | 2026-09-20 |

## Tests that belong to no tier

| id | tier | reason | phase | date |
|---|---|---|---|---|
| legacy:tests/layout.test.ms | T0 | a standalone binary with its own `expectEq` runner that does not build on msc 0.2.53; port its cases into `src/test/` or delete it (docs/TESTING.md "T0"). Re-dated at P1's review: it was stamped P1 and P1 did not touch it, so saying P1 again would be the third time | P2 | 2026-09-20 |
