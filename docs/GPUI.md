# GPUI — Reference for void2d, and what to absorb (2026-09-19)

[GPUI](https://github.com/zed-industries/zed/tree/main/crates/gpui) is Zed's UI renderer. It is the best-in-class reference for **how a UI primitive should look on the GPU** — rounded boxes, borders, shadows, text — and for **how a frame should be handed to the GPU**. It is a poor reference for anything else Void does. This doc records the comparison, read from source, and the decision on what void2d takes from it without losing the Heaps model.

Source: `~/projects/gpui` — a sparse clone of the Zed monorepo (only `crates/gpui*`) at `b961b49`. GPUI paths below are relative to `crates/`; Void paths are relative to `src/` at `b07dfe6`. Every citation was re-checked against those two trees.

## What GPUI is

A 2D-only, instanced, SDF UI renderer with a fixed set of eight primitive kinds, drawing **pixel-snapped, axis-aligned geometry in device space**.

| | |
|---|---|
| Backends | Metal (`gpui_apple/src/metal_renderer.rs`), D3D11 + DirectComposition (`gpui_windows/src/directx_renderer.rs`), wgpu → Vulkan/GL on Linux and WebGPU/WebGL2 on the web (`gpui_wgpu/src/wgpu_renderer.rs`). No mobile. |
| Shaders | **Three hand-maintained ports** of the same code: `shaders.metal` (1279), `shaders.hlsl` (1268), `shaders.wgsl` (1362) + WebGL/storage/subpixel fragments. |
| Scene | `gpui/src/scene.rs:41`: a flat display list — one `Vec` per kind (`shadows, quads, paths, underlines, monochrome_sprites, subpixel_sprites, polychrome_sprites, surfaces`) of `#[repr(C)]` POD structs, uploaded as-is as instance data. |
| Frame shape | Build the scene → `finish()` sorts each `Vec` by order → `write_instances` uploads **everything once** (`wgpu_renderer.rs:1542`) → the pass is only draws over instance ranges. No GPU call happens while the element tree is walked. |
| Batching | `order` assigned by an R-tree (`gpui/src/bounds_tree.rs`), **rebuilt from empty every frame**: one more than the max order of overlapping earlier primitives, so non-overlapping primitives share an order and batch across kinds. `BatchIterator` merges the eight sorted streams; within one order, kinds draw in enum order. One instanced 4-vertex strip per batch. |
| Layer hint | `paint_layer` (`window.rs:4359`): the caller asserts "this geometry does not overlap"; everything inside takes the layer's single order and **skips the tree** (`scene.rs:97-101`). |
| Layout / UI | Taffy, element tree rebuilt per frame with retained element state, hitboxes, accesskit, animation. Cached views replay the previous frame's scene ranges (`scene.rs:141`). |
| Extensibility | None: no user shaders, no render targets, no depth, no 3D. Only `paint_quad/path/svg/image/glyph/…`. `paint_surface` (video) is macOS-only. |

### The techniques that make it look good

- **Quad** (`scene.rs:535`): `bounds, content_mask, background, border_color, corner_radii` (per corner), `border_widths` (per side), `border_style {Solid, Dashed}`. **No transform** — and not by omission, see the next section.
- **Rounded-rect SDF** — `quad_sdf_impl` (`shaders.wgsl:372`), per-corner radius by quadrant, 0.5 px analytic AA; fast paths for no-border/no-radius and interior pixels. Varying border widths via `quarter_ellipse_sdf`. Dashes laid out around rounded corners by arc length. Border-only quads are split into four strips on the CPU so the transparent interior is never shaded (`window.rs:4532`).
- **Box shadow** — analytic Gaussian (Evan Wallace): polynomial `erf` (`shaders.wgsl:325`), closed-form along x, 4-sample integration along y (`fs_shadow`, `shaders.wgsl:1000`). Inset shadows supported. A shadow is its own primitive (one instance, no render target), and only ever the shadow of a rounded rect.
- **Background** (`color.rs:779`): solid, **2-stop** linear gradient, slash pattern, checkerboard; interpolated per pixel in sRGB or **Oklab**. No radial.
- **Paths** — lyon tessellation on the CPU; rasterized with **4× MSAA into a full-viewport intermediate texture**, then copied back by bounds. The main render pass is ended and restarted around each path batch (`wgpu_renderer.rs:1459-1494`). Curves get Loop-Blinn analytic AA.
- **Text** — CoreText (macOS), DirectWrite with fallback and COLR/SVG color glyphs (Windows), cosmic-text + swash (Linux/web; browser canvas fallback for emoji on web). Glyphs keyed by `(font, glyph, size, subpixel_variant, scale)`, 4 horizontal subpixel variants (`text_system.rs:49`). Gamma/contrast correction ported from Windows Terminal's `dwrite.hlsl` (`platform.rs:1349`). ClearType via dual-source blending on D3D11/wgpu; **not on Metal** (`metal_renderer.rs:741`: `SubpixelSprites => unreachable!()`). Line-layout cache double-buffered across frames.
- **Atlas** — `etagere` bucketed allocator, 1024² pages growing to max texture size, ref-counted; R8 for monochrome, BGRA8 for color.
- **Images/SVG** — `image` crate incl. animated GIF/WebP; SVG via resvg on the CPU, drawn as a tinted alpha mask. `PolychromeSprite` carries `corner_radii`, which is how rounded images (avatars) are clipped without a clip primitive.
- **Clipping** — axis-aligned `ContentMask` only. The vertex shader emits four edge distances as varyings and the fragment shader discards on any negative (`distance_from_clip_rect`, `shaders.wgsl:192`) — no scissor, no flush, and no `gl_ClipDistance` needed. No rounded clip.

### Why GPUI quads have no transform

The SDF is evaluated in **device pixels**: `fs_quad` takes `input.position.xy` (the fragment coordinate) minus `quad.bounds.origin`, and hard-codes `antialias_threshold = 0.5` on the assumption that one SDF unit is one pixel (`shaders.wgsl:565-600`). `paint_quad` snaps bounds and border widths to device pixels first (`window.rs:4514-4515`, `snap_bounds` at `:3131`), which is why the quad geometry can end exactly at the bounds: straight edges land on pixel boundaries and need no AA; only the corners, which are inside the bounds, do.

Rotate or scale that quad and three things break: the SDF is in the wrong space, 0.5 is no longer half a pixel, and the straight edges need an AA fringe that lies **outside** the quad's geometry and is never rasterized. GPUI's look is a consequence of never transforming; the shader cannot be ported as-is under a per-node affine. See "SDF under an affine" below.

## Void vs GPUI

### Where Void is ahead

| | Void | GPUI |
|---|---|---|
| Shader source | One GLSL file, sokol-shdc fans out to every backend | Three ports kept in sync by hand |
| Mobile | iOS (Metal), Android (GLES3) | None |
| Transform | Full affine (rotation/scale/pivot) on every node (`void2d/render.ms:78-88`) | Only monochrome/subpixel sprites; quads, images, shadows cannot rotate |
| Blend / colour | Alpha, Add, Multiply, Screen, colorMatrix, colorAdd, colorKey, nearest sampling | Premultiplied alpha only |
| Offscreen | Render targets; Blur/Glow/DropShadow filters on any subtree | No render-target API |
| 3D | Depth, MRT, low-res pass + post + blit (`void3d/pass3d.c`) | No depth buffer anywhere |
| Custom shaders | Own the pipeline | Closed |
| Size | ~6k hand-written lines | ~150k |

### Where GPUI is ahead — concrete void2d gaps

1. **AA depends on MSAA.** Rounded rects, circles and paths are tessellated fans (`void2d/graphics.ms:395-401`, `arcSegs` at `:58`). MSAA 4× is on only for the sokol_app entry (`sokol/bridge.c:47`); iOS, Android and embed run `sample_count = 1` (`bridgeIos.m:99`, `bridgeAndroid.c:138`, `bridgeEmbed.m:137`), so every curved edge is aliased on mobile.
2. **Shadows cost render targets, and the blur is wrong.** DropShadow is RT + two blur passes + composite per node (`void2d/render.ms:216-283`). The blur is a fixed 5-fetch/9-tap kernel whose tap spacing is multiplied by the radius (`void2d/shader2d.glsl:81-87`). The 1.3846 / 3.2308 linear-sampling offsets are only valid at a 1-texel step, so every radius other than 1 is both undersampled (ghosting) and incorrectly weighted.
3. **GPU calls are issued while walking the tree.** Every flush is a `sg_append_buffer` + pipeline + bindings + two uniform blocks (`void2d/batcher.c:213-246`). Every Label and Graphics node flushes and issues its own draw (`void2d/draw.ms:264-277`, `:307-320`); texture, blend, effect and clip changes also flush (clip is a scissor, `draw.ms:139`). `Rect` binds the white view and `Label` the font view, so box/text/box/text could not batch even if labels were dynamic. 500 labels ≥ 500 draws.
4. **Per-frame vertex cap.** The dynamic buffer holds 65536 vertices (`void2d/batcher.c:14`, `:80`) and every flush appends into it, so a frame carries ~10.9k dynamic quads before sokol drops draws on append overflow. The cause is append-per-flush into a fixed buffer, not the vertex format.
5. **Text.** fontstash/stb_truetype: no shaping (no ligatures or complex scripts; combining marks misplace — Vietnamese is fine when NFC-precomposed, which covers the whole alphabet), no fallback fonts (≤16 fonts loaded by hand, `batcher.c:30`), no colour emoji, no subpixel positioning, no gamma/contrast. The atlas is expanded R8→RGBA on the CPU (4× memory, `batcher.c:340-355`) and fully re-uploaded on any new glyph (`:202-211`). **Atlas-full is unhandled**: the atlas is a fixed 512² (`:142-143`), nothing in `src/` calls `fonsExpandAtlas`, `fonsResetAtlas` or `fonsSetErrorCallback`, so `fons_resize` / `s_atlasGen` never fire and glyphs that do not fit are dropped silently (fontstash behaviour from memory — `deps/` absent). Wrapping is `split(" ")` (`void2d/text.ms:19`), so CJK does not wrap. Changing a label's text destroys and recreates its GPU buffer (`render.ms:110-111`).
6. **Gradients** are per-vertex sRGB lerps (`graphics.ms:50-55`); GPUI's are per-pixel with Oklab (though only 2-stop linear; Void has radial).
7. **Clip under rotation.** A rotated Mask clips to its AABB via scissor (`render.ms:204`). GPUI has no rotated clip either, but its four-edge-distance technique generalises to one — see below.

## Decision: absorb the techniques and the frame shape, not the UI framework

GPUI's pixel quality lives in fragment-shader math — SDF, `erf`, gamma tables — none of which touches the Heaps model. Its throughput lives in one architectural piece that is equally independent of the UI framework above it: **a flat POD display list between the tree and the GPU, uploaded once**. Both are taken. The `Node2D` tree, painter's order, filters and blend modes stay.

| Absorb | Absorb, adapted | Do not absorb |
|---|---|---|
| Display list: build → upload once → draw ranges | Rounded-rect SDF, per-corner radii, per-side borders, dashes — **re-derived for local space** (below) | Taffy, elements, entities, hitboxes, a11y, animation — Neon's job ([VOID2D.md](VOID2D.md) scope) |
| Analytic `erf` shadow (drop + inset), as its own instance | Clip by edge-distance varyings — extended to a **rotated** rect | BoundsTree reordering (see guardrail 1) |
| Per-pixel gradients, sRGB/Oklab | Cached replay → persistent instance ranges with dirty upload ([SCENE-SCALE.md](SCENE-SCALE.md) "Instances") | One pipeline per primitive kind |
| Glyph atlas: R8, multi-page, partial upload, subpixel variants, gamma/contrast | `paint_layer` → a "children do not overlap" node flag | MSAA intermediate-texture path rasterization |
| `corner_radii` on image instances | Text shaping — compile-time opt-in module | ClearType / dual-source blending |
| | | Three hand-written shader ports |

All absorbed shaders are written once in GLSL for sokol-shdc.

### The display list

`emitNode` stops calling the GPU. It appends POD instances to a CPU stream and records draw commands `(pipeline, views, blend, fx, clip, instance range)`. At `end2d`: one `sg_update_buffer`, then the commands replay as `sg_draw` over ranges. Consequences:

- A state change costs one more draw call, not an upload. A few hundred draws per frame is fine on every target, so scissor clipping and painter's order stop being throughput problems.
- The vertex cap goes: the stream is a growable CPU array and the GPU buffer is reallocated when it is outgrown.
- The renderer's input no longer depends on `Node2D`. `void2d/scene.ms` is still a fat-object tree; the columnar scene in SCENE-SCALE.md does not exist yet. With a display list between them, either can change without the other.
- The immediate-mode face of void2d ([VOID2D.md](VOID2D.md) "two faces") is exactly "append to the list".
- The list can be asserted on in tests with no GPU.

GPUI's cached-view replay has a Void equivalent even though Void is retained: today the tree is re-walked and every quad re-transformed on the CPU each frame (48 floats per quad). With the affine in the instance, a node that did not change has byte-identical instance data; keeping instance ranges persistent and uploading only dirty ranges makes static content cost zero CPU per frame. Draw order is rebuilt only on structural change (`drawOrder` in SCENE-SCALE.md). This, not bytes per quad, is the main win of instancing.

### One UI pipeline, not one per kind

Painter's order plus one pipeline per kind means a flush at every box→text→box alternation — the exact problem GPUI's BoundsTree exists to repair. Void avoids creating it:

- **UI pipeline** — one shader, one instance layout, a per-instance `mode` (box SDF / shadow / glyph / image). The branch is coherent per primitive. The glyph atlas and one image atlas sit in two view slots, and the glyph atlas carries a white texel (the Dear ImGui trick), so a UI subtree in tree order is typically **one draw call** with no reordering.
- **Sprite pipeline** — flat textured shader for sprites, particles, tiles, `Graphics` meshes. Never runs SDF math. **Pay for what you use** holds at the pipeline level: game scenes never touch the UI shader.

### SDF under an affine

What Void must solve that GPUI never did:

1. **Evaluate in local space.** The vertex shader passes the local position (pixels in the node's own frame) as a varying; radii, border widths and the SDF are all in local units.
2. **AA width from the transform.** Half a device pixel expressed in local units: `0.5 / scale` computed in the vertex shader from the affine for uniform scale, `fwidth(d)` otherwise. Heaps does the same for SDF fonts (`h3d/shader/SignedDistanceField.hx`, `autoSmoothing`).
3. **Inflate the quad.** The vertex shader expands each corner outward by ~1 device pixel so the outer AA fringe of straight edges is rasterized under rotation. The fast paths (no border, no radius, interior pixel) stay.
4. **Shadow.** The Gaussian is isotropic, so rotation is free in local space; under non-uniform scale sigma is approximated by the mean scale.

### Clip

Four edge distances as varyings work for any convex quad, so a **rotated Mask clips correctly** with the clip rect's four half-planes supplied per draw command (uniform, not per instance — clip changes are rare and a draw call is now cheap). Nested clips whose intersection is no longer a rectangle fall back to today's scissor AABB for the outer levels. Rounded `overflow: hidden` — common in Neon — is covered for the image case by `corner_radii` on the image instance; a general rounded clip is one more SDF term on the same varyings and is deferred until needed.

### Instance sizes

Today a quad is 6 vertices × 8 floats = **192 B**, re-transformed on the CPU every frame, with no AA of its own. With per-instance attributes (`SG_VERTEXSTEP_PER_INSTANCE`, core in GLES3/WebGL2):

| Instance | Payload | Size |
|---|---|---|
| Sprite pipeline | affine 6 + size 2 + uv 4 + colour 4 (float) | 64 B |
| UI pipeline (single stride for all modes) | affine 6 + size 2, uv-or-radii 4, border widths 4, mode/params 4, gradient/shadow params 4, three colours as `UBYTE4N` | ~92 B packed, ~128 B with float colours |

Glyphs drawn through the UI pipeline pay the UI stride; that is still under half of today's 192 B. The UI layout is ~9 per-instance attributes plus the per-vertex corner, inside the 16-attribute limit of WebGL2 and `SG_MAX_VERTEX_ATTRIBUTES`. Vertex-attribute instancing also avoids GPUI's WebGL2 workaround (instance data packed into an `Rgba32Uint` texture because WebGL2 has no storage buffers, `wgpu_renderer.rs:169`, `shaders_webgl.wgsl`). These sizes are estimates from the planned layouts, not measured; 4-vertex instances should be checked against indexed quads on one Mali and one Adreno device before committing.

## Guardrails — where absorbing GPUI would break the Heaps model

1. **Draw order.** Heaps draws in tree order (`h2d/RenderContext.hx:779` flushes on texture/blend/filter change, same as Void). **Painter's order stays**, and the unified UI pipeline makes it batch. BoundsTree reordering is **not planned**: it repairs a problem the per-kind pipelines would have created, GPUI rebuilds it from empty every frame (natural for an immediate-mode scene, not for a retained tree), and it is O(log n) per primitive against the 1M-node target in [SCENE-SCALE.md](SCENE-SCALE.md). The cheap form of the same idea is kept: a node flag asserting that children do not overlap (GPUI `paint_layer`, Heaps `TileGroup`), inside which draws may be sorted by pipeline/texture freely. Revisit the tree only if measurements of real Neon UI show state-change draws dominating.
2. **Node2D width.** `Node2D` already carries 71 fields (`void2d/node.ms`). Box style (~20 floats) is read only when emitting a box, so it belongs in a side table, not in new columns on every node — the side-table bar in SCENE-SCALE.md. (That doc's `payload` column is a design, not code; until the columnar scene lands the side table is keyed by a field on `Node2D`.)
3. **Filters stay — and get fixed.** Render-target filters on arbitrary subtrees are Heaps semantics and remain; the `erf` shadow covers only rounded rects and is a fast path beside them. The blur itself must be corrected: downsample by 2^k then blur at a 1-texel step, or dual-Kawase; tap spacing is never multiplied by the radius.
4. **Paths: no MSAA intermediate, and no baked fringe.** GPUI's per-path-batch pass break is a full tile store/load on tile-based mobile GPUs. A NanoVG-style fringe baked into the mesh does not work either: NanoVG re-tessellates in device space every frame, while `Graphics` meshes are retained in local space and scaled in the shader, so a baked 1 px fringe becomes 2 px of blur at 2× and aliases at 0.5×. Instead store the edge normal per fringe vertex (the uv slot is free for solid fills) and **extrude in the vertex shader by `1px / scale`**: the mesh stays retained and the fringe is one device pixel at any transform.
5. **MSAA is a knob, not a dependency.** On tile-based GPUs 4× MSAA on the swapchain pass resolves on-tile and is cheap (it is Flutter Impeller's primary AA on mobile); what is expensive is breaking the pass. Expose `sample_count` for iOS/Android instead of hard-coding 1. SDF and the fringe are still required: the embed host owns the framebuffer and its sample count, and analytic coverage is better than four levels.
6. **Text is the only real bloat risk.** Atlas work (R8, pages, partial upload, atlas-full handling, subpixel variants, gamma/contrast) is cheap and goes in by default. Normalising input to NFC covers Vietnamese with no shaper. Shaping is a compile-time opt-in: HarfBuzz would grow the wasm artifacts substantially, and Heaps-style games are served by fontstash bitmap fonts. Candidate shaper: `kb_text_shape` (single header). The glyph layer already emits backend-neutral `quad + UV + atlas` ([VOID2D.md](VOID2D.md)), so swapping the shaper does not touch consumers.
7. **Skip ClearType.** Dual-source blending is not core in GLES3/WebGL2, GPUI does not use it on Metal either, LCD AA is meaningless under rotation, and retina/mobile do not need it. Grayscale + gamma/contrast is the target.

## Sequencing

Each step is measured before and after, the way SCENE-SCALE.md was.

1. **Display list** — record draw commands, one upload per frame, draw ranges; growable stream (removes the 65536-vertex cap). Fix **atlas-full** in the same step: error callback → expand or reset, bump `s_atlasGen`.
2. **Instanced pipelines** — flat sprite pipeline; unified UI pipeline with local-space SDF box (per-corner radii, per-side borders, per-pixel gradient), glyph and image modes, quad inflation, white texel in the glyph atlas. Labels emit glyph instances instead of owning a buffer. Box style in a side table.
3. **`erf` shadow** mode (drop + inset); `corner_radii` on image instances; clip by edge distances incl. rotated Mask.
4. **Text atlas** — R8, multi-page, partial upload, subpixel variants, gamma/contrast; NFC normalisation.
5. **AA for `Graphics`** — vertex-shader fringe; `sample_count` knob on mobile bridges.
6. **Blur** — correct kernel (downsample + 1-texel step).
7. **Persistent instance ranges** — dirty-range upload, draw order rebuilt on structural change only.
8. **Non-overlap node flag** — free sort inside flagged subtrees.
9. **Shaping module**, opt-in.

Bloat/speed budget to check at every step: draw calls and frame time at 10k Box + 10k Label; frame time of a sprite-only scene (must not regress); CPU time of a fully static 100k-node frame after step 7; wasm size delta for each backend.

## Open

- `deps/` was absent on the machine this was written on. Not checked: dual-source blending and storage-buffer support in the vendored `sokol_gfx.h` (neither decision depends on it); the vendored fontstash's exact atlas-full path and whether its stb_truetype reads GPOS kerning (older versions read only the `kern` table, which many modern fonts lack).
- GPUI facts were read from source at `b961b49`, not benchmarked. Instance sizes and the one-draw-call claim for the unified UI pipeline are from planned layouts, not measured.
- Non-uniform scale on SDF boxes and `erf` shadows is approximated; the error has not been characterised.
- Nested rotated clips fall back to scissor AABB for outer levels; whether Neon needs better is unknown.
