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
| ~~No fallback chain; integer glyph origins, rounded advances, `kern`-only metrics, `split(" ")` wrapping, no `textWidth`, ≤ 16 fonts, the R8→RGBA CPU expansion~~ closed at P3 steps 3 and 5. What the collection model still lacks is rows `font-colour-emoji` and `font-grapheme-selection` | goldens `text/*`, `text/cjkFallback` | done / P3 |
| The h2d surface still missing — `parent`, `TileGroup`, `Mask.scrollX/Y`; `Tile.dx/dy`, uniform node pivots and the text metrics are closed | rows `h2d-object-surface`, `h2d-tilegroup`, `one-node-two-parents`, `golden-missing:clip/maskScroll` | P5 |
| Idle costs a full walk and draw | row `idle-costs-a-walk` | P5 |
| A sokol view id past 2^24 names another slot in the replay | row `display-list-view-id-float32` | P5 |
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
| font-colour-emoji | T2 | an emoji draws `.notdef` after probing every fallback face. stb_truetype reads no colour glyph table, so colour emoji is a P6 compile-time module (decided at P3's review): CBDT/sbix strikes through `stb_image` and COLRv0 layers into RGBA pages, with explicit-versus-fallback presentation; deferred faces, which answer coverage before they load, land beside it in the default glyph layer | P6 | 2026-09-24 |
| font-grapheme-selection | T1 | a face is chosen per codepoint; a multi-codepoint grapheme should take the first face covering all of it (GHOSTTY.md:27), which needs the UCD segmentation P4 wires | P4 | 2026-09-24 |
| glyph-page-second-upload | T2 | a glyph first rasterized into a page that an earlier bracket of the same frame already uploaded is one frame late, because sokol permits one `sg_update_image` per image per frame. The resize half of the old row is gone: pages never grow, so no UV goes stale. The runner draws three frames, so a golden cannot see the transient. Fix direction from P3's review: a page already uploaded this frame takes no new tile and is not reclaimed | P5 | 2026-09-24 |
| label-dispose-pins-page | T1 | a Label dropped without `dispose` keeps its glyph tiles referenced, so its atlas page is never reclaimed; a reconciler that forgets `dispose` fills all 16 pages and then refuses glyphs. Only a comment in `node.ms` states it. The host contract owns node lifetime | P5 | 2026-09-24 |
| style:line-length | T0 | CODE-STYLE asks for <=100 columns. Re-measured 2026-09-23 with the P0 command `awk 'length > 100' $(git ls-files '*.ms') | wc -l`: **215** lines across **31** MetaScript files; 67 are the one-row-per-scene data table. A compliant cut would touch 31 files, mostly formatting pre-existing imports, signatures and data rows, so P2 rejected that unrelated churn during renderer review. P6 "Modules and hardening" owns the repository-wide mechanical pass | P6 | 2026-09-23 |
| ui-box-color-effect | T1 | A styled Rect combined with `colorMatrix`, `colorAdd` or `colorKey` is rejected loudly rather than rendered as a square flat fallback. P6 carries the existing colour-effect record through the unified UI shader, then adds a production-emitter assertion before this row is removed | P6 | 2026-09-23 |
| sdf-non-uniform-bound | T3 | Local-space box and `erf` shadow AA use the affine axes' geometric mean under non-uniform scale. P6 must bound that approximation with an independent coverage case; the legacy `xform/nonUniform` golden only pins its pixels and cannot prove the error | P6 | 2026-09-23 |
| idle-costs-a-walk | T4 | `Scene.present` walks and draws every frame; nothing knows whether the tree changed | P5 | 2026-09-20 |
| h2d-object-surface | T0 | `parent`, `remove()`, `getChildAt`, `getChildIndex`, `numChildren`, `name`, and `localToGlobal` returning last frame's matrix (`node.ms:174-180`) | P5 | 2026-09-20 |
| h2d-tilegroup | T1 | `TileGroup` does not exist | P5 | 2026-09-20 |
| one-node-two-parents | T0 | `addChild` does not detach from a previous parent (`node.ms:133-137`) | P5 | 2026-09-20 |
| display-list-view-id-float32 | T1 | the display list stores a sokol view id as `float32` (`CMD_VIEW`, and `draw.ms`'s saved view), exact below 2^24 only; an id is `(generation << 16) | slot`, so after the 256th reuse of one view slot the replay binds another slot. Found by P3.5's audit (REVIEWS.md "Audit before P4" #18) | P5 | 2026-09-25 |

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

## Oracles not wired

[docs/TESTING.md](../docs/TESTING.md) "T3" lists these as "wire it"; P2's rounded-rect and shadow coverage oracles and P3's fontTools metrics and HarfBuzz kerning subset already run in every gate.

| id | tier | reason | phase | date |
|---|---|---|---|---|
| oracle:ucd-segmentation | T3 | `GraphemeBreakTest.txt` and `LineBreakTest.txt` | P4 | 2026-09-20 |
| oracle:h2d | T3 | Heaps compiled to JS, for `getBounds`, `localToGlobal`, mask intersection and scale modes | P5 | 2026-09-20 |
| oracle:harfbuzz-full | T3 | the full shaping oracle | P6 | 2026-09-20 |

## Tests that belong to no tier

| id | tier | reason | phase | date |
|---|---|---|---|---|
| legacy:tests/layout.test.ms | T0 | Porting these five Yoga cases into `src/test/` is blocked by compiler card `../../.inbox/compiler/2026-09-22-imported-interface-literal-reachability.md`: assigning a partial literal through the imported `FlexStyle | null` field reaches codegen with its TypeInfo marked dead. The standalone file remains the parked site; no workaround hides the compiler failure | compiler | 2026-09-22 |
