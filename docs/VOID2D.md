# void2d — Unified 2D / UI Render Layer

Void's 2D layer: draw the **same pixels on every platform** (Metal / D3D11 / GL / WebGPU / WebGL2) through one MetaScript codebase. This is the layer that makes Neon's UI rendering "special" — instead of binding to per-OS native widgets, an opted-in app can render its UI through Void and get identical output everywhere.

**This doc is the entry point.** It holds the conclusions. The evidence lives in four reference docs, each read from source with `file:line` citations:

| Doc | Role |
|---|---|
| [HEAPS.md](HEAPS.md) | **The model.** Heaps `h2d`: the interface and semantics void2d keeps. |
| [GPUI.md](GPUI.md) | **Rendering reference 1.** Zed's renderer: the primitive look, the text path, the frame shape. The full inventory of what is taken and why not the rest. |
| [MAKEPAD.md](MAKEPAD.md) | **Rendering reference 2.** GPUI's model under Void's constraints: own shader fan-out, own text stack, web and mobile. |
| [GHOSTTY.md](GHOSTTY.md) | **Rendering reference 3.** Dense text only: font stack, atlas, blend space, frame discipline. |

Scale and scene storage: [SCENE-SCALE.md](SCENE-SCALE.md).

## Where it sits

```
Neon (parent)            component model: View, Text, Flexbox, events, state, diffing
  │   React-Native style; picks a backend per platform
  ├── native widgets      iOS UIKit · Android · Browser DOM          ← Neon-default
  └── Void backend        unified pixels on every platform           ← opt-in, "special"
         │
   Neon reconcile +       Layer A: diffs JSX → Host ops (neon/src/render/reconcile.ms).
   Void Host adapter      voidHost() maps Host ops → Node2D field mutations.
         │                Like R3F (react-reconciler drives THREE.Object3D) — NOT a
                          second reconciler; the adapter is ~50 lines (see neon mockHost).
   ┌─────┴───────────────────────────────────┐
 void2d (this layer)                        void3d (camera/mesh/material)   ← opt-in
   Node2D tree + quad batcher                       │
         │                                          │
         └──────────── Void GPU bridge ─────────────┘   = oryol "Gfx" tier  ✅ DONE
                              │   src/sokol/{bridge,gpu}
                       sokol_gfx (floooh)  ← the load-bearing cross-platform dependency
```

> **Full 3-layer model** (A reconcile / B paint / C GPU) and who owns B+C per platform — native = OS, Void = owned: see [`~/metascript/neon/docs/RENDER-LAYERS.md`](../../neon/docs/RENDER-LAYERS.md). Void = Layers B+C; Neon = Layer A; they meet only at the Host interface.

## Two faces of void2d (load-bearing)

1. **Immediate quad batcher** — thin over the GPU bridge: accumulate textured/colored quads CPU-side, flush as few draw calls. For HUD / games that just draw each frame.
2. **Retained `Node2D` tree** — `Node2D` = transform + props + children. This is the **host the JSX/Solid reconciler binds to** (R3F maps `<mesh>` → a retained `THREE.Object3D`; Solid-on-Void maps JSX → a retained `Node2D`). Each frame, walk the tree → emit batcher calls.

Both required from day one: face 1 ships HUD/game now; face 2 is what the reconciler (`createNode` / `setProp` / `appendChild`) will drive later. A pure immediate-mode 2D layer would have no host for the JSX layer to reconcile onto. With the display list below, face 1 becomes "append to the list" and face 2 "a tree that appends to the list".

## The bar (2026-09-20)

Heaps is a game engine. Void is a rendering engine, and void2d must carry **application-UI rendering** when Void is a Neon backend — concretely, render a code editor like Zed: fine font control, high-quality antialiasing, fast and smooth — while staying recognisably h2d in interface and feel. Decisions are judged against "a 13 px code font at 1× and 1.5× DPI looks and scrolls like Zed", not against HUD needs.

**The rule.** void2d keeps the **h2d model** (retained tree, painter's order, an affine on every node, render-target filters, blend modes) and takes **everything in the rendering layer of its references**, except where one of three reasons applies:

- **N** — Neon or its Void host already covers it (component model, layout, events, focus, lists, a11y). Void renders; Neon + Void is the combination.
- **W** — the reference's mechanism is worse than one Void has or plans, or repairs a problem Void does not have.
- **P** — not portable to sokol_gfx / GLES3 / WebGL2, or against "same pixels on every platform".

Every item of each reference carries one of these in its doc's disposition table.

## Conclusions

Each line names who supports it: **G** GPUI, **M** Makepad, **Gh** Ghostty, **H** Heaps.

### Frame shape

- **A flat POD display list between the tree and the GPU**: record → one upload → draw ranges. No GPU call while the tree is walked. (G, M, Gh all do this.) A state change costs a draw call, not an upload; a few hundred draws per frame is fine, so painter's order and scissor stop being throughput problems.
- **Offscreen passes are hoisted**: one command list per target, children before consumers, never nested at replay. sokol asserts `!in_pass`; Makepad orders "deepest first" and records the bug it had when it did not (M). Heaps opens targets lazily mid-walk only because its API has no pass objects (H).
- **One growing instance buffer**, `max(2×, pow2)`, no shrink, a cap, and a dropped frame with an error past it (G). One GPU buffer per draw call is the defect Makepad carries and the 128-buffer-pool bug void2d has today.
- **Persistent instance ranges with dirty upload.** A node that did not change has byte-identical instance data. Makepad is the running proof: retained draw lists, and an **in-place paint-only patch** — hover, focus and caret blink write instance floats and never walk the tree (M). Skip an upload when the bytes are identical (M).
- **Dirty → draw + present; else present the retained list or do nothing** (G, M, Gh). `Scene` reports whether it changed; scheduling belongs to the host.
- **Append N instances with the command resolved once** — the inner loop of a glyph run and of `TileGroup` (M `begin_many_instances`).
- One GLSL source through sokol-shdc. All three references maintain ports or a generator by hand, and all three have drifted (G gradients and dither, Gh cursor colour, M `modf`).

### Order and batching

- **Painter's order stays**; no spatial reordering (H, M). GPUI's BoundsTree repairs the box/text alternation that its own per-kind pipelines create.
- **One unified UI pipeline** — one shader, one instance layout, a per-instance `mode` (box / shadow / glyph / image / underline / selection) — beside **one flat sprite pipeline** that never runs SDF math. With a white texel in the glyph atlas, a UI subtree in tree order is about one draw call.
- Where a draw cannot join that pipeline (custom shader, second atlas page), the fallback is Makepad's **lanes** — backgrounds may cross a content barrier of the same parent — guarded by an explicit "children do not overlap" flag rather than Makepad's depth buffer. `TileGroup` is the h2d-native form of the same assertion.

### Primitives

- **Rounded-rect SDF evaluated in local space**, AA width from the transform (`0.5 / scale`, `fwidth` otherwise), quad inflated by ~1 device pixel. GPUI's SDF is in device space and cannot rotate; Makepad's derivative-based one proves the local-space form under rotation, scale and DPI (G, M).
- **`erf` box shadow**, drop and inset, no render target (G, M). For the common card, **shadow + fill + border in one instance** with the quad inflated by the shadow extent (M); a standalone shadow mode stays.
- Per-pixel gradients, sRGB and Oklab, with dither (G); Void's radial and multi-stop stay.
- **Pixel snapping when the world transform is axis-aligned** (G): each edge rounded independently; strokes and borders `0 → 0, else ≥ 1 device px`; masks floor/ceil outward; offsets snapped. Two additions: **complementary rounding** for fractional splits — `min = size − round((1−f)·size)`, `max = round(f·size)` (Gh) — and a **`dpi_dilate` uniform** for hairlines drawn inside SDF shaders, where CPU snapping cannot reach (M).
- Images: `corner_radii`, `grayscale`, `ObjectFit`, animated frames (G). SVG → R8 mask → tinted sprite, as a module (G).
- `Graphics` AA by a vertex-shader fringe; never an MSAA intermediate, never a baked fringe.

### Clip and scroll

- **Clip by four edge distances with `discard`**, so a rotated Mask clips correctly (G adapted; M falls back to `discard` exactly when rotation appears). Cull on the CPU against the **active clip**, not only the viewport.
- **Scroll is a snapped translation, not a rebuild.** With a text run's origin on a device pixel, each glyph's subpixel variant depends only on its position inside the run, so it survives any snapped translation. Scrolling is `Mask.scrollX/Y` — the h2d idiom — applied as a list-level shift after the per-instance clip, the formulation Makepad wrote and never used: `clamp(clamp(p, clip) + shift, viewClip)`. **None of the three references has a cheap scroll**: GPUI rebuilds every visible item, Makepad re-records, Ghostty re-emits rows. A retained tree is what makes this possible.

### Text

- **fontstash goes.** It truncates glyph origins, rounds advances and has no room for a variant in its key. void2d owns a glyph layer, first on `deps/stb/stb_truetype.h` v1.26.
- **Interface stays h2d's** (`Font`, `Text`, `textWidth`, `calcTextWidth`, `splitText`, `letterSpacing`, `lineSpacing`, `maxWidth`, `textAlign`); underneath, nothing of h2d's font pipeline survives (H: baked atlases, Int metrics, one page).
- **Layout is logical, unhinted, float, never rounded** (G, M). The node holds its shaped layout; wrap, truncation and hit-testing index into it (G).
- **Two regimes, chosen per node from the world matrix.**
  - *Pixel-exact* (translation + DPI scale) — coverage bitmaps at `size × scale`, x quantized to 1/4 device pixel in four variants, baseline on a whole pixel, drawn 1:1 texel-exact (G; Gh is the one-phase special case). Makepad is the counter-example to avoid: at 13 px / 1× it draws a 32 px/em SDF minified ~2.4× with bilinear filtering, no snap and no gamma correction — it has no mechanism for pixel-grid crispness (inferred from source, not captured).
  - *Transformed* (any other affine) — an **SDF atlas**: one ~32 px/em distance field per glyph serves every size, derivative-scaled ramp, luma bias (M recipe; `stbtt_GetGlyphSDF` exists). Zoom and animation cost nothing and leak nothing. This is also the door to world-space text in void3d.
- **Gamma/contrast**: GPUI's function and table, ported once. All three references blend in gamma space on a UNORM target, as Void does. Ghostty's bg-aware `linear-corrected` is an alternative tied to linear blending and needs the destination colour; it is an opt-in only for text that declares a solid background.
- **Fonts**: `Font { family, weight, style, features, fallbacks }` from bytes (G, M). The collection model is Ghostty's: ordered faces per style, deferred faces, explicit-vs-fallback presentation, a codepoint → face map that caches misses, whole-grapheme selection, **fallback size harmonisation**, synthetic bold/italic, lazy CJK/emoji families (Gh, M). System font discovery is host work.
- **Runs and decorations**: `TextRun { len, font, color, background, underline, strikethrough }`; a style change splits the shaping run, so a ligature is never two-tone (G, Gh). Backgrounds, underline, strikethrough and wavy are instances of the UI pipeline; thickness and position from the font's `post` / `OS/2` metrics with broken-table fallbacks (Gh), snapped.
- **Caret and selection are their own instances**, never part of a text range, so a blink dirties nothing else (Gh, M). Selection is per-row quads unioned by smooth-min (M).
- **Atlas**: coverage pages and colour pages, 1024², a new page when full (G); 1 px gutter; a CPU mirror per page, dirty pages uploaded once per frame (sokol replaces whole images); ref-counted tiles; **a repack never moves a live tile** (Gh). Four single-channel planes per RGBA page (M) is weighed at step 2.
- **Shaper** — compile-time module (candidate `kb_text_shape`): GSUB features, ligatures, complex scripts; "break shaping at index" as an input (Gh). Without it: cmap, GPOS kerning, NFC input, fallback by coverage.
- **Rasterizer — open.** stb_truetype is unhinted: what macOS and Ghostty-on-macOS ship, and sufficient on HiDPI. Ghostty ships FreeType **light hinting** everywhere else; Makepad is unhinted and unsnapped. Constraint if FreeType comes: hinting only in the pixel-exact regime, and the outline is shifted *before* hinting. Decided from captures beside Zed at 1× and 1.5×.
- No ClearType: dual-source blending is not in GLES3/WebGL2 and none of the references uses it on all platforms.

### What the Neon host needs from void2d

The boundary is not "nothing above pixels". These are rendering services the host cannot compute itself:

- **Text measurement** for the Yoga measure callback, from the same layout the node will paint. Native Neon hosts get text layout from the OS; the Void host gets it from Void.
- **Text geometry**: x for a byte index, index for an x, line boxes — caret, selection, IME candidate position.
- **Hit geometry**: `globalToLocal`, world bounds, clip-aware containment. Dispatch order and event semantics stay in the host.
- **"Did anything change?"** from `Scene`, and a re-present of the last list.
- **Frame timings and counters** (draw calls, instances, upload bytes — GPUI counts none of them).
- Host-facing requirements seen in the references: a synchronous draw during live resize, release of GPU resources when occluded, warm-up of pipelines and fonts off the first frame, a device-loss path (drop all, re-arm dirty, redraw) with a fault-injection switch (M, Gh).

Neon's `Style` already names what the host must express and today drops (`neon/src/macros/style/fields.ms:40-56`): `borderWidth/Color/Radius`, `boxShadow`, `fontFamily/Weight/Style`, `textDecorationLine`, `overflow`, `transform`, `zIndex`.

### Instance sizes

Today a quad is 6 vertices × 8 floats = **192 B**, re-transformed on the CPU every frame, with no AA of its own. With per-instance attributes (`SG_VERTEXSTEP_PER_INSTANCE`, core in GLES3/WebGL2):

| Instance | Payload | Size |
|---|---|---|
| Sprite pipeline | affine 6 + size 2 + uv 4 + colour 4 (float) | 64 B |
| UI pipeline (single stride for all modes) | affine 6 + size 2, uv-or-radii 4, border widths 4, mode/params 4, gradient/shadow params 4, three colours as `UBYTE4N` | ~92 B packed, ~128 B with float colours |

For scale: GPUI's glyph instance is 112 B, Makepad's ~116 B, Ghostty's 32 B (integer grid coordinates — not reachable for general UI). Ceilings: 16 vertex attributes, and a **255-byte stride on WebGL2** (M). Ranges are addressed with `vertex_buffer_offsets`; `base_instance` does not exist on GLES3. Only what the fragment stage reads is passed as a varying (Makepad forwards every field, costly on tile-based GPUs). Sizes are estimates from planned layouts; 4-vertex instances should be checked against indexed quads on one Mali and one Adreno device before committing.

## Known defects in void2d (2026-09-20)

- **Atlas-full drops glyphs silently**: a fixed 512² atlas (`void2d/batcher.c:147-148`) and no `FONS_ATLAS_FULL` handler; `fons_resize` would leak the old image and view (`:61-65`).
- **At most ~126 Labels/Graphics render**: each owns an `sg_buffer` and sokol's default pool is 128. Measured with `examples/bench2d.ms`.
- **Node filters nest a pass inside the swapchain pass** (`void2d/render.ms:216-283`, `scene.ms:88-102`); the nested `begin2d` also drops pending vertices and state.
- **Filter semantics differ from h2d**: only children enter the target; alpha applied twice under Blur; the target is screen-space at dpi 1; children re-synced twice per frame. The blur kernel multiplies tap spacing by the radius (`shader2d.glsl:81-87`).
- **Fractional DPI puts every glyph off-grid**: `begin2d(wf as int32, hf as int32, dpi)` (`scene.ms:89`).
- **Samplers are hard-wired REPEAT** (`batcher.c:136-143`).
- The h2d surface still missing — `parent`, `TileGroup`, `Tile.dx/dy`, `Mask.scrollX/Y`, text metrics — is listed in [HEAPS.md](HEAPS.md).

## Guardrails

1. **Draw order.** Painter's order stays, and the unified UI pipeline makes it batch. BoundsTree reordering is not planned: GPUI rebuilds it from empty every frame, and it is O(log n) per primitive against the 1M-node target in [SCENE-SCALE.md](SCENE-SCALE.md). The cheap form is kept: `TileGroup`, and a node flag asserting that children do not overlap. No depth buffer for 2D order. Revisit only if measurements of real Neon UI show state-change draws dominating.
2. **Node2D width.** `Node2D` carries 71 fields. Box style and text runs are read only when emitting, so they live in side tables — the side-table bar in SCENE-SCALE.md.
3. **Filters stay — and get fixed.** Render-target filters on arbitrary subtrees are h2d semantics; the `erf` shadow is a fast path beside them. The blur is corrected: downsample by 2^k then blur at a 1-texel step, or dual-Kawase.
4. **Paths: no MSAA intermediate, no baked fringe.** A pass break per path batch is a full tile store/load on mobile GPUs; a baked fringe scales with the node. Store the edge normal per fringe vertex and extrude in the vertex shader by `1px / scale`.
5. **MSAA is a knob, not a dependency.** Expose `sample_count` for iOS/Android instead of hard-coding 1. Analytic coverage is still required: the embed host owns the framebuffer and its sample count.
6. **Text is where the weight goes, so it is modular.** The glyph layer goes in by default. The shaper, a hinting rasterizer, colour emoji, the SDF text path, procedural sprite glyphs and the SVG rasterizer are compile-time modules; CJK and emoji families load on a real miss. A game build pays for none of them. Measure the wasm delta of each.
7. **No ClearType.**
8. **Pay for what you use.** Snapping, the pixel-exact text regime and the UI pipeline engage only for nodes that use them; a sprite-only scene must not regress at any step.
9. **Same pixels on every platform.** No OS text system, no per-platform text path (Makepad's slug on macOS/web, SDF on Windows), no runtime shader generation.

## Sequencing

Each step is measured before and after, the way SCENE-SCALE.md was. Baseline (release, D3D11, 2026-09-20, `examples/bench2d.ms`): UI scene of 10 000 cards + labels — `present` 4.5 ms CPU, 253 draws, **126 labels actually drawn**; 10 000 sprites — 1.7 ms, 1 draw.

1. **Display list** — record draw commands, one upload per bracket, draw ranges; growable stream; per-target command lists with offscreen passes hoisted; Labels emit quads into the stream, command resolved once per run. With it: **atlas-full** handled, **filters** brought to h2d semantics, the **fractional-DPI truncation**, and **clamp** samplers (its own commit — it changes edge pixels).
2. **Glyph layer** — replaces fontstash: logical float layout on stb_truetype v1.26, four x-variants and baseline snap, the pixel-exact regime, coverage pages with gutter and dirty-page upload, gamma/contrast; `Font` with weight/style/fallbacks from bytes, the font collection model with size harmonisation, decoration metrics from the font; text metric surface and per-glyph x. Captured beside Zed at 1× and 1.5× → the rasterizer decision.
3. **Instanced pipelines** — flat sprite pipeline; unified UI pipeline with local-space SDF box (per-corner radii, per-side borders, dashes, gradients, patterns, dither), shadow-in-instance, glyph, image and underline modes, quad inflation, white texel; snapping rules incl. complementary rounding and `dpi_dilate`; box style in a side table; culling against the active clip.
4. **Text runs** — `TextRun`, run backgrounds, underline / strikethrough / wavy; wrap boundaries with the CJK rule, truncation, `force_width`, `split_at`; caret and selection instances, selection mode.
5. **Persistent instance ranges** — `TileGroup`, dirty-range upload, in-place paint-only patch, draw order rebuilt on structural change only; `Mask.scrollX/Y` with snapped offsets; `Scene` change flag and re-present; `parent` and the missing `Object` surface.
6. **`erf` shadow** standalone (drop + inset); `corner_radii` / `grayscale` / `ObjectFit` on images; clip by edge distances incl. rotated Mask.
7. **Shaping module** (`kb_text_shape`), OpenType features, ligatures, shaping breaks; colour emoji, variable axes and the hinting rasterizer if step 2's captures call for them.
8. **SDF text** for the transformed regime. **AA for `Graphics`** — vertex-shader fringe; `sample_count` knob on mobile bridges. **Blur** — correct kernel.
9. **SVG mask module**; animated image frames; procedural sprite glyphs; non-overlap flag and lanes; frame profiler and counters; device-loss path.

Budget checked at every step: draw calls and `present` time at 10k Box + 10k Label; frame time of a sprite-only scene (must not regress); CPU time of a fully static 100k-node frame and of a scrolling 200-line text view after step 5; atlas bytes after a zoom sweep; wasm size delta per backend and per module.

## Open

- **Rasterizer**: stb_truetype only, or FreeType as a module — from step 2's captures.
- **Atlas planes**: separate R8 and RGBA page kinds (G) or four coverage planes per RGBA page (M) — at step 2.
- Reference facts were read from source, not benchmarked. Instance sizes and the one-draw-call claim are from planned layouts, not measured.
- Non-uniform scale on SDF boxes and `erf` shadows is approximated; the error has not been characterised.
- Nested rotated clips fall back to scissor AABB for outer levels; whether Neon needs better is unknown.
- System font discovery is host work; whether Ion or the Neon host owns it is undecided. Ghostty's Windows scanner is a stopgap, not a model.
- The Zed editor element (`crates/editor`) is outside the sparse clone: how it uses `paint_layer`, `split_at` and tab expansion was not read.

## Decision (2026-06-20): own the batcher, do NOT vendor sokol_gp

void2d's render base is a **hand-rolled quad batcher on Void's own GPU bridge** — not [sokol_gp](https://github.com/edubart/sokol_gp).

**Why (in order):**

1. **Hard incompatibility.** sokol_gp master binds textures with the **old** sokol_gfx API (`sg_bindings.images[]`, `sg_shader_desc` images). Void's vendored `sokol_gfx.h` is the **resource-views** generation: `sg_bindings` has only `views[]`, `sg_shader_desc` has only `views[]` — no `images[]`. sokol_gp master **does not compile** against our sokol_gfx. (Downgrading sokol_gfx is rejected: it would break the working cube and move backward.)
2. **Less long-term maintenance, not more.** Owning the batcher = track **one** upstream (sokol_gfx). Patching sokol_gp = track **two** upstreams **plus their compatibility** — which is already out of sync today.
3. **Own-the-stack discipline.** A 2D quad-batcher is exactly the "UI-helper layer above the narrow waist" that Void's CLAUDE.md says Void should own. Hand-rolling a quad batcher directly on sokol_gfx is also the mainstream sokol pattern.

**Important:** this does **not** detach Void from sokol. void2d still issues `sokol_gfx` calls through the bridge. It declines a third-party *add-on* (sokol_gp), keeping only the load-bearing core (sokol_gfx).

**What we give up + the escape hatch:** sokol_gp ships a shape rasterizer (lines, arcs, AA strokes, transform/clip stack). For UI we need only a subset — cheap to own. If void2d later needs heavy vector graphics (charts, arbitrary paths), evaluate a vector layer *above* void2d at that point — not now.

## Other references

| Source | Local | Take | Skip |
|---|---|---|---|
| **oryol** (floooh) | `~/projects/oryol` | Module discipline: small layered modules, strict one-way deps (high→low), tier stays technique-agnostic. Its `Gfx` module = the **predecessor of sokol_gfx** → confirms our sokol bridge already IS that tier. | Its C++ container/RTTI opinions, CMake. |
| **Kha `graphics2`** | `~/projects/Kha` | "2D built on top of the GPU layer" generational pattern. | Its full multi-target build system. |
| **sokol_gp** (edubart) | not vendored — [github](https://github.com/edubart/sokol_gp) | Read its quad-batching + transform-stack approach as a model. | **Do not compile** (version mismatch, see decision above). |
| **fontstash** | `deps/fontstash` ✅ | Today's text path, until step 2. | Its integer layout, its single fixed atlas. |

Local clones of the four main references: `~/projects/heaps` @ `b9aa6dcb`, `~/projects/gpui` (sparse `crates/gpui*`) @ `b961b49`, `~/projects/makepad` @ `5e9a697`, `~/projects/ghostty` @ `a301054`. No further rendering references are planned: models that differ too much do not combine.

## Text design (2026-06-21): one shared glyph layer, two consumers

The decision that matters for text is **NOT** "2D text vs 3D text" — it's **bitmap atlas vs SDF**. Every engine surveyed (Bevy, Unity, Godot, Heaps) shares **one** font/glyph/shaping/atlas layer and exposes only **thin per-context consumers** on top.

| Engine | Shared font layer | 2D / UI consumer | 3D / world consumer | Atlas |
|---|---|---|---|---|
| **Bevy** | `bevy_text` (cosmic-text + `FontAtlasSet` → `TextLayoutInfo`) | `Text` (UI) | `Text2d` (world 2D; **no** 3D-mesh text) | bitmap |
| **Unity TMP** | Font Asset + SDF + TMP shader | `TextMeshProUGUI` | `TextMeshPro` (MeshRenderer) | **SDF** |
| **Godot** | `TextServer` (shape + raster) | `Label`, `RichTextLabel` | `Label3D` (billboard) + `TextMesh` (extruded geometry) | bitmap (MSDF opt) |
| **Heaps** | `h2d.Font` (BMFont/SDF atlas) | `h2d.Text`, `h2d.HtmlText` | DIY (HUD overlay / billboard quad) | bitmap (SDF via tool) |
| **Void** | **own glyph layer** (layout + atlas → quads) | **void2d** | void3d (→ [VOID3D.md](VOID3D.md)) | **bitmap for pixel-exact, SDF for transformed** |

**Why glyphs are the same in 2D and 3D:** text is always rasterized to an atlas texture; each character becomes a **textured quad with UVs**. The only difference is *where the quads sit + which pipeline draws them*.

**The real fork — bitmap vs SDF:** a bitmap atlas is **crisp for fixed-size 2D UI** (1:1 pixel mapping — exactly Neon's need) but **blurs under scale or 3D perspective**. World-space / heavily-scaled text wants **SDF**. The 2026-09-20 conclusion keeps both, as the two regimes above: the references confirm the fork from both sides — GPUI and Ghostty draw coverage 1:1 on the pixel grid; Makepad draws SDF everywhere and has nothing that lands small text on the grid.

**Void's call:**
1. **Shared glyph layer, not two text systems.** Layout + atlas + glyph quads once; consumers stay thin.
2. **Keep the glyph layer backend-neutral** — it emits `quad + UV + atlas`, not screen-space-coupled geometry, so void3d feeds the same glyphs through the 3D MVP with the SDF atlas.
3. *(2026-06-21: fontstash was the first step. 2026-09-20: it is replaced — its integer glyph positions cannot reach the bar.)*

## Scope discipline

void2d = unified 2D **draw primitives** (rects, sprites, text, clip, transform, batching) + a retained node tree for the reconciler. It is **not** a UI framework: no flexbox layout, no event system, no declarative components — those live in Neon (above) and the JSX/Solid layer (which reconciles onto void2d's `Node2D`). Text layout, measurement and hit geometry **are** rendering and live here. Keep the narrow waist.
