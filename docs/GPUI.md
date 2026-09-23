# GPUI — Reference for void2d (2026-09-19, revised 2026-09-20)

[GPUI](https://github.com/zed-industries/zed/tree/main/crates/gpui) is Zed's UI renderer. It is the best-in-class reference for **how a UI primitive should look on the GPU** — rounded boxes, borders, shadows, and above all text — and for **how a frame should be handed to the GPU**. This doc records the comparison, read from source.

The entry point for void2d's decisions — the bar, the conclusions across all references, guardrails and sequencing — is [VOID2D.md](VOID2D.md). This doc is the evidence for the GPUI part: how GPUI works, where void2d stands against it, and the disposition of every item in GPUI's rendering layer. The disposition reasons are VOID2D.md's: **N** Neon or its Void host covers it, **W** GPUI's mechanism is worse than one Void has or plans, **P** not portable or against "same pixels on every platform".

Source: `~/projects/gpui` — a sparse clone of the Zed monorepo (only `crates/gpui*`) at `b961b49`. GPUI paths below are relative to `crates/`; `W:` is `gpui/src/window.rs`. Void paths are relative to `src/` at `7f52e78`; Heaps paths are relative to `~/projects/heaps` at `b9aa6dcb`. Citations were re-checked against those trees on 2026-09-20.

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

Rotate or scale that quad and three things break: the SDF is in the wrong space, 0.5 is no longer half a pixel, and the straight edges need an AA fringe that lies **outside** the quad's geometry and is never rasterized. The shader cannot be ported as-is under a per-node affine; the local-space form is in [VOID2D.md](VOID2D.md) "Primitives".

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
| 3D | Depth, MRT, low-res pass + post + blit (`void3d/renderer.ms` core, `pixelArtRenderer.ms` preset, on the `gpu3d.c` bridge) | No depth buffer anywhere |
| Custom shaders | Own the pipeline | Closed |
| Size | ~6k hand-written lines | ~150k |

### Where GPUI is ahead — concrete void2d gaps

1. **AA depends on MSAA.** Rounded rects, circles and paths are tessellated fans (`void2d/graphics.ms:395-401`, `arcSegs` at `:58`). MSAA 4× is on only for the sokol_app entry (`sokol/bridgeWin.c` `voidRun`); iOS, Android and embed run `sample_count = 1` (`voidPlatformDeviceEnsure` in `bridgeIos.m`, `sokolSetup` in `bridgeAndroid.c`, `bridgeEmbed.m:137`), so every curved edge is aliased on mobile.
2. **Shadows cost render targets, and the blur is wrong.** DropShadow is RT + two blur passes + composite per node (`void2d/render.ms:216-283`). The blur is a fixed 5-fetch/9-tap kernel whose tap spacing is multiplied by the radius (`void2d/shader2d.glsl:81-87`); the 1.3846 / 3.2308 offsets are only valid at a 1-texel step.
3. **GPU calls are issued while walking the tree.** Every flush is a `sg_append_buffer` + pipeline + bindings + two uniform blocks (`void2d/batcher.c:218-251`). Every Label and Graphics node flushes and issues its own draw (`void2d/draw.ms:264-277`, `:307-320`); texture, blend, effect and clip changes also flush. `Rect` binds the white view and `Label` the font view, so box/text/box/text cannot batch.
4. **Per-frame vertex cap.** The dynamic buffer holds 65536 vertices (`void2d/batcher.c:19`, `:85`) and every flush appends into it; past it sokol drops draws silently.
5. **Text positions are integers.** fontstash truncates every glyph origin to a whole pixel and rounds every advance (`deps/fontstash/fontstash.h:1230-1244`), and quantizes size to 0.1 px (`:1314`). Its glyph key is `(codepoint, size, blur)` — there is no room for a subpixel variant. At 12–14 px this visibly distorts spacing; it is exactly what GPUI's variants solve, and it cannot be fixed from outside the library.
6. **Text, the rest.** No shaping (no ligatures — `calt` in code fonts — or complex scripts), no fallback (`fonsAddFallbackFont` exists but nothing calls it; ≤ 16 fonts, `batcher.c:35`), no colour emoji, no gamma/contrast. The bundled stb_truetype is v1.16: `kern` table only, no GPOS (`deps/stb/stb_truetype.h` v1.26 has GPOS and `stbtt_MakeGlyphBitmapSubpixel`). The atlas is expanded R8→RGBA on the CPU (`batcher.c:345-360`) and fully re-uploaded on any new glyph (`:207-216`). Wrapping is `split(" ")` (`void2d/text.ms:19`). Changing a label's text destroys and recreates its GPU buffer (`render.ms:110-111`). No per-glyph x for a caret, no `textWidth`.
7. **Gradients** are per-vertex sRGB lerps (`graphics.ms:41-55`); GPUI's are per-pixel with Oklab (2-stop linear only; Void has radial).
8. **Clip under rotation.** A rotated Mask clips to its AABB via scissor (`render.ms:204`). Culling tests the viewport, not the active clip (`render.ms:191-201`) — a scrolled list lies mostly inside the viewport and outside the clip.
9. **No pixel-snapping rules**: no hairline minimum, fractional box edges, centred text lines on fractional pixels (`text.ms:7`).
10. **Idle cost.** `Scene.present` walks and draws every frame; nothing knows whether the tree changed.

Defects found in void2d while tracing are listed in [VOID2D.md](VOID2D.md) "Known defects".

## Disposition of GPUI's rendering layer

How the taken items are adapted — the display list, the unified UI pipeline, SDF under an affine, the text regimes, clip and scroll — is in [VOID2D.md](VOID2D.md) "Conclusions".

| GPUI | Disposition | Note |
|---|---|---|
| Display list: build → upload once → draw ranges | **Take** | VOID2D.md "Frame shape" |
| Instance buffer growth `max(2×, pow2)`, no shrink, cap, drop-frame-with-error | **Take** | |
| CPU cull of primitives with empty `bounds ∩ mask` | **Take** | cull against the active clip, not only the viewport |
| Rounded-rect SDF, per-corner radii, per-side borders, dashes | **Take, adapted** | re-derived for local space |
| `erf` shadow, drop + inset, own instance | **Take, adapted** | isotropic → rotation is free |
| Per-pixel gradient, sRGB/Oklab; slash + checkerboard patterns; dither | **Take** | keep Void's radial and multi-stop |
| `corner_radii` + `grayscale` on image instances; `ObjectFit` math; animated frames keyed by `frame_index` | **Take** | decoding stays in `assets/` |
| SVG → R8 mask at 2× → tinted sprite (icons) | **Take**, opt-in module | rasterizer: a single-header C one; resvg is Rust |
| Clip by four edge distances | **Take, adapted** | extended to a rotated rect; `discard`, not `vec4(0)` (VOID2D.md "Clip and scroll") |
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
| BoundsTree reordering, per-kind `Vec`s, `BatchIterator` | **W** | VOID2D.md guardrail 1 |
| One pipeline per primitive kind | **W** | creates the box/text flush problem |
| Scene stored twice; replay re-inserts and re-sorts | **W** | |
| 112-byte glyph instance, HSLA converted on the GPU, identity matrix per glyph | **W** | |
| Atlas without padding or eviction | **W** | Void sprites can be transformed; zoom must not leak |
| Scroll = rebuild every visible item | **W** | VOID2D.md "Clip and scroll" |
| Opacity multiplied per primitive only | **W** | Void keeps alpha down the tree **and** group opacity through a target |
| MSAA intermediate-texture path rasterization | **W/P** | VOID2D.md guardrail 4 |
| Platform text systems (DirectWrite / CoreText / swash) | **P** | different pixels per OS; Void owns one rasterizer |
| ClearType / dual-source blending | **P** | VOID2D.md guardrail 7 |
| Storage-buffer instances, `base_instance` ranges | **P** | not in GLES3/WebGL2 (`sokol_gfx.h:238-239`); use per-instance vertex attributes and `vertex_buffer_offsets` |
| Per-tile partial texture upload | **P** | sokol's `sg_update_image` replaces a whole image once per frame; keep a CPU mirror per page and upload dirty pages |
| Three hand-written shader ports | **P** | one GLSL source |
| Taffy, elements, entities, views, arena, actions, keymap, animation | **N** | Neon |
| Hitboxes, dispatch tree, focus, tab stops, IME input handler, cursor styles, tooltips, `uniform_list` / `list`, a11y, frame scheduling, window/platform | **N** | Neon's Void host (and Ion) |
| Layout pixel rounding (`taffy.rs:270-376`) | **N** | Yoga's `pointScaleFactor`, set to the DPI by the host |

## Open

- GPUI facts were read from source at `b961b49`, not benchmarked.
- The Zed editor element (`crates/editor`) is outside the sparse clone: how it uses `paint_layer`, `split_at` and tab expansion was not read.
- Two suspected GPUI bugs were noticed and should not be copied: the swash subpixel offset is divided by `scale_factor` although the scaler is already in device pixels (`cosmic_text_system.rs:506-523`), and the variant computation misplaces glyphs at negative device x (`W:4666-4670`).
