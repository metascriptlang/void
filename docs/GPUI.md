# GPUI — Reference for void2d, and what to absorb (2026-09-19, revised 2026-09-20)

[GPUI](https://github.com/zed-industries/zed/tree/main/crates/gpui) is Zed's UI renderer. It is the best-in-class reference for **how a UI primitive should look on the GPU** — rounded boxes, borders, shadows, and above all text — and for **how a frame should be handed to the GPU**. This doc records the comparison, read from source, and the decision on what void2d takes from it without losing the Heaps model.

**The bar (2026-09-20).** Heaps is a game engine. Void is a rendering engine, and void2d must carry application-UI rendering when Void is a Neon backend: concretely, render a code editor like Zed — fine font control, high-quality antialiasing, fast and smooth — while keeping the interface and feel of Heaps h2d. Every decision below is judged against "a 13 px code font at 1× and 1.5× DPI looks and scrolls like Zed", not against HUD needs.

**The rule.** void2d takes **everything in GPUI's rendering layer**, except where one of three reasons applies:

- **N** — Neon or its Void host already covers it (component model, layout, events, focus, lists, a11y). Void renders; Neon + Void is the combination.
- **W** — GPUI's mechanism is worse than an alternative Void has, or exists to repair a problem Void does not have.
- **P** — it is not portable to sokol_gfx / GLES3 / WebGL2, or it contradicts "same pixels on every platform" ([VOID2D.md](VOID2D.md)).

Source: `~/projects/gpui` — a sparse clone of the Zed monorepo (only `crates/gpui*`) at `b961b49`. GPUI paths below are relative to `crates/`; `W:` is `gpui/src/window.rs`. Void paths are relative to `src/` at `45d88e0`; Heaps paths are relative to `~/projects/heaps` at `b9aa6dcb`. Citations were re-checked against those trees on 2026-09-20.

## What GPUI is

A 2D-only, instanced, SDF UI renderer with a fixed set of eight primitive kinds, drawing **pixel-snapped, axis-aligned geometry in device space**.

| | |
|---|---|
| Backends | Metal (`gpui_apple/src/metal_renderer.rs`), D3D11 + DirectComposition (`gpui_windows/src/directx_renderer.rs`), wgpu → Vulkan/GL on Linux and WebGPU/WebGL2 on the web (`gpui_wgpu/src/wgpu_renderer.rs`). No mobile. |
| Shaders | **Three hand-maintained ports** of the same code: `shaders.metal`, `shaders.hlsl`, `shaders.wgsl` + WebGL/storage/subpixel fragments. They have drifted: gradients differ between WGSL and HLSL, and only HLSL dithers (`shaders.hlsl:395-402`). |
| Scene | `gpui/src/scene.rs:41`: a flat display list — one `Vec` per kind (`shadows, quads, paths, underlines, monochrome_sprites, subpixel_sprites, polychrome_sprites, surfaces`) of `#[repr(C)]` POD structs, uploaded as-is as instance data. |
| Frame shape | Build the scene → `finish()` sorts each `Vec` by order → `write_instances` uploads **everything once**, one range per kind (`wgpu_renderer.rs:1542-1579`) → the pass is only draws over instance ranges. No GPU call happens while the element tree is walked. |
| Batching | `order` assigned by an R-tree (`gpui/src/bounds_tree.rs`), **rebuilt from empty every frame**. `BatchIterator` merges the eight sorted streams; a batch breaks at every order boundary where another kind interleaves and at every atlas-texture change (`scene.rs:298-462`). One instanced 4-vertex strip per batch. |
| Layer hint | `paint_layer` (`W:4354-4377`): the caller asserts "this geometry does not overlap"; everything inside takes one order and skips the tree (`scene.rs:75-101`). Its only callers are the two text-line painters (`text_system/line.rs:546, 808`): one tree insert per line, not per glyph. |
| Layout / UI | Taffy rebuilt every frame (`W:3348`), element tree rebuilt per frame in a bump arena, hitboxes, accesskit. Cached views replay the previous frame's paint operations (`scene.rs:141-149`). |
| Extensibility | None: no user shaders, no render targets, no depth, no 3D. |

### Primitive techniques

- **Quad** (`scene.rs:535`): `bounds, content_mask, background, border_color, corner_radii` (per corner), `border_widths` (per side), `border_style {Solid, Dashed}`. **No transform** — see "Why GPUI quads have no transform".
- **Rounded-rect SDF** — `quad_sdf_impl` (`shaders.wgsl:372`), per-corner radius by quadrant, 0.5 px analytic AA; fast paths for no-border/no-radius and interior pixels. Varying border widths via `quarter_ellipse_sdf`. Dashes laid out around rounded corners by arc length. Border-only quads are emitted as four copies with narrowed content masks so the transparent interior is never shaded (`W:4532`).
- **Box shadow** — analytic Gaussian (Evan Wallace): polynomial `erf` (`shaders.wgsl:325`), closed-form along x, 4-sample integration along y (`fs_shadow`, `shaders.wgsl:1000`). Inset shadows supported. One instance, no render target; only ever the shadow of a rounded rect.
- **Background** (`color.rs:779`): solid, **2-stop** linear gradient, slash pattern, checkerboard; interpolated per pixel in sRGB or **Oklab**. No radial. HLSL adds ±2/255 triangular-noise dither against banding.
- **Paths** — lyon tessellation on the CPU; rasterized with MSAA into a **full-surface intermediate texture**, then composited. The main pass is ended and re-opened around each path batch (`wgpu_renderer.rs:1459-1494`).
- **Images/SVG** — `image` crate incl. animated GIF/WebP (atlas key `{image_id, frame_index}`); `ObjectFit` computed on the CPU; `PolychromeSprite` carries `corner_radii` and a `grayscale` flag. SVG via resvg on the CPU at 2× the snapped device size, kept as an **R8 alpha mask** and drawn tinted (`svg_renderer.rs:231-262`, `W:4821-4866`) — this is the icon path.
- **Clipping** — axis-aligned `ContentMask` only, as four edge distances per vertex. D3D11 and Metal use hardware clip distances (`shaders.hlsl:1154`); WGSL has none and returns `vec4(0)` from the fragment shader (`shaders.wgsl:566-569`). No scissor, no flush, no rounded clip. Primitives whose `bounds ∩ mask` is empty are dropped on the CPU (`scene.rs:89-95`).
- **Atlas** — `etagere` bucketed allocator; **fixed 1024² pages, a new page when full**; a single item larger than a page gets a page of its own size (`wgpu_atlas.rs:153-189`). R8 for monochrome, BGRA8/RGBA8 for colour. Per-tile upload into the sub-rectangle. **No padding** (`padding: 0`, `:355`) — safe only because sprites are drawn 1:1 at integer device positions. **No eviction**: glyph and SVG tiles live until device loss; the key includes `font_size` and `scale_factor`, so zooming accumulates tiles forever (only images are dropped, explicitly, `W:4997-5008`).

### Why GPUI quads have no transform

The SDF is evaluated in **device pixels**: `fs_quad` takes `input.position.xy` (the fragment coordinate) minus `quad.bounds.origin`, and hard-codes `antialias_threshold = 0.5` on the assumption that one SDF unit is one pixel (`shaders.wgsl:565-600`). `paint_quad` snaps bounds and border widths to device pixels first (`W:4513-4525`), which is why the quad geometry can end exactly at the bounds: straight edges land on pixel boundaries and need no AA; only the corners, which are inside the bounds, do.

Rotate or scale that quad and three things break: the SDF is in the wrong space, 0.5 is no longer half a pixel, and the straight edges need an AA fringe that lies **outside** the quad's geometry and is never rasterized. The shader cannot be ported as-is under a per-node affine. See "SDF under an affine".

### The text path — where Zed's look actually comes from

1. **Layout is logical and unhinted; only rasterization scales.** `layout_line(text, font_size, runs)` returns glyph ids with float positions in logical pixels (`text_system/line_layout.rs:19-57`). No advance is rounded anywhere. DirectWrite lays out at `pixelsPerDip = 1.0` (`direct_write.rs:1457-1489`); cosmic-text uses `Hinting::Disabled` for layout (`cosmic_text_system.rs:758`) while swash rasterizes with `.hint(true)` at `size × scale_factor` (`:522-523`).
2. **Subpixel positioning** (`W:4659-4697`). The glyph origin is scaled to device space, then quantized: x to **1/4 device pixel**, y to a **whole device pixel** (`SUBPIXEL_VARIANTS_X = 4`, `_Y = 1`, `text_system.rs:49-52`). The fraction selects one of four pre-rasterized variants; the integer part places the sprite. The sprite is drawn **1:1 on the device-pixel grid**, so the atlas is sampled texel-exact. Baseline snapping is a consequence of `_Y = 1`.
3. **Atlas key** `RenderGlyphParams { font_id, glyph_id, font_size, subpixel_variant, scale_factor, is_emoji, subpixel_rendering, dilation }` (`text_system.rs:1264-1288`). Colour is not in the key: one coverage mask serves every colour.
4. **Gamma/contrast.** The targets are UNORM, not sRGB (`directx_renderer.rs:27`, `wgpu_renderer.rs:350-359`), so blending happens on gamma-encoded values. Text compensates per fragment with `apply_contrast_and_gamma_correction(sample, color, enhanced_contrast, gamma_ratios)` — contrast enhancement scaled by the text colour's brightness, then a polynomial alpha correction (`shaders.wgsl:34-78`, identical in `alpha_correction.hlsl`). `gamma_ratios` is a 13-row table indexed by gamma 1.0–2.2 (`gpui/src/platform.rs:1344-1378`, from Windows Terminal); defaults gamma 1.8, grayscale contrast 1.0 (`wgpu_renderer.rs:2163-2198`).
5. **Font control.** `Font { family, features: [(tag, u32)], fallbacks: [family], weight: f32, style }` → cached `FontId` (`text_system.rs:1291-1309, 329-351`). Features are arbitrary OpenType tags; "ligatures off" is `calt = 0` (`font_features.rs:12-14`). No variable-font axes, no stretch, no letter-spacing. User fallback chain resolved per grapheme by charmap coverage — ASCII always primary (`cosmic_text_system.rs:1045-1139`).
6. **Runs and decorations.** `TextRun { len, font, color, background_color, underline, strikethrough }` (`text_system.rs:1227-1241`). A colour change splits the shaping run, so ligatures never span two colours (`:886-935`). Backgrounds are one quad per contiguous run, painted before glyphs (`line.rs:790-937`). Underline/strikethrough are their own primitive: origin rounded to a device pixel, thickness `snap_stroke` (min 1 dp), wavy = distance to a sine in the fragment shader (`shaders.wgsl:1149-1211`).
7. **Wrap, truncation and hit-testing run over shaped glyphs.** `WrapBoundary { run_ix, glyph_ix }` indexes the unwrapped glyph list; a width change never re-shapes (`line_layout.rs:193-295`). Break rule: after a space, or at any non-word char — the CJK path (`line_wrapper.rs:68-79`); hanging indent; truncation Start/Middle/End (`:141-446`). `x_for_index` / `index_for_x` read glyph positions (`line_layout.rs:61-129`). `force_width` snaps base glyphs to a monospace cell grid and leaves combining marks attached (`:893-921`). `ShapedLine::split_at` cuts a shaped line without re-shaping (`line.rs:193-380`).
8. **Line-layout cache**: keyed `(text, font_size, runs, wrap_width, force_width)`, two generations swapped per frame; a hit allocates nothing (`line_layout.rs:457-719`). It exists because the element tree is rebuilt every frame.
9. **Colour emoji** take a separate path: whole-pixel origin, BGRA tile, `PolychromeSprite`, no gamma correction (`W:4752-4804`).
10. **Subpixel (ClearType) AA** needs dual-source blending and an opaque window; off on Metal and WebGL2.

Weak spots in GPUI's text path: 112-byte glyph instances carrying HSLA and a `TransformationMatrix` that is always identity for glyphs (`scene.rs:711-719`, `W:4708`); two hash lookups, a `RwLock` and a `Mutex` per glyph per frame; rasterization is synchronous on first paint with no warm-up; underline position ignores the font's own metric (`text_system.rs:58-61`); tabs are not handled at all.

### The frame lifecycle

- One decision point per vsync tick (`W:1700-1838`): **dirty → draw + present; not dirty but must present → present the retained scene; otherwise nothing**. `draw` clears `dirty`; `present` clears `needs_present`.
- `InputRateTracker` (`W:1257-1299`): ≥ 6 invalidating inputs within 100 ms sustains presentation for 1 s so a VRR display does not underclock mid-gesture.
- Throttle: an inactive window is capped at 30 fps (`gpui/src/platform.rs:2359`).
- N input events → one draw: events only set dirty.
- `WindowProfiler` (`gpui/src/profiler.rs:889-910`): histograms of `dirty_to_present`, `draw_duration`, `input_latency`, `events_per_frame`. The debug overlay is inserted straight into the scene, bypassing invalidation (`debug_overlay.rs:1-3`). **No renderer counts draw calls, batches or instances.**
- Instance buffer: grows to `max(2×, next_pow2)`, capped at 256 MiB, never shrinks; past the cap the frame is dropped with an error (`wgpu_renderer.rs:1930-1970, 1395-1420`).
- Device loss: atlas cleared, caches bypassed, next draw forced.
- **Scroll has no cheap path.** `Scene` has no translation; `with_element_offset` only changes where elements compute bounds (`W:4006-4008`); the cached-view key contains absolute `bounds` (`view.rs:484-490`), so scrolling is a cache miss and every visible item is rebuilt, laid out and painted each frame. What survives a scroll: element state, shaped lines, atlas tiles.
- Replay is not a memcpy: every replayed primitive is cloned, re-inserted through `BoundsTree::insert`, and the whole scene is re-sorted (`scene.rs:141-163`). Each primitive is stored twice.

### Pixel snapping rules

`gpui/src/util.rs:128-161`, `W:3131-3174`:

- `snap_bounds`: each edge rounded independently (half toward zero), far ≥ near.
- `snap_stroke`: 0 stays 0, anything else rounds with a **minimum of 1 device pixel** — hairlines never vanish. Border widths per side use it.
- `cover_bounds`: floor the near edge, ceil the far edge — used for content masks, layer bounds, shadow bounds.
- Scroll/element offsets are snapped to a device pixel before being added (`W:5097-5110`).
- Corner radii, blur radii and paths are scaled only.

## Void vs GPUI

### Where Void is ahead

| | Void | GPUI |
|---|---|---|
| Shader source | One GLSL file, sokol-shdc fans out to every backend | Three ports kept in sync by hand, already diverged |
| Mobile | iOS (Metal), Android (GLES3) | None |
| Transform | Full affine (rotation/scale/pivot) on every node (`void2d/render.ms:78-88`) | Only sprites carry a matrix, used by SVG only |
| Blend / colour | Premultiplied; Alpha, Add, Multiply, Screen, None; colorMatrix, colorAdd, colorKey; nearest sampling | One blend |
| Offscreen | Render targets; filters on any subtree; group opacity is possible | No render-target API; opacity is multiplied into each primitive, so overlapping children of a translucent parent double-blend (`W:4038-4054`) |
| Retention | Retained tree: a node that did not change need not be rebuilt | Tree, layout and scene rebuilt every frame |
| 3D | Depth, MRT, low-res pass + post + blit (`void3d/pass3d.c`) | No depth buffer anywhere |
| Custom shaders | Own the pipeline | Closed |
| Size | ~6k hand-written lines | ~150k |

### Where GPUI is ahead — concrete void2d gaps

1. **AA depends on MSAA.** Rounded rects, circles and paths are tessellated fans (`void2d/graphics.ms:395-401`, `arcSegs` at `:58`). MSAA 4× is on only for the sokol_app entry (`sokol/bridge.c:47`); iOS, Android and embed run `sample_count = 1` (`bridgeIos.m:99`, `bridgeAndroid.c:138`, `bridgeEmbed.m:137`), so every curved edge is aliased on mobile.
2. **Shadows cost render targets, and the blur is wrong.** DropShadow is RT + two blur passes + composite per node (`void2d/render.ms:216-283`). The blur is a fixed 5-fetch/9-tap kernel whose tap spacing is multiplied by the radius (`void2d/shader2d.glsl:81-87`); the 1.3846 / 3.2308 offsets are only valid at a 1-texel step.
3. **GPU calls are issued while walking the tree.** Every flush is a `sg_append_buffer` + pipeline + bindings + two uniform blocks (`void2d/batcher.c:218-251`). Every Label and Graphics node flushes and issues its own draw (`void2d/draw.ms:264-277`, `:307-320`); texture, blend, effect and clip changes also flush. `Rect` binds the white view and `Label` the font view, so box/text/box/text cannot batch.
4. **Per-frame vertex cap.** The dynamic buffer holds 65536 vertices (`void2d/batcher.c:19`, `:85`) and every flush appends into it; past it sokol drops draws silently.
5. **Text positions are integers.** fontstash truncates every glyph origin to a whole pixel and rounds every advance (`deps/fontstash/fontstash.h:1230-1244`), and quantizes size to 0.1 px (`:1314`). Its glyph key is `(codepoint, size, blur)` — there is no room for a subpixel variant. At 12–14 px this visibly distorts spacing; it is exactly what GPUI's variants solve, and it cannot be fixed from outside the library.
6. **Text, the rest.** No shaping (no ligatures — `calt` in code fonts — or complex scripts), no fallback (`fonsAddFallbackFont` exists but nothing calls it; ≤ 16 fonts, `batcher.c:35`), no colour emoji, no gamma/contrast. The bundled stb_truetype is v1.16: `kern` table only, no GPOS (`deps/stb/stb_truetype.h` v1.26 has GPOS and `stbtt_MakeGlyphBitmapSubpixel`). The atlas is expanded R8→RGBA on the CPU (`batcher.c:345-360`) and fully re-uploaded on any new glyph (`:207-216`). Wrapping is `split(" ")` (`void2d/text.ms:19`). Changing a label's text destroys and recreates its GPU buffer (`render.ms:110-111`). No per-glyph x for a caret, no `textWidth`.
7. **Gradients** are per-vertex sRGB lerps (`graphics.ms:41-55`); GPUI's are per-pixel with Oklab (2-stop linear only; Void has radial).
8. **Clip under rotation.** A rotated Mask clips to its AABB via scissor (`render.ms:204`). Culling tests the viewport, not the active clip (`render.ms:191-201`) — a scrolled list lies mostly inside the viewport and outside the clip.
9. **No pixel-snapping rules**: no hairline minimum, fractional box edges, centred text lines on fractional pixels (`text.ms:7`).
10. **Idle cost.** `Scene.present` walks and draws every frame; nothing knows whether the tree changed.

### Defects found while tracing (2026-09-20)

- **Atlas-full drops glyphs silently.** The atlas is a fixed 512² (`batcher.c:147-148`); fontstash reports `FONS_ATLAS_FULL` through `handleError` (`fontstash.h:1131`) and retries once, but `batcher.c` never sets a handler, so `fons__getGlyph` returns NULL. `fons_resize` would also leak the old `sg_image` and view (`batcher.c:61-65`).
- **At most ~126 Labels/Graphics render.** Each owns an `sg_buffer`; sokol's default `buffer_pool_size` is 128 (`sokol_gfx.h:6590`) and `sg_make_buffer` fails silently past it. Measured with `examples/bench2d.ms`: 10 000 labels requested, 126 drawn.
- **Node filters nest a pass inside the swapchain pass.** `drawFiltered` calls `beginRT` while `Scene.present` is between `beginPass` and `endPass` (`render.ms:216-283`, `scene.ms:88-102`); `sg_begin_pass` asserts `!in_pass`. Its nested `begin2d` also drops pending vertices and resets clip/effect state (`draw.ms:110-125`).
- **Filter semantics differ from h2d**: only children go into the target, not the node itself; alpha is applied twice under Blur (`render.ms:245, 273`); the target is screen-space at dpi 1 (`:239`), so it is half-resolution on HiDPI and does not rotate with the node; children are re-synced twice per frame.
- **Fractional DPI puts every glyph off-grid.** `present` truncates the logical size: `begin2d(wf as int32, hf as int32, dpi)` (`scene.ms:89`). A 1000 px framebuffer at 1.5 gives 666, not 666.67; the projection becomes 1.5015×.
- **Samplers are hard-wired REPEAT** (`batcher.c:136-143`) — bilinear bleed at atlas tile edges. h2d defaults to clamp.

## Decision

### Inventory of GPUI's rendering layer

| GPUI | Disposition | Note |
|---|---|---|
| Display list: build → upload once → draw ranges | **Take** | "The display list" below |
| Instance buffer growth `max(2×, pow2)`, no shrink, cap, drop-frame-with-error | **Take** | |
| CPU cull of primitives with empty `bounds ∩ mask` | **Take** | cull against the active clip, not only the viewport |
| Rounded-rect SDF, per-corner radii, per-side borders, dashes | **Take, adapted** | re-derived for local space |
| `erf` shadow, drop + inset, own instance | **Take, adapted** | isotropic → rotation is free |
| Per-pixel gradient, sRGB/Oklab; slash + checkerboard patterns; dither | **Take** | keep Void's radial and multi-stop |
| `corner_radii` + `grayscale` on image instances; `ObjectFit` math; animated frames keyed by `frame_index` | **Take** | decoding stays in `assets/` |
| SVG → R8 mask at 2× → tinted sprite (icons) | **Take**, opt-in module | rasterizer: a single-header C one; resvg is Rust |
| Clip by four edge distances | **Take, adapted** | extended to a rotated rect; `discard`, not `vec4(0)` (see "Clip") |
| Pixel-snapping rules (`snap_bounds`, `snap_stroke` min 1 dp, `cover_bounds`, snapped offsets) | **Take** | applied when the world transform is axis-aligned |
| Glyph layer: logical unhinted layout, 4 x-variants, baseline snap, atlas key, 1:1 texel-exact sprites | **Take** | replaces fontstash |
| Gamma/contrast correction function + `gamma_ratios` table | **Take** | one GLSL function; same UNORM/gamma-space blending as Void |
| Atlas: R8 + RGBA kinds, fixed 1024² pages, new page when full, oversized item → own page | **Take, adapted** | 1 px gutter; dirty-page upload; eviction |
| `Font { family, weight, style, features, fallbacks }` → `FontId`; fonts from bytes; per-grapheme fallback by coverage | **Take** | |
| `TextRun`, run backgrounds, underline / strikethrough / wavy primitive | **Take** | |
| Wrap boundaries, truncation, `x_for_index` / `index_for_x`, `force_width`, `split_at` — all over shaped glyphs | **Take** | text layout is rendering: native Neon hosts get it from the OS, the Void host gets it from Void |
| Shaping with OpenType features (ligatures, `calt`), colour-change splits the run | **Take**, compile-time module | shaper candidate `kb_text_shape` |
| Colour emoji as RGBA sprites | **Take**, with the rasterizer decision | needs COLR/CBDT, which stb_truetype lacks |
| Dirty → draw+present / present-only / nothing; retained list re-presented | **Take** (renderer half) | `Scene` reports whether it changed and can replay its last list; scheduling is the host's |
| Frame profiler: `dirty_to_present`, draw time, input latency; overlay drawn outside invalidation | **Take**, plus draw-call / instance / upload-byte counters GPUI lacks | |
| Device-loss path: drop atlas + GPU resources, force a full redraw | **Take** | generalises `s_atlasGen` |
| `paint_layer` non-overlap hint | **Take, adapted** | as h2d `TileGroup` + a node flag |
| Cached-view replay | **Take, adapted** | persistent instance ranges with dirty upload ([SCENE-SCALE.md](SCENE-SCALE.md)) |
| Line-layout cache, two generations | **W** | exists because GPUI rebuilds its tree; in Void the node holds its layout. A keyed cache only if measure and paint shape the same string twice |
| BoundsTree reordering, per-kind `Vec`s, `BatchIterator` | **W** | guardrail 1 |
| One pipeline per primitive kind | **W** | creates the box/text flush problem |
| Scene stored twice; replay re-inserts and re-sorts | **W** | |
| 112-byte glyph instance, HSLA converted on the GPU, identity matrix per glyph | **W** | |
| Atlas without padding or eviction | **W** | Void sprites can be transformed; zoom must not leak |
| Scroll = rebuild every visible item | **W** | "Scroll" below |
| Opacity multiplied per primitive only | **W** | Void keeps alpha down the tree **and** group opacity through a target |
| MSAA intermediate-texture path rasterization | **W/P** | guardrail 4 |
| Platform text systems (DirectWrite / CoreText / swash) | **P** | different pixels per OS; Void owns one rasterizer |
| ClearType / dual-source blending | **P** | guardrail 7 |
| Storage-buffer instances, `base_instance` ranges | **P** | not in GLES3/WebGL2 (`sokol_gfx.h:238-239`); use per-instance vertex attributes and `vertex_buffer_offsets` |
| Per-tile partial texture upload | **P** | sokol's `sg_update_image` replaces a whole image once per frame; keep a CPU mirror per page and upload dirty pages |
| Three hand-written shader ports | **P** | one GLSL source |
| Taffy, elements, entities, views, arena, actions, keymap, animation | **N** | Neon |
| Hitboxes, dispatch tree, focus, tab stops, IME input handler, cursor styles, tooltips, `uniform_list` / `list`, a11y, frame scheduling, window/platform | **N** | Neon's Void host (and Ion) |
| Layout pixel rounding (`taffy.rs:270-376`) | **N** | Yoga's `pointScaleFactor`, set to the DPI by the host |

### What the Neon host needs from void2d

The boundary is not "nothing above pixels". These are rendering services the host cannot compute itself:

- **Text measurement** for the Yoga measure callback: width/height of a run list under a width constraint, from the same layout the node will paint.
- **Text geometry**: x for a byte index, index for an x, line boxes — caret, selection, IME candidate position.
- **Hit geometry**: `globalToLocal`, world bounds, clip-aware containment. Dispatch order and event semantics stay in the host.
- **"Did anything change?"** from `Scene`, so the host can skip a frame; and a re-present of the last list.
- **Frame timings and counters.**

Neon's `Style` already names what the host must be able to express and today drops (`neon/src/macros/style/fields.ms:40-56`): `borderWidth/Color/Radius`, `boxShadow`, `fontFamily/Weight/Style`, `textDecorationLine`, `overflow`, `transform`, `zIndex`.

### The display list

`emitNode` stops calling the GPU. It appends POD instances to a CPU stream and records draw commands `(pipeline, views, blend, fx, clip, instance range)`. At `end2d`: one upload, then the commands replay as `sg_draw` over ranges. Consequences:

- A state change costs one more draw call, not an upload. A few hundred draws per frame is fine on every target, so scissor clipping and painter's order stop being throughput problems.
- The vertex cap goes: the stream is a growable CPU array and the GPU buffer is reallocated when it is outgrown.
- **Offscreen passes are hoisted.** One command list per target; filter and blur passes run before the swapchain pass in the order they completed. `Heaps` can open a target lazily mid-walk because its API has no pass objects; sokol cannot (`sg_begin_pass` asserts `!in_pass`).
- Labels emit glyph quads into the stream instead of owning a buffer — this also removes the 128-buffer cap.
- An immediate bracket opened more than once per frame uses `sg_append_buffer` (returns an offset), not `sg_update_buffer` (once per frame).
- The renderer's input no longer depends on `Node2D`; the columnar scene in SCENE-SCALE.md can replace the fat-object tree without touching it.
- The immediate-mode face of void2d ([VOID2D.md](VOID2D.md) "two faces") is exactly "append to the list".
- The list can be asserted on in tests with no GPU, and re-presented without walking the tree.

With the affine in the instance, a node that did not change has byte-identical instance data; keeping instance ranges persistent and uploading only dirty ranges makes static content cost zero CPU per frame. Draw order is rebuilt only on structural change (`drawOrder` in SCENE-SCALE.md).

### One UI pipeline, not one per kind

Painter's order plus one pipeline per kind means a flush at every box→text→box alternation — the exact problem GPUI's BoundsTree exists to repair. Void avoids creating it:

- **UI pipeline** — one shader, one instance layout, a per-instance `mode` (box SDF / shadow / glyph / image / underline). The glyph atlas and one image atlas sit in two view slots, and the glyph atlas carries a white texel (the Dear ImGui trick), so a UI subtree in tree order is typically **one draw call** with no reordering.
- **Sprite pipeline** — flat textured shader for sprites, particles, tiles, `Graphics` meshes. Never runs SDF math. **Pay for what you use** holds at the pipeline level: game scenes never touch the UI shader.

### SDF under an affine

1. **Evaluate in local space.** The vertex shader passes the local position as a varying; radii, border widths and the SDF are all in local units.
2. **AA width from the transform.** Half a device pixel in local units: `0.5 / scale` from the affine for uniform scale, `fwidth(d)` otherwise. Heaps does the same for SDF fonts (`h3d/shader/SignedDistanceField.hx:40`, `autoSmoothing`).
3. **Inflate the quad** by ~1 device pixel so the outer AA fringe of straight edges is rasterized under rotation. The fast paths stay.
4. **Shadow.** The Gaussian is isotropic, so rotation is free; under non-uniform scale sigma is approximated by the mean scale.
5. **When the world transform is axis-aligned**, apply GPUI's snapping rules on the CPU first. Then straight edges land on pixel boundaries and the result is GPUI's, pixel for pixel; the fringe only matters once a node rotates or scales.

### Text

**fontstash goes.** Integer origins, rounded advances and a key with no variant are its design, not a setting. Its replacement is a glyph layer owned by void2d, first on `deps/stb/stb_truetype.h` v1.26 (GPOS kerning, `stbtt_MakeGlyphBitmapSubpixel`) — no new dependency.

- **Interface stays h2d's**: `Font`, `Text` with `text / font / textColor / letterSpacing / lineSpacing / maxWidth / textAlign`, `textWidth / textHeight / calcTextWidth / splitText`. Added on top: `Font` carries `weight, style, features, fallbacks`; a `Text` takes runs (`TextRun`); per-glyph x is queryable.
- **Layout** at the logical size, float positions, never rounded. The node holds its shaped layout; wrap boundaries, truncation and hit-testing index into it, so a width change never re-shapes.
- **Two regimes, chosen per node at sync from the world matrix.**
  - *Pixel-exact* — the transform is a translation plus the DPI/view scale. Rasterize at `size × scale`; snap the run's origin to a device pixel; quantize glyph x to 1/4 device pixel and y to a whole one; draw 1:1. This is GPUI's text.
  - *Transformed* — any other affine (game text, animation). Bilinear sampling of the nearest rasterized size; the 1 px atlas gutter makes this safe. SDF fonts remain the answer for world-space text ([VOID2D.md](VOID2D.md) "Text design").
- **Scroll.** With the run's origin snapped to a device pixel, each glyph's variant depends only on its position inside the run: it is computed once at layout and survives any snapped translation. Scrolling is then `Mask.scrollX/Y` — the h2d idiom (`h2d/Mask.hx:70-125`) — snapped to device pixels: no re-layout, no re-rasterization, no variant churn. GPUI cannot do this; a retained tree can.
- **Atlas**: R8 pages for coverage, RGBA pages for colour glyphs and images; 1024² pages, a new page when full; a CPU mirror per page, dirty pages uploaded once per frame; 1 px gutter; tiles ref-counted by live layouts so zooming does not leak. The white texel lives in page 0.
- **Gamma/contrast**: GPUI's function, ported once to GLSL, in the glyph mode of the UI pipeline. Parameters are uniforms, defaults gamma 1.8 / contrast 1.0.
- **Decorations**: run backgrounds and underline/strikethrough are instances of the same pipeline, thickness through `snap_stroke`.
- **Shaper** — compile-time opt-in module (candidate `kb_text_shape`, single header). Without it: cmap + GPOS kerning, NFC-normalised input (covers Vietnamese), fallback by coverage. With it: GSUB features, ligatures, complex scripts. The glyph layer's output (`glyph id, x, y, byte index`) is the same either way.
- **Rasterizer — open decision.** stb_truetype is unhinted. On HiDPI that is what macOS does and is sufficient. At 1× and 13 px it will be softer than Zed on Windows (DirectWrite) or Linux (swash, hinted); matching that needs FreeType light auto-hint, which also brings COLR/CBDT emoji and variable fonts, at a real size cost on wasm. Decide from captures of the same text beside Zed at 1× and 1.5×, behind a rasterizer interface that makes the swap local.

### Clip

Four edge distances as varyings work for any convex quad, so a **rotated Mask clips correctly** with the clip rect's four half-planes supplied per draw command (uniform, not per instance — clip changes are rare and a draw call is now cheap). The fragment shader **discards**: returning transparent, as GPUI's WGSL does, is wrong under `BlendMode.None` and `Multiply`. Nested clips whose intersection is no longer a rectangle fall back to the scissor AABB for the outer levels. Rounded `overflow: hidden` is covered for the image case by `corner_radii` on the image instance; a general rounded clip is one more SDF term on the same varyings and is deferred until needed.

### Instance sizes

Today a quad is 6 vertices × 8 floats = **192 B**, re-transformed on the CPU every frame, with no AA of its own. With per-instance attributes (`SG_VERTEXSTEP_PER_INSTANCE`, core in GLES3/WebGL2):

| Instance | Payload | Size |
|---|---|---|
| Sprite pipeline | affine 6 + size 2 + uv 4 + colour 4 (float) | 64 B |
| UI pipeline (single stride for all modes) | affine 6 + size 2, uv-or-radii 4, border widths 4, mode/params 4, gradient/shadow params 4, three colours as `UBYTE4N` | ~92 B packed, ~128 B with float colours |

Glyphs drawn through the UI pipeline pay the UI stride; that is still under half of today's 192 B and under GPUI's 112 B. The UI layout is ~9 per-instance attributes plus the per-vertex corner, inside the 16-attribute limit of WebGL2 and `SG_MAX_VERTEX_ATTRIBUTES`. Instance ranges are addressed with `vertex_buffer_offsets`, since `base_instance` is unavailable on GLES3. These sizes are estimates from the planned layouts, not measured; 4-vertex instances should be checked against indexed quads on one Mali and one Adreno device before committing.

## The Heaps side

### Keep, and still add, to stay h2d

Kept as-is: radians, S·R·T then parent, alpha multiplied down the tree, colour/blend/effects not inherited, array-order painter's drawing, filter as a node property, Mask as a node, `getBounds`, `localToGlobal/globalToLocal`.

Missing from void2d today:

- `parent`, `remove()`, reparent-on-add with a cycle guard, `getChildAt / getChildIndex / numChildren`, `name` (`h2d/Object.hx:411-443` vs `void2d/node.ms:133-137`, where one node can sit under two parents). A reconciler host needs `parent` anyway.
- **`TileGroup`** — a retained multi-quad node on one texture (`h2d/TileGroup.hx:562-718`); `Text` is built on it (`h2d/Text.hx:187-189`). It maps onto a persistent instance range and is the h2d-native form of the non-overlap hint.
- **`Tile.dx/dy`** with `center()` / `setCenterRatio()` (`h2d/Tile.hx:26-30, 166-175`). Today's node `pivot` is applied for Rect/Sprite/Anim, ignored by ScaleGrid, Label and Graphics, and used by Mask (`render.ms:42-56, 192-204`).
- `Mask.scrollX/Y` — the scroll mechanism above.
- The `Text` metric surface and `Align` enum; `lineSpacing` in pixels (void2d's is a multiplier, `text.ms:49`).
- `smooth` as a tri-state with a scene default; `tileWrap`, with clamp as the default sampler.
- Filter semantics (`h2d/Object.hx:896-956`): the node itself goes into the target, alpha applied once, target in object-local space through a filter matrix instead of re-syncing the subtree, bounds clipped to the viewport, a frame-linear target pool (`h3d/impl/TextureCache.hx`), clip state saved and cleared per target.
- `localToGlobal` after a mutation and before `present` returns last frame's matrix (`node.ms:174-180`); h2d calls `syncPos()` first (`Object.hx:359`).
- `ScaleMode.Zoom` / `AutoZoom` mean something different from h2d's (`scene.ms:65-78` vs `h2d/Scene.hx:415-427`).

### Do not copy from h2d

- **Its whole font pipeline**: offline or canvas-baked atlases with a fixed charset (`hxd/res/FontBuilder.hx:26-146`, JS only), one texture page (`hxd/fmt/bfnt/FontParser.hx:10`), **Int metrics** for advance and kerning (`:68-73`), accent-stripping as "fallback" (`hxd/Charset.hx:53-72`), one sub-font per Text, per-code-unit iteration (`Text.hx:455`). Keep the interface, replace everything under it.
- Rebuilding a whole `Text` on any change (`Text.hx:299-303`) and O(n) re-measurement for caret and selection every frame (`h2d/TextInput.hx:792-793`).
- No analytic AA: `Graphics` is tessellation only and engine MSAA defaults to 0 (`h3d/Engine.hx:73`). Rounded, bordered panels are 9-slice bitmaps (`h2d/Flow.hx:355-359`).
- Render-target drop shadows as the way to shadow a panel (`h2d/filter/DropShadow.hx:42-54`): two targets plus blur per box per frame.
- Ignoring DPI (`displayScale` has no reader) and nearest sampling by default (`h2d/RenderContext.hx:52`).
- The two-corner rotated mask (`h2d/Mask.hx:26-43`) — void2d's four-corner AABB is already more correct.
- Scrolling by mutating child positions, which re-syncs the subtree (`Flow.hx:728-733`, `Mask.hx:109-125`). void2d's variant — the camera baked into every world matrix, so a camera move re-multiplies the tree (`scene.ms:91-99`) — is the same mistake; in h2d the camera is one uniform (`RenderContext.hx:275-283`).
- One draw per Bitmap: h2d's default path does **not** batch — `BUFFERING` is a compile flag, off by default (`RenderContext.hx:24`); throughput comes from user-chosen `TileGroup`/`SpriteBatch`. That does not survive a reconciler that emits thousands of small nodes.

## Guardrails — where absorbing GPUI would break the Heaps model

1. **Draw order.** Heaps draws in tree order; **painter's order stays**, and the unified UI pipeline makes it batch. BoundsTree reordering is **not planned**: it repairs a problem the per-kind pipelines would have created, GPUI rebuilds it from empty every frame (natural for an immediate-mode scene, not for a retained tree), and it is O(log n) per primitive against the 1M-node target in [SCENE-SCALE.md](SCENE-SCALE.md). The cheap form of the same idea is kept: `TileGroup`, and a node flag asserting that children do not overlap, inside which draws may be sorted by pipeline/texture freely. Revisit only if measurements of real Neon UI show state-change draws dominating.
2. **Node2D width.** `Node2D` already carries 71 fields (`void2d/node.ms`). Box style (~20 floats) and text runs are read only when emitting, so they belong in side tables, not in new columns on every node — the side-table bar in SCENE-SCALE.md.
3. **Filters stay — and get fixed.** Render-target filters on arbitrary subtrees are Heaps semantics and remain; the `erf` shadow covers only rounded rects and is a fast path beside them. The blur must be corrected: downsample by 2^k then blur at a 1-texel step, or dual-Kawase; tap spacing is never multiplied by the radius.
4. **Paths: no MSAA intermediate, and no baked fringe.** GPUI's per-path-batch pass break is a full tile store/load on tile-based mobile GPUs. A NanoVG-style fringe baked into the mesh does not work either: `Graphics` meshes are retained in local space and scaled in the shader, so a baked 1 px fringe becomes 2 px of blur at 2× and aliases at 0.5×. Instead store the edge normal per fringe vertex and **extrude in the vertex shader by `1px / scale`**.
5. **MSAA is a knob, not a dependency.** On tile-based GPUs 4× MSAA on the swapchain pass resolves on-tile and is cheap; what is expensive is breaking the pass. Expose `sample_count` for iOS/Android instead of hard-coding 1. SDF and the fringe are still required: the embed host owns the framebuffer and its sample count, and analytic coverage is better than four levels.
6. **Text is where the weight goes, so it is modular.** The glyph layer (layout, variants, atlas, gamma) is small and goes in by default. The shaper, a hinting rasterizer, colour emoji and the SVG rasterizer are compile-time modules: a game build pays for none of them, an editor build takes all of them. Measure the wasm delta of each.
7. **Skip ClearType.** Dual-source blending is not core in GLES3/WebGL2, GPUI does not use it on Metal either, LCD AA is meaningless under rotation, and HiDPI does not need it. Grayscale + gamma/contrast is the target.
8. **Pay for what you use.** Snapping, the pixel-exact text regime and the UI pipeline engage only for nodes that use them; a sprite-only scene must not regress at any step.

## Sequencing

Each step is measured before and after, the way SCENE-SCALE.md was. Baseline (release, D3D11, 2026-09-20, `examples/bench2d.ms`): UI scene of 10 000 cards + labels — `present` 4.5 ms CPU, 253 draws, **126 labels actually drawn**; 10 000 sprites — 1.7 ms, 1 draw.

1. **Display list** — record draw commands, one upload per bracket, draw ranges; growable stream; per-target command lists with offscreen passes hoisted; Labels emit quads into the stream. With it: **atlas-full** handled (error callback → expand, reset at the next frame start past the maximum; font view resolved at replay; `fons_resize` leak), **filters** brought to h2d semantics, the **fractional-DPI truncation**, and **clamp** samplers (its own commit — it changes edge pixels).
2. **Glyph layer** — replaces fontstash: logical float layout on stb_truetype v1.26, four x-variants and baseline snap, pixel-exact vs transformed regime, R8 pages with gutter, dirty-page upload, gamma/contrast; `Font` with weight/style/fallbacks, fonts from bytes; text metric surface and per-glyph x. Captured beside Zed at 1× and 1.5× → the rasterizer decision.
3. **Instanced pipelines** — flat sprite pipeline; unified UI pipeline with local-space SDF box (per-corner radii, per-side borders, dashes, per-pixel gradient, patterns, dither), glyph, image and underline modes, quad inflation, white texel; snapping rules for axis-aligned nodes; box style in a side table; culling against the active clip.
4. **Text runs** — `TextRun`, run backgrounds, underline / strikethrough / wavy; wrap boundaries with the CJK rule, truncation, `force_width`, `split_at`.
5. **Persistent instance ranges** — `TileGroup`, dirty-range upload, draw order rebuilt on structural change only; `Mask.scrollX/Y` with snapped offsets; `Scene` change flag and re-present; `parent` and the missing `Object` surface.
6. **`erf` shadow** (drop + inset); `corner_radii` / `grayscale` / `ObjectFit` on images; clip by edge distances incl. rotated Mask.
7. **Shaping module** (`kb_text_shape`), OpenType features, ligatures; colour emoji and the hinting rasterizer if step 2's captures call for them.
8. **AA for `Graphics`** — vertex-shader fringe; `sample_count` knob on mobile bridges. **Blur** — correct kernel.
9. **SVG mask module**; animated image frames; non-overlap node flag; frame profiler and counters; device-loss path.

Budget checked at every step: draw calls and `present` time at 10k Box + 10k Label; frame time of a sprite-only scene (must not regress); CPU time of a fully static 100k-node frame and of a scrolling 200-line text view after step 5; atlas bytes after a zoom sweep; wasm size delta per backend and per module.

## Open

- **Rasterizer**: stb_truetype only, or FreeType as a module — decided from step 2's captures.
- GPUI facts were read from source at `b961b49`, not benchmarked. Instance sizes and the one-draw-call claim for the unified UI pipeline are from planned layouts, not measured.
- Non-uniform scale on SDF boxes and `erf` shadows is approximated; the error has not been characterised.
- Nested rotated clips fall back to scissor AABB for outer levels; whether Neon needs better is unknown.
- System font discovery (an editor user expects installed fonts) is host work; void2d takes bytes. Who owns it — Ion or the Neon host — is undecided.
- The Zed editor element (`crates/editor`) is outside the sparse clone: how it uses `paint_layer`, `split_at` and tab expansion was not read.
- Two suspected GPUI bugs were noticed and should not be copied: the swash subpixel offset is divided by `scale_factor` although the scaler is already in device pixels (`cosmic_text_system.rs:506-523`), and the variant computation misplaces glyphs at negative device x (`W:4666-4670`).
