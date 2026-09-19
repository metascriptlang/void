# PENDING — known divergences, read by the harnesses

One entry per known failure, with the reason and the phase that removes it
([docs/TESTING.md](../docs/TESTING.md) "PENDING"). The rule is rexa's, unchanged:

> **A listed case that starts passing fails the run**, and its entry is deleted in the same
> commit as the fix.

That is what keeps the list from going stale, and it is why the list can be seeded
aggressively. The build-breaking condition is absolute: zero unlisted failures, zero
graduated entries, zero missing snapshots.

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

## Scenes that cannot be captured yet

These are rows of the scene table in [docs/TESTING.md](../docs/TESTING.md) "T2" that today's
renderer cannot produce. The phase that lands the feature adds the row to
`tests/golden/table.ms` and deletes the entry here, in the same commit.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| golden-missing:filter/blur | T2 | a node filter opens a render-target pass inside the swapchain pass; a debug build trips sokol's `!_sg.cur_pass.valid` assertion and aborts, a release build presents nothing but the clear colour. The builder exists in `tests/golden/scenes.ms` | P1 | 2026-09-20 |
| golden-missing:filter/glow | T2 | same cause as filter/blur | P1 | 2026-09-20 |
| golden-missing:filter/dropShadow | T2 | same cause as filter/blur | P1 | 2026-09-20 |
| golden-missing:filter/groupOpacity | T2 | same cause as filter/blur | P1 | 2026-09-20 |
| golden-missing:regress/filterNestedPass | T2 | same cause as filter/blur; the siblings drawn before and after the filtered node disappear with it | P1 | 2026-09-20 |
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
| walk-issues-gpu-calls | T1 | `sg_*` calls happen while the tree is walked (`batcher.c:218-251`, `draw.ms:264-277`, `:307-320`). Assertable only once the stream is the walk's only output | P1 | 2026-09-20 |
| text-buffer-churn | T1 | a text change destroys and recreates its GPU buffer (`render.ms:110-111`) | P1 | 2026-09-20 |
| upload-per-bracket | T1 | there is no "one upload per bracket" to assert against; the batch flushes on every state change | P1 | 2026-09-20 |
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
| debug-abort:node-filter | T2 | any `Node2D.filter` trips `Assertion failed: !_sg.cur_pass.valid` (`sokol_gfx.h:27214`) and the process dies. The path has never had a caller: no example and no test sets `Node2D.filter` | P1 | 2026-09-20 |
| debug-abort:vertex-cap | T2 | `regress/vertexCap` panics with `VALIDATION_FAILED` (`sokol_gfx.h:23960`) when `sg_append_buffer` runs past the 65 536-vertex buffer. In release the same overflow is silent, which is what the golden records | P1 | 2026-09-20 |

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
