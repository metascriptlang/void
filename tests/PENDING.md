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
| Atlas-full drops a different set of glyphs each run | row `golden-missing:regress/atlasFull` | P1 / P3 |
| ~~At most ~126 Labels/Graphics render~~ | **closed `747127f`** — golden `regress/nodeCap` shows all 200 labels; `ui.buffersAlive` 3, constant in node count. `ui.buffersRefused` deleted with the defect | done |
| ~~Node filters do not work at all~~ | **closed** - per-target command lists are hoisted out of the swapchain list, so the replay runs each target as its own pass before it. Goldens `filter/blur`, `filter/glow`, `filter/dropShadow`, `filter/groupOpacity`, `regress/filterNestedPass` are on. Re-measured in a debug build with sokol's validation layer linked: all five capture, no `!_sg.cur_pass.valid` | done |
| ~~Filter semantics differ from h2d~~ | **closed** - the node itself enters the target, alpha applied once, object-local space through the emitter's filter matrix, bounds clipped to the viewport, one sync, a frame-linear target pool. `filter/groupOpacity` is the proof and was read pixel by pixel against both models | done |
| ~~Fractional DPI puts every glyph off-grid~~ | **closed `747127f`** — `begin2d` takes a float logical size; golden `regress/dpiTruncation` moved. The `text/` and `snap/` goldens did not move: integer glyph origins are a separate defect | done / P3 for glyph origins |
| ~~Samplers are hard-wired REPEAT~~ | **closed** — four samplers indexed by `smooth * 2 + tileWrap`, clamp by default. `regress/samplerRepeat` moved but is weak (448 px at max delta 2: both sheet edges are near-black); `image/tileWrap` is the scene that shows the mechanism, and `image/sceneSmooth` covers the tri-state | done |
| ~~Per-frame vertex cap~~ | **closed `747127f`** — one growing buffer, cap plus dropped frame past it; golden `regress/vertexCap` moved; `debug-abort:vertex-cap` deleted after a debug build was re-run and did not abort | done |
| GPU calls are issued while the tree is walked | **behaviour closed `747127f`**, assertion not written: the walk's only output is the stream and `void2dReplay` is the only draw-issuing function. Rows `walk-issues-gpu-calls`, `text-buffer-churn`, `upload-per-bracket` stay open against the T1 tier | P1 (T1) |
| A rotated Mask clips to its AABB | golden `clip/rotatedMask` | P2 |
| Culling tests the viewport rather than the active clip | row `cull-against-viewport` (the golden `clip/scrolledList` looks right; only the cost is wrong) | P2 |
| Integer glyph origins and rounded advances, `kern`-only metrics, `split(" ")` wrapping, no `textWidth`, no fallback, ≤ 16 fonts, the R8→RGBA CPU expansion | goldens `text/code13Dpi100` and `text/wrapped` for the pixels, rows `h2d-text-metrics` and `golden-missing:text/cjkFallback` for the surface that does not exist | P3 |
| The h2d surface still missing — `parent`, `TileGroup`, `Tile.dx/dy`, `Mask.scrollX/Y`, text metrics | rows `h2d-object-surface`, `h2d-tilegroup`, `h2d-text-metrics`, `one-node-two-parents`, `golden-missing:xform/tilePivot`, `golden-missing:clip/maskScroll` | P2 / P3 / P5 |
| Idle costs a full walk and draw | row `idle-costs-a-walk` | P5 |
| Entry points declare `function main()` and nothing calls it | **fixed at P0** for `src/examples/mainSokol2d.ms`; the gate now runs the demo, not just builds it. The four void3d entries still carry it — row `entry-main-not-called` | P0 / void3d arc |

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
| golden-missing:regress/atlasFull | T2 | once the 512x512 fontstash atlas fills, which glyphs survive varies between runs of the same binary: three distinct outputs in ten runs, worst pair 28 740 of 80 000 pixels (35.9%) at max delta 207. The builder exists in `tests/golden/scenes.ms` | P1 | 2026-09-20 |
| golden-missing:prim/perCornerRadii | T2 | scene not renderable until P2 — one radius per rect today (`graphics.ms` `fillRoundedRect`) | P2 | 2026-09-20 |
| golden-missing:prim/perSideBorders | T2 | scene not renderable until P2 — `strokeRect` has one width | P2 | 2026-09-20 |
| golden-missing:prim/dashedBorder | T2 | scene not renderable until P2 | P2 | 2026-09-20 |
| golden-missing:prim/dropShadow | T2 | scene not renderable until P2 — the `erf` shadow as a primitive, distinct from the render-target filter | P2 | 2026-09-20 |
| golden-missing:prim/insetShadow | T2 | scene not renderable until P2 | P2 | 2026-09-20 |
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
| walk-issues-gpu-calls | T1 | **the behaviour is fixed** (`747127f`): the stream is the walk's only output. What is missing is the assertion that keeps it fixed — a T1 test that records a tree and proves no `sg_*` call was made before `end2d`. The T1 tier does not exist yet | P1 | 2026-09-20 |
| text-buffer-churn | T1 | **the behaviour is fixed** (`747127f`): no node owns a GPU buffer, so a text change rewrites a `float32[]` and nothing else. Missing is the T1 assertion that a text change creates and destroys no buffer | P1 | 2026-09-20 |
| upload-per-bracket | T1 | **the behaviour is fixed** (`747127f`): one upload per bracket, gated at T4 as `ui.uploads` 1 / `sprites.uploads` 1. Missing is the T1 assertion that reads the command stream directly rather than a counter | P1 | 2026-09-20 |
| cull-against-viewport | T1 | culling tests the viewport, not the active clip (`render.ms:191-201`), so `clip/scrolledList` draws forty rows to show four. The picture is right and the cost is wrong | P2 | 2026-09-20 |
| idle-costs-a-walk | T4 | `Scene.present` walks and draws every frame; nothing knows whether the tree changed | P5 | 2026-09-20 |
| h2d-object-surface | T0 | `parent`, `remove()`, `getChildAt`, `getChildIndex`, `numChildren`, `name`, and `localToGlobal` returning last frame's matrix (`node.ms:174-180`) | P5 | 2026-09-20 |
| h2d-tilegroup | T1 | `TileGroup` does not exist | P5 | 2026-09-20 |
| h2d-text-metrics | T0 | no `textWidth`, no `calcTextWidth`, no `splitText`, no per-glyph x | P3 | 2026-09-20 |
| one-node-two-parents | T0 | `addChild` does not detach from a previous parent (`node.ms:133-137`) | P5 | 2026-09-20 |
| entry-main-not-called | T2 | `mainSokol.ms`, `mainCampfire.ms`, `iosEntryAnim.ms` and `iosEmbedEntry.ms` declare `function main()` and end without calling it, so they build binaries that exit at once (CODE-STYLE.md section 9: "Nothing calls `main()`"). `src/examples/mainSokol2d.ms` was fixed at P0; these four are void3d's entries and belong to that arc | void3d arc | 2026-09-20 |

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
| backend:gles3-desktop | T2 | `glReadPixels` is written (`tests/capture/capture.c`) but no GLES3 build of the runner has been run; the path is untested | P1 | 2026-09-20 |
| backend:metal-macos | T2 | no readback; needs the blit to a shared `MTLBuffer` (~50 lines) and the Mac | P3 | 2026-09-20 |
| backend:metal-ios | T2 | no readback, and the device run is T5 the first time | P3 | 2026-09-20 |
| backend:gles3-android | T2 | shares the `glReadPixels` path; needs the device and an entry that writes the PNG off-device | P3 | 2026-09-20 |
| backend:webgpu | T2 | needs `copyTextureToBuffer` + `mapAsync` (~60 lines plus a JS hand-off) and a browser driver; see docs/TESTING.md "Guardrail 9" | P3 | 2026-09-20 |
| backend:webgl2 | T2 | shares the GLES3 path in wasm; needs the same browser driver | P3 | 2026-09-20 |

## Oracles not wired

[docs/TESTING.md](../docs/TESTING.md) "T3" lists these as "wire it". None exists yet.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| oracle:coverage | T3 | the CPU 16x16 supersampled rounded-rect and `erf` shadow reference — the only tier that says the AA is correct rather than merely unchanged | P2 | 2026-09-20 |
| oracle:font-metrics | T3 | fontTools over `head`/`hhea`/`OS_2`/`post` | P3 | 2026-09-20 |
| oracle:harfbuzz-kerning | T3 | the cmap + GPOS-kerning subset, features off | P3 | 2026-09-20 |
| oracle:ucd-segmentation | T3 | `GraphemeBreakTest.txt` and `LineBreakTest.txt` | P4 | 2026-09-20 |
| oracle:h2d | T3 | Heaps compiled to JS, for `getBounds`, `localToGlobal`, mask intersection and scale modes | P5 | 2026-09-20 |
| oracle:harfbuzz-full | T3 | the full shaping oracle | P6 | 2026-09-20 |

## Tests that belong to no tier

| id | tier | reason | phase | date |
|---|---|---|---|---|
| legacy:tests/layout.test.ms | T0 | a standalone binary with its own `expectEq` runner that does not build on msc 0.2.53; port its cases into `src/test/` or delete it (docs/TESTING.md "T0") | P1 | 2026-09-20 |
