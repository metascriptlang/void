# Makepad — Reference for void2d (2026-09-20)

[Makepad](https://github.com/makepad/makepad) (Makepad B.V., MIT/Apache-2.0) is a Rust UI runtime whose flagship is a code editor. It shares GPUI's model — instanced quads, SDF in the fragment shader, a glyph atlas, draw lists — and, **like Void and unlike GPUI, owns its whole stack**: its own shader language fanned out to D3D11, Metal, GL/WebGL2 and Vulkan, and its own text stack instead of the OS's. That makes it the closest existing answer to "GPUI's model under Void's constraints", and the place to check what happens to GPUI's decisions when there is no DirectWrite underneath. The entry point for void2d's decisions is [VOID2D.md](VOID2D.md); the model Makepad is cross-checked against is [GPUI.md](GPUI.md).

Source: `~/projects/makepad` (shallow clone) at `5e9a697`. Only `draw/`, `platform/`, `code_editor/` and the cited `widgets/` files were read; the AI, audio, XR and 3D parts were ignored. This checkout is the script-VM generation of Makepad: there is no `live_design!` DSL and line numbers differ from older trees. Read from source on 2026-09-20; nothing was built or benchmarked.

## What Makepad is

| | |
|---|---|
| Backends | D3D11, Metal, GL / WebGL2 (`#version 300 es`), Vulkan via WGSL → naga. **No WebGPU consumer** — the WGSL backend only feeds naga on the way to SPIR-V. |
| Shaders | One DSL, translated **at runtime** to MSL / HLSL / GLSL / WGSL by a single-pass generator with ~110 per-backend branches (`platform/script/src/shader.rs:209-245`, `shader_backend.rs:14-21`). A draw whose shader is still compiling is skipped — "a flat clear-color region" (`platform/src/draw_vars.rs:133-137`). D3D11 caches DXBC on disk (`platform/src/os/windows/d3d11.rs:4052-4194`). |
| Instance layout | A `#[repr(C)]` Rust struct **is** the instance: `DrawVars::as_slice()` returns its own memory (`draw_vars.rs:195-213`). `DrawQuad` 48 B, `DrawColor` 64 B, `DrawText` ~116 B (`draw/src/shader/draw_text.rs:1380-1417`). |
| Scene | A **retained tree of draw lists**. Each draw item owns a CPU float vec and its own GPU buffer, and both persist (`platform/src/draw_list.rs:1460-1520, 2372-2451`). |
| Order | Painter's order, two lanes per parent scope, plus a **depth buffer**: every draw item gets `zbias += 0.001` in paint order (`draw/src/shader/draw_quad.rs:36`, `d3d11.rs:234-235`). No spatial sort, no R-tree. |
| Layout / UI | "Turtle" layout run inside draw code; widgets re-record their draw list on change. No element tree rebuilt per frame. |

## Mechanisms

### Shader source → backends

- Instance fields, uniforms, varyings and textures are derived from the struct and the DSL object (`platform/script/src/shader_output.rs:383-542`, `platform/src/draw_shader.rs:1006-1389`). Three uniform scopes: pass, draw list (`view_transform, view_clip, view_shift`, `draw_list.rs:1818-1831`), draw call.
- **WebGL2**: per-instance vertex attributes with `vertexAttribDivisor` (`platform/src/os/web/web_gl.js:2072-2096`). All instance floats are packed into `vec4` attributes, `ceil(slots/4)` of them (`platform/script/src/shader_glsl.rs:265-280`), and the JS side rejects `slots * 4 > 255` as an invalid stride (`web_gl.js:1103-1108`). Practical ceiling: 15 × vec4 = 60 floats = 240 B per instance.
- On GL and D3D **every instance field is forwarded to the fragment stage as a varying**, used or not (`shader_glsl.rs:662-681`) — about ten vec4 for text. Metal instead re-fetches the instance in the fragment stage by `instance_id` (`platform/script/src/shader_metal.rs:630-638`).
- Semantics drift per backend and are maintained by hand: `modf` lowers to `fmod` / `mod` / `%`, which differ for negative operands (`shader_backend.rs:1318-1345`).

### Draw lists, batching, retention

- A widget's draw appends its struct's floats to the matching draw item and gets back an **`Area`**: `{draw_list_id, draw_item_id, instance_offset, instance_count, redraw_id}` (`platform/src/area.rs:11-18`, `draw/src/draw_list_2d.rs:573-608`).
- **Merging** (`draw_list.rs:2586-2766`): walk the list's items backward; append to an item when shader, geometry, every dyn uniform, every texture slot and the options match. A non-matching item is a barrier, with one exception — `// Only background lane draws may cross content lane barriers.` (`:2567`). Quads stamp lane 0 of their parent scope, text lane 1 (`draw/src/cx_2d.rs:292-333`). So `bg, text, bg, text…` inside one parent becomes two draw calls, in tree order, with O(1) state. The depth buffer is what makes the cross-lane move safe.
- `begin_many_instances` resolves the draw item once and then appends N instances with no lookup (`draw_list_2d.rs:432-452`) — the inner loop for glyph runs.
- **Retention**: a draw list whose rect did not change and that the draw event does not select returns `Redrawing::no()` and keeps its items (`draw_list_2d.rs:96-147`). Granularity is the draw list plus all its ancestors; a widget in a plain `View` re-records its nearest enclosing list, often the window (`platform/src/event/event.rs:595-630`).
- **Paint-only path**: `DrawVars::update_rect`, `set_instance_on_area` and the animator write floats **in place** into the recorded range, set `instance_dirty` and `paint_dirty`, and no draw code runs (`draw_vars.rs:218-346, 695-740`). Hover animations and caret blink use it.
- Upload: per dirty draw item, the whole vec. D3D11 re-creates the buffer at the exact new size whenever the length changes — "Keep original churn behavior" (`d3d11.rs:2806-2861`). Metal skips the upload when the re-recorded bytes equal the resident copy (`platform/src/os/apple/metal.rs:285-297`).
- Clip and alignment are **patched into already-emitted instances** after recording (`draw/src/turtle.rs:5216-5364`).

### SDF primitives

- `Sdf2d` (`draw/src/shader/sdf.rs`): shapes (`circle`, `box`, `box_all` per-corner, `hexagon`, arcs, polygons), boolean ops incl. `gloop(k)` smooth-min, and `fill / stroke / glow` that accumulate premultiplied colour — one fragment composes many shapes.
- AA is derivative-based, in local logical pixels (`sdf.rs:166-168`):

```
fn antialias(p: vec2) -> float { return 1.0 / length(vec2(length(dFdx(p)), length(dFdy(p)))); }
```

  so one code path holds under rotation, scale and DPI. The ramp lies **inside** the edge (coverage 0 at distance 0), so no quad inflation is needed — at the cost of shapes ~0.7 px smaller and softer than GPUI's ±0.5 px, and a ramp pixel even on a pixel-aligned straight edge.
- **Shadow + fill + border in one instance**: the vertex shader inflates the quad by the shadow radius and offset; the fragment evaluates the shadow only outside the shape (`widgets/src/view_ui.rs:255-303`). The shadow is the same Evan Wallace `erf` code GPUI uses (`sdf.rs:10-68`). No inset shadow.
- Gradients: 2-stop, axis-only, sRGB, with a `random_2d * 0.04` dither (`view_ui.rs:269-283`).
- **No pixel snapping anywhere.** The one DPI device is a pass uniform `dpi_dilate = clamp(2 - dpi_factor, 0, 1)` that shaders add to stroke widths so hairlines survive at 1× (`platform/src/draw_pass.rs:688-694`).

### Clip and scroll

- Clip is per instance in the **vertex** shader, by clamping the corner and recomputing the local position from it (`draw_quad.rs:22-43`):

```
let clipped = clamp( clamp(self.geom.pos * rect_size + rect_pos, self.draw_clip.xy, self.draw_clip.zw)
                     + self.draw_list.view_shift, self.draw_list.view_clip.xy, self.draw_list.view_clip.zw )
```

  That cannot work under rotation: `DrawRotatedText` clips in the fragment shader with `discard` (`draw/src/shader/draw_rotated_text.rs:157-187`). A fully clipped quad degenerates but is still emitted and uploaded — there is no CPU cull.
- **Scroll is a layout offset**: `let origin = origin - layout.scroll;` (`turtle.rs:4017`), so every scroll event re-records every visible instance, from an unsnapped `f64` offset. The list-level `view_shift` / `view_clip` uniforms are honoured by every 2D shader but `ScrollBars` never writes them; an older `draw_scroll` mechanism is commented out (`draw_list.rs:1412-1449`), and the snap is a bare comment with no code (`widgets/src/scroll_bar.rs:407`).

### Text

- **Fonts from bytes only**; no system discovery. `FontDefinition { data, index, weight, variations }`; `weight` drives the `wght` axis (`draw/src/text/loader.rs:141-198`). CJK and emoji families load lazily, on a real glyph miss (`draw_text.rs:3659-3691`).
- **Fallback by shaping**: shape with font 0, find runs of `.notdef`, re-shape exactly that byte range with the next font (`draw/src/text/shaper.rs:296-404`).
- Shaper: rustybuzz, BiDi, LRU of 4096 (`shaper.rs:138-170`). OpenType features exist in the shaper but the only caller passes none (`draw/src/text/font_family.rs:74-84`); `y_offset` is produced and never read (`shaper.rs:473`).
- Layout: logical pixels, floats, never rounded (`draw/src/text/layouter.rs:491-507`). **No runs** — one style per layout, colour in the cache key. Wrapping re-shapes candidate rows from cached words; end-ellipsis only. Hit-testing walks glyph clusters and divides a ligature evenly among its graphemes (`layouter.rs:1150-1367`). Layout cache: LRU with a byte budget that **never evicts entries used this frame** (`layouter.rs:188-208`).
- **Rasterization is SDF, not coverage.** Outlines → unhinted coverage → ESDT distance field, pad 4, radius 8 (`draw/src/text/sdfer.rs:22-58`), at `max(size, 32 px/em)` (`draw/src/text/rasterizer.rs:330, 399`). Every text size up to 32 device px/em shares **one** raster per glyph. A 13 px font at 1× is a 32 px/em SDF minified ~2.4× with bilinear filtering. No hinting, no subpixel variants, no snapping. Fragment (`draw_text.rs:620-697`): a derivative-scaled ramp, then a luma bias of 0.03 (dark text slightly heavier). No gamma table.
- Four kinds share one shader via a per-instance index: SDF, MSDF (generated on a worker, seeded from the SDF), colour PNG strikes (no COLR), and **"slug"** — GPU outline evaluation from RGBA32F curve textures. Slug is the path for *all* outline text on macOS, web and mobile, and gated on Windows/Linux (`draw/src/text/fonts.rs:40-55`); a D3D11 comment records a TDR hazard (`d3d11.rs:3180-3186`). So pixels differ per platform.
- Atlas: one 2048² BGRA texture. **SDF glyphs are packed one per colour channel** — four max-rects packers kept balanced; colour items reserve all four planes (`rasterizer.rs:603-679`). Key `{font, glyph, pixel size, kind}` (`draw/src/text/font_atlas.rs:293-299`). No growth, no eviction: full → clear everything at the next frame and redraw all (`rasterizer.rs:206-209`). Upload is a dirty-rect union (`fonts.rs:359-370`).
- Target `B8G8R8A8_UNORM`, premultiplied source-over (`d3d11.rs:1978, 3713-3716`): gamma-space blending, same as GPUI and Void.

### The code editor

- Virtualised by binary search over cached line y (`code_editor/src/code_editor.rs:829-836`); a **monospace cell grid** — positions are `column × cell_size`, shaped advances are never used.
- **Text is drawn one Unicode scalar per `draw_abs` call** (`code_editor.rs:1661-1677`): ligatures cannot form, and a frame costs ~3000 layout-cache lookups, inside one `begin_many_instances` bracket → one draw call.
- **Selection** (`code_editor/src/draw_selection.rs:5-113`): one quad per visual row carrying the x/width of the rows above and below; the fragment unions three rounded boxes with `gloop(8.0)`, so concave joins come out filleted with no geometry.
- Caret blink is an in-place instance patch. Scroll re-records everything. `Layout::width()` loops every document line per draw (`code_editor/src/layout.rs:30-71`).
- ~8–10 GPU draw calls per frame.

### Frame lifecycle

- Three request channels: re-record a draw list, next-frame animation, **paint-only**. The loop is `Poll` when anything is dirty, else `Wait` (`platform/src/os/windows/windows.rs:463-474`).
- **Passes are never nested at paint time.** Nesting exists at record time only; `compute_pass_repaint_order` sorts "deepest first. A pass's parent is its CONSUMER", and its comment records the bug where a grandchild landed after its consumer (`platform/src/os/cx_shared.rs:135-271`).
- D3D11 present: flip-model swapchain, frame-latency **waitable object** as the frame clock with `SetMaximumFrameLatency(2)`, one timestamp per frame from DXGI statistics, drawing during the modal resize loop with `DwmFlush` (`d3d11.rs:1967-2062, 2134-2173, 2303-2368`). Occluded windows skip painting.
- Device loss: drop every GPU object, re-arm every dirty flag, redraw all, with a fault-injection switch (`windows.rs:685-765`).
- Idle is not free: a 125 Hz signal-poll timer on Windows (`platform/src/os/windows/win32_app.rs:957-961`). `MAKEPAD_TRACE=frames` prints histograms of next-frame gap, present gap and flip lead (`platform/src/frame_trace.rs`).

## Disposition

Reasons as in [GPUI.md](GPUI.md): **N** Neon/host covers it, **W** worse than what Void has or plans, **P** not portable or against "same pixels on every platform".

| Makepad | Disposition | Note |
|---|---|---|
| UNORM target, premultiplied, gamma-space blending | **Confirms** | all three references blend where Void blends |
| `erf` shadow with no render target; local-space SDF with derivative AA under any transform | **Confirms** GPUI.md "SDF under an affine" | |
| Fragment `discard` for clip once rotation is involved | **Confirms** "Clip" | |
| Offscreen passes ordered children-first, never nested at paint time | **Confirms** the hoisting in "The display list" | sokol has the same constraint |
| Tree order, no spatial sort, a handful of draw calls | **Confirms** guardrail 1 | |
| Logical unhinted float layout; fonts from bytes; colour out of the atlas key | **Confirms** | |
| Persistent instance ranges + dirty flag + `Wait` when idle | **Confirms** step 5 — and is the only running example of it | |
| Per-instance attributes + `vertexAttribDivisor` on WebGL2; **255-byte stride ceiling** | **Confirms**, adds a number | the planned 92–128 B UI stride fits |
| Device loss = drop all, re-arm dirty, redraw; fault injection | **Confirms**, take the test switch | |
| **`Area` + paint-only animation**: the animator writes instance fields in place | **Take** | the missing half of "dirty-range upload": hover, focus, caret blink never walk the tree |
| **Lane batching** (backgrounds may cross a content barrier of the same parent) | **Take, adapted** | fallback where the unified UI pipeline cannot absorb a draw (custom shader, second atlas page). Needs the non-overlap flag; Makepad needs a depth buffer for it |
| `begin_many_instances` — resolve the command once, append N | **Take** | inner loop of glyph runs and `TileGroup` |
| Shadow + fill + border in **one instance**, quad inflated by the shadow extent | **Take** | half the instances of GPUI's separate shadow primitive for the common card; keep a standalone shadow mode too |
| Selection as per-row quads with neighbour x/w and a smooth-min union | **Take** | a mode of the UI pipeline; editor-grade selection with no geometry |
| `dpi_dilate` pass uniform | **Take** | hairline compensation inside SDF shaders, where CPU `snap_stroke` cannot reach |
| `clamp(clamp(p, instance clip) + view_shift, view_clip)` — list-level shift applied after the per-instance clip | **Take the formulation** | the shader shape of `Mask.scrollX/Y`. Makepad wrote it and does not use it |
| **SDF text recipe**: 32 px/em ESDT, pad 4 / radius 8, derivative-scaled ramp, luma bias | **Take, for the transformed regime only** | one raster serves every size, so zoom and animation cost nothing. It is not the UI-text path (below) |
| Lazy CJK / emoji families on a real glyph miss | **Take** | the wasm-size answer for guardrail 6 |
| Emoji strikes pre-shrunk into 1.25× size buckets | **Take** | bounded atlas churn under zoom |
| Layout-cache eviction that never evicts this frame's working set | **Take**, if a keyed cache is ever added | |
| Four single-channel planes per RGBA page, balanced allocator | **Consider** at step 2 | 4× glyphs per texture and per bind slot on GLES3, and one page kind for coverage and emoji; costs a per-instance plane selector and rules out an R8 format |
| "Identical bytes → skip upload" | **Take** | cheap guard for re-recorded, unchanged ranges |
| Frame-latency waitable as frame clock, timestamp from DXGI statistics, draw during modal resize, occlusion probe; frame-gap histograms | **N**, with requirements noted | Ion / the host owns pacing; the histograms are the template for void2d's profiler |
| **Minified SDF as UI text** — no hinting, no variants, no snap, no gamma | **W** | nothing lands small text on the pixel grid (inferred from source; not captured). The contrast with GPUI and Ghostty is the argument for the pixel-exact coverage regime |
| "Slug" GPU outlines | **P** | RGBA32F data textures and data-dependent loops on GLES3/WebGL2; TDR hazard; different pixels per platform |
| Single 2048² atlas, flush-all when full; key by pixel dimensions | **W** | pages + ref-counted tiles |
| One GPU buffer per draw call, re-created on any length change | **W** | on sokol this is the 128-buffer-pool defect already found |
| Depth buffer for 2D order; `zbias` from global paint order re-uploads every later call's uniforms | **W** | a depth attachment on every UI pass, against painter's order and "pay for what you use"; interacts badly with alpha AA fringes |
| Inside-only AA ramp; `box` radius doubled | **W** for axis-aligned UI | not CSS / GPUI geometry. Usable as an option under rotation where inflating the quad is awkward |
| No pixel snapping; unsnapped scroll; scroll = re-record | **W** | GPUI's rules stand; neither reference has a cheap scroll |
| No CPU cull of clipped instances | **W** | |
| All instance fields forwarded as varyings | **W** | costly on tile-based GPUs; pass only what the fragment reads |
| Editor text one scalar per call; no runs, no decorations, features unreachable, `y_offset` dropped | **W** | GPUI's shaped-line model stands |
| Runtime shader generation with hand-kept per-backend semantics | **P** | dropped draws until compiled; sokol-shdc validates one GLSL at build time |
| 2-stop axis-only sRGB gradients | **W** | |
| Turtle layout, widgets, animator state machine, script VM, live reload | **N** | |
