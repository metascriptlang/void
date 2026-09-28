# void2d — Unified 2D / UI Render Layer

Void's 2D layer: draw the **same pixels on every platform** (Metal / D3D11 / GL / WebGPU / WebGL2) through one MetaScript codebase. This is the layer that makes Neon's UI rendering "special" — instead of binding to per-OS native widgets, an opted-in app can render its UI through Void and get identical output everywhere.

**This doc is the entry point.** It holds the conclusions. The evidence lives in four reference docs, each read from source with `file:line` citations:

| Doc | Role |
|---|---|
| [HEAPS.md](HEAPS.md) | **The vocabulary reference.** Heaps `h2d`: the scene-graph names and meanings void2d takes where they cost no power ("The rule"). |
| [GPUI.md](GPUI.md) | **Rendering reference 1.** Zed's renderer: the primitive look, the text path, the frame shape. The only reference with a shipped WebGPU-in-the-browser path. |
| [MAKEPAD.md](MAKEPAD.md) | **Rendering reference 2.** GPUI's model under Void's constraints: own shader fan-out, own text stack, WebGL2 and mobile. |
| [GHOSTTY.md](GHOSTTY.md) | **Rendering reference 3.** Dense text only: font stack, atlas, blend space, frame discipline. |

Scale and scene storage: [SCENE-SCALE.md](SCENE-SCALE.md). How any of it is proved — tiers, oracles, goldens, the gate, and the conformance run that turns guardrail 9 into a number: [TESTING.md](TESTING.md).

## Where it sits

```
Neon (parent)            component model: View, Text, Flexbox, events, state, diffing
  │   React-Native style; picks a backend per platform
  ├── native widgets      iOS UIKit · Android · Browser DOM          ← Neon-default
  └── Void backend        unified pixels on every platform           ← opt-in, "special"
         │
   Neon reconcile +       Layer A: diffs JSX → Host ops (neon/src/render/reconcile.ms).
   Void Host adapter      voidHost() maps Host ops → binder calls on NodeRef handles.
         │                Like R3F (react-reconciler drives THREE.Object3D) — NOT a
                          second reconciler; the adapter is ~50 lines (see neon mockHost).
   ┌─────┴───────────────────────────────────┐
 void2d (this layer)                        void3d (camera/mesh/material)   ← opt-in
   node tables + quad batcher                       │
         │                                          │
         └──────────── Void GPU bridge ─────────────┘   = oryol "Gfx" tier  ✅ DONE
                              │   src/sokol/{bridge,gpu}
                       sokol_gfx (floooh)  ← the load-bearing cross-platform dependency
```

> **Full 3-layer model** (A reconcile / B paint / C GPU) and who owns B+C per platform — native = OS, Void = owned: see [`~/metascript/neon/docs/RENDER-LAYERS.md`](../../neon/docs/RENDER-LAYERS.md). Void = Layers B+C; Neon = Layer A; they meet only at the Host interface.

## Two faces of void2d (load-bearing)

1. **Immediate quad batcher** — thin over the GPU bridge: accumulate textured/colored quads CPU-side, flush as few draw calls. For HUD / games that just draw each frame.
2. **Retained node tree** — since P5 step 6 a node is a row of its `Scene`'s tables (transform, paint, content, order, tree), held as a `NodeRef` handle and written through binders. This is the **host the JSX/Solid reconciler binds to** (R3F maps `<mesh>` → a retained `THREE.Object3D`; Solid-on-Void maps JSX → a retained node). Each frame, walk the tree → emit batcher calls.

Both required from day one: face 1 ships HUD/game now; face 2 is what the reconciler (`createNode` / `setProp` / `appendChild`) will drive later. A pure immediate-mode 2D layer would have no host for the JSX layer to reconcile onto. With the display list below, face 1 becomes "append to the list" and face 2 "a tree that appends to the list".

## The bar (2026-09-20)

Heaps is a game engine. Void is a rendering engine, and void2d must carry **application-UI rendering** when Void is a Neon backend — concretely, render a code editor like Zed: fine font control, high-quality antialiasing, fast and smooth. Decisions are judged against "a 13 px code font at 1× and 1.5× DPI looks and scrolls like Zed", not against HUD needs.

**The spirit (the human, 2026-09-29).** Void is a pure rendering engine and was never Heaps: WebGPU and sokol are first-class, and P5 step 5 already replaced h2d's objects with void3d's data model. Rendering power and performance come first. void2d exposes raw capability and leaves the app as much control as it can; convenience (policies, defaults, widgets, layout) is Neon's layer. Its syntax is the one that fits MetaScript's power and idiom best, not the one a Heaps user expects.

**The rule.** For every surface and every mechanism:

- **Capability first.** Expose what the GPU and the mechanism can do: bulk writes over spans, explicit promises that buy speed (children that do not overlap), raw transforms. A policy built on a capability is a helper, or Neon's.
- **The call shape is MetaScript's**, as void3d writes it: handles, binders, spans, value tables. h2d supplies a name or a meaning where it costs no power, and a divergence from it is recorded in HEAPS.md "Do not copy from h2d".
- **Low level is not unsafe.** The workspace rules hold: the same result on every backend, and fail loud. A promise the app makes to go faster is checked where it can be, and a misuse stops with an error that names it.
- **The mechanism comes from the references**: GPUI first, then Makepad and Ghostty where GPUI is weak, Bevy and void3d for data. void2d takes **everything in their rendering layer**, except where one of three reasons applies:
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
- **Interface stays h2d's** (`Font`, `Text`, `textWidth`, `calcTextWidth`, `splitText`, `letterSpacing`, `lineSpacing`, `maxWidth`, `textAlign`); underneath, nothing of h2d's font pipeline survives (H: baked atlases, Int metrics, one page). `textAlign` takes h2d's five `Align` values since P4, with h2d's spans (`h2d/Text.hx:430-446`): Center and Right inside `maxWidth`, or about the origin without one; the Multiline pair inside the widest line. h2d floors each line's offset; void2d keeps it a float, because layout is never rounded.
- **Layout is logical, unhinted, float, never rounded** (G, M). The node holds its shaped layout; wrap, truncation and hit-testing index into it (G).
- **Control characters draw nothing and probe no face** (P4, REVIEWS.md P3 F4). GPUI does not handle tabs at all (GPUI.md, weak spots); here a C0 control or DEL keeps its glyph slot, so indices still line up, with no glyph, no advance and no kerning pair across it, and never reaches the fallback chain. A tab advances to the next stop of 8 spaces of the primary face, counted from the line start: 8 is CSS `tab-size`'s initial value, which is what the same text shows in a browser, and an editor that wants 4 expands tabs itself, as Zed does.
- **Two regimes, chosen per node from the world matrix.**
  - *Pixel-exact* (translation + DPI scale) — coverage bitmaps at `size × scale`, x quantized to 1/4 device pixel in four variants, baseline on a whole pixel, drawn 1:1 texel-exact (G; Gh is the one-phase special case). Makepad is the counter-example to avoid: at 13 px / 1× it draws a 32 px/em SDF minified ~2.4× with bilinear filtering, no snap and no gamma correction — it has no mechanism for pixel-grid crispness (inferred from source, not captured).
  - *Transformed* (any other affine) — an **SDF atlas**: one ~32 px/em distance field per glyph serves every size, derivative-scaled ramp, luma bias (M recipe; `stbtt_GetGlyphSDF` exists). Zoom and animation cost nothing and leak nothing. This is also the door to world-space text in void3d. **Until P6's SDF module lands, P3's transformed regime is a coverage bitmap** rasterized at `size × √|det|` and drawn through the affine (`labelText.ms` `placeLabel`): correct, but a scale change re-rasterizes, and the zoom sweep's two-page bound is what keeps it honest.
- **Gamma/contrast**: GPUI's function and table, ported once — **done at P3 step 4**: one GLSL `@block` (`shader2d.glsl` `textGamma`) serves the UI glyph mode and the colour-pipeline fallback, its T0 copy is `src/void2d/textGamma.ms`, and the ratios come from GPUI's 13-row table at its defaults, gamma 1.8 and grayscale contrast 1.0, through `setTextGamma` (GPUI's `ZED_FONTS_GAMMA` equivalent). Measured on the goldens: only the 12 text scenes moved, max delta 48, and on light-on-dark text every changed pixel got lighter — the direction the table predicts (a half-covered edge 0.50 → 0.69). All three references blend in gamma space on a UNORM target, as Void does. Ghostty's bg-aware `linear-corrected` is an alternative tied to linear blending and needs the destination colour; it is an opt-in only for text that declares a solid background.
- **Fonts**: `Font { family, weight, style, features, fallbacks }` from bytes (G, M). The collection model is Ghostty's: ordered faces per style, deferred faces, explicit-vs-fallback presentation, a codepoint → face map that caches misses, whole-grapheme selection, **fallback size harmonisation**, synthetic bold/italic, lazy CJK/emoji families (Gh, M). System font discovery is host work. **Landed at P3 step 5** (`font.ms`): `registerFace(path, family, weight, style)` registers a face without loading it; `resolveFont(Font)` interns the value, picks the face in the CSS Fonts 4 weight order with italic preferred for italic, loads it, and synthesizes bold (weight ≥ 600 over a lighter face) and italic from the outline — Ghostty's policy on stb_truetype: `FT_Outline_EmboldenXY` ported to float at `lineHeight / 32` units, the advance widened by that strength as `FT_GlyphSlot_Embolden` does (Ghostty does not widen, because a grid cell is fixed), and a `tan 12°` skew about the baseline. A label takes it as h2d's `text.font = f`, spelled `setFont(id)`: since P4 `addFont` and `resolveFont` return `Result<FontId, FontError>`, so a refused font is the caller's to handle, not a label that silently keeps its old font. `features` honours `kern` only; any other tag refuses the font by name until P6's shaper. Fallback families resolve in the font's own weight and style, synthesized when they lack it. **Size harmonisation is Ghostty's `ic_width → ex_height → cap_height → line_height` chain, off by default** (`Font.sizeAdjust`). Measured on Inter + Noto Sans SC: `IcWidth`, Ghostty's default, draws hanzi 19.6 % larger than the Latin size — right for a terminal cell, wrong for UI text — while `ExHeight` moves them 0.5 %. The other references, read 2026-09-24 at the human's request, agree with off: GPUI does nothing (Rexa on GPUI adds only symbol fallback families), and WezTerm (`b09b56c`) has only an opt-in cap-height match, `use_cap_height_to_scale_fallback_fonts`, default false. Not landed: **colour emoji, decided at P3's review as a P6 compile-time module.** stb_truetype reads no colour table and every reference draws colour glyphs through FreeType or the OS, so void reads them itself. Explicit-versus-fallback presentation comes with it, and deferred faces land beside it in the default glyph layer (`tests/PENDING.md font-colour-emoji`). **Whole-grapheme selection landed in P4** (`textLayout.ms` `assignFaces`, over `grapheme.ms`'s UAX #29 segmenter): a multi-codepoint grapheme takes the face of its first codepoint whose face covers every codepoint in it, joiners (ZWJ, VS15, VS16) ignored, as Ghostty's `indexForCell` does (`src/font/shaper/run.zig:318-382`). Where no one face covers it, Ghostty draws U+FFFD, because a terminal cell holds one font; a proportional line keeps a face per codepoint instead, so the text stays readable at the cost of a mark placed by another face's metrics.
- **Runs and decorations**: `TextRun { len, font, color, background, underline, strikethrough }`; a style change splits the shaping run, so a ligature is never two-tone (G, Gh). Backgrounds, underline, strikethrough and wavy are instances of the UI pipeline; thickness and position from the font's `post` / `OS/2` metrics with broken-table fallbacks (Gh), snapped. **The metrics landed at P3 step 6** as `TextLayout.decoration` (`glyph.c` `void2dGlyphDecoration`), float, y-down from the baseline to the top of each stroke, from the primary face: Ghostty's rule exactly, where a zero thickness marks a table broken but keeps a non-zero position, and each missing value is estimated from the ex height (OS/2 v2+, else the measured `x`, else 0.75 of the cap height, itself OS/2, the measured `H`, or 0.75 of the ascent). One divergence: the ascent in that last estimate is stb_truetype's `hhea` ascent, where Ghostty prefers `OS/2` typo metrics; the two agree for Inter. Emission and snapping are P4's, with runs. **Landed in P4** (`setTextRuns`, `textLayout.ms` `layoutRuns`, `labelText.ms` `runDecorations`): `len` counts UTF-16 units and the runs must cover the text exactly, or the label stops and says so; a run's colour multiplies with the label's, as h2d's `setColorSegments` does with `textColor` (GPUI's replaces it); kerning stops at a run boundary, standing in for the shaping-run split until P6's shaper; the decoration boxes are laid out with the text and only transformed and snapped when drawn, so a frame builds no array for them. A decoration runs on across the runs that share it (kind, colour, position and thickness), as GPUI's does (`line.rs:633-663`), so a squiggle under several syntax runs keeps one phase. Each run's decoration sits on its own face's metrics, Ghostty's rule as the P3 metrics have it, so one that crosses faces with different metrics steps there and restarts its wave, where GPUI puts one offset on the whole line: a **W** for metric fidelity. A styled label's bounds reach its widest row's end, so a background or underline over trailing spaces is neither culled nor clipped. The human chose h2d's multiply on 2026-09-27 (asked 2026-09-26); **landed in P5**, before the host contract: a styled label is written white and coloured by its runs, as in h2d, and T1 pins the product. Backgrounds, glyphs and lines bind the same glyph-page view, so `text/decorations`, three styled labels, is one draw call.
- **Caret and selection are their own instances**, never part of a text range, so a blink dirties nothing else (Gh, M). Selection is per-row quads unioned by smooth-min (M).
- **Atlas**: coverage pages and colour pages, 1024², a new page when full (G); 1 px gutter; a CPU mirror per page, dirty pages uploaded once per frame (sokol replaces whole images); ref-counted tiles; **a repack never moves a live tile** (Gh). **Resolved at P3 step 8: R8 coverage pages, with colour glyphs on a separate RGBA page kind**, not four planes per RGBA page (M) — P3 "Atlas page kinds" has the measurement. Only the R8 kind is built; P6's colour-emoji module builds the RGBA one. A page is reclaimed whole once no live tile and no quad of the current frame uses it. One divergence from GPUI: a glyph larger than a page (1023 px with the gutter) is refused with `AtlasError.TooLarge`, where GPUI gives an oversized item its own texture (GPUI.md:127); those sizes belong to the SDF regime.
- **Shaper** — compile-time module (candidate `kb_text_shape`): GSUB features, ligatures, complex scripts; "break shaping at index" as an input (Gh). Without it: cmap, GPOS kerning, NFC input, fallback by coverage.
- **Rasterizer — resolved at P3 step 8: stb_truetype only** (P3 has the experiment). stb_truetype is unhinted: what macOS and Ghostty-on-macOS ship, and sufficient on HiDPI. Ghostty ships FreeType **light hinting** everywhere else; Makepad is unhinted and unsnapped. Constraint if FreeType comes: hinting only in the pixel-exact regime, and the outline is shifted *before* hinting. Decided by the FreeType experiment and its wasm cost, not by captures beside Zed: that T5 look is still owed by the human, and it can move only the verdict on stem darkness.
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

### Web and WebGPU

The browser is a first-class target, not a port: `scripts/build-web.sh` builds **both** web backends, WebGPU (`--use-port=emdawnwebgpu -DSOKOL_WGPU`, which also needs `-sASYNCIFY`) and WebGL2 (`-DSOKOL_GLES3`), from the same source (`src/sokol/sokolWeb.c:1-8`).

Among the references **only GPUI ships a browser renderer**: `BrowserWebGpu` with WebGPU detection and a GL fallback (`gpui_wgpu/src/wgpu_context.rs:159-171`), plus a whole `gpui_web` crate. Makepad is WebGL2 only — its WGSL is an intermediate for Vulkan through naga, with no WebGPU consumer. Ghostty declares a `webgl` backend for wasm (`src/renderer/backend.zig:5-22`) but `src/renderer/WebGL.zig` is two lines: intent, not code. So on this axis GPUI is the closest reference, not the farthest.

**The binding constraint is the intersection of WebGPU and WebGL2**, because Void must run both:

- **No storage buffers on WebGL2.** Instance data travels as per-instance vertex attributes (`SG_VERTEXSTEP_PER_INSTANCE`), never a storage buffer. GPUI needs a second code path for this — instances packed into an `Rgba32Uint` texture "to keep the records available to both shader stages" (`gpui_wgpu/src/wgpu_renderer.rs:166-176`). Void does not, and must not grow one.
- **No `base_instance` on GLES3/WebGL2** (`deps/sokol/sokol_gfx.h:238-239`). Instance ranges are addressed with `vertex_buffer_offsets`.
- **255-byte vertex stride ceiling** on WebGL2 (Makepad's own validator, `web_gl.js:1103-1108`), and 16 attributes. The planned ~92–128 B UI stride fits with room to spare.
- **No dual-source blending**, so no ClearType — GPUI disables subpixel text whenever it falls back to the WebGL instance path (`wgpu_renderer.rs:434-435`). Guardrail 7 already holds.
- **Uniforms are expensive on WebGPU**: sokol allocates one per-frame uniform buffer and **every `sg_apply_uniforms` call costs at least 256 bytes** of it, whatever the payload (`sokol_gfx.h:2014-2023`, `_SG_WGPU_ROWPITCH_ALIGN`); the default `uniform_buffer_size` is 4 MB (`:6614`). void2d applies two uniform blocks per draw today, so a draw costs 512 B of that budget on WebGPU and Metal. At a few hundred draws this is fine, but the display list must keep per-draw uniforms to what actually changes, and the budget is a thing to measure, not assume.
- Image data on WebGPU is row-pitch aligned to 256 bytes, so atlas pages stay at power-of-two widths ≥ 256.

**What the browser demands beyond desktop:**

1. **Warm-up matters more.** GPUI rasterizes a glyph synchronously on its first paint, with no pre-warm. On one browser thread that is a visible hitch the first time a file shows new glyphs. Ghostty's warm-up of device, pipelines and the font database off the first-frame path (`renderer/Metal.zig:405-441`) is the model; on the web it is not optional.
2. **Upload bandwidth is scarcer.** sokol can only replace a whole image, so atlas pages stay small (1024²) and only dirty pages are uploaded — a 2048² page like Makepad's would re-send 16 MB for one new glyph.
3. **Fractional DPI is the norm**, since `devicePixelRatio` is routinely 1.25 or 1.5. The logical size is therefore a float, never truncated to int: that defect closed in P1 ("Known defects").
4. **No OS text system at all.** GPUI's web path is cosmic-text plus a canvas fallback for emoji, which is a third set of pixels beside its macOS and Windows output. Void owns one rasterizer everywhere; this is guardrail 9 and the reason the glyph layer cannot be deferred.
5. **wasm size is a shipping constraint, not a nicety** — hence guardrail 6 and the per-module measurement in the budget.
6. Frames are driven by `requestAnimationFrame`, re-armed only when something is dirty (`gpui_web/src/window.rs:918`). That is the host's job, and it is the same "dirty → draw, else nothing" contract as the desktop hosts.

### Instance sizes

Today a quad is 6 vertices × 8 floats = **192 B**, re-transformed on the CPU every frame, with no AA of its own. With per-instance attributes (`SG_VERTEXSTEP_PER_INSTANCE`, core in GLES3/WebGL2):

| Instance | Payload | Size |
|---|---|---|
| Sprite pipeline | affine 4 + origin/size 4 + uv 4 + colour 4 (float) | **64 B, measured** |
| UI pipeline (single stride for all modes) | affine 4, origin/size 4, uv-or-radii 4, border widths 4, mode/params 4, gradient/shadow params 4 (all `FLOAT4`), three colours as `UBYTE4N` | **108 B, measured** |

**Measured 2026-09-21, not estimated.** Both numbers come from `sizeof` on the structs the
vertex layout is built from, and `src/test/instanceLayoutCheck.ms` holds them to the offsets with
no GPU. Since P5 one lane table, `scripts/instanceLayout.ms`, generates both sides:
`src/void2d/instanceLayout.h` (the C structs, the vertex attributes, the UI pack) and
`src/void2d/instanceLayout.ms` (the byte and record offsets). The gate regenerates them and fails
on any difference, so a field cannot be added to one side alone; the setup-time check that
compared two hand-written copies is gone with the second copy (REVIEWS.md "Audit before P4" #23).
Call sites build a `UiInstance` record (`instance.ms`) with named lanes in place of
`drawUiInstance`'s 25 positional ones (#19).

Two things the estimate got wrong, kept because the phase says *do not defend the estimate*:

- **"~92 B packed" did not match the field list printed beside it.** Six `FLOAT4` lanes plus
  three `UBYTE4N` is 96 + 12 = **108 B**; there is no packing in the enumeration that reaches 92.
  92 is reachable only by demoting the radii and border lanes to `HALF4`, which the row never
  said and which is not being done: at 108 B there are **147 bytes of headroom** under the
  ceiling, and a second vertex format is cost with no measured buyer. If P5's persistent ranges
  or a bandwidth measurement later want those 16 bytes, that is a measured reason to pack.
- **The sprite row said "affine 6 + size 2".** An affine is six numbers but ships as two
  `FLOAT4` lanes, because a vertex attribute is a vec4 — the translation rides in the same lane
  as the size. The count of numbers and the count of bytes are not the same thing, and the row
  mixed them.

**P2's two-stride fallback is therefore not taken.** 108 ≤ 255, so one stride serves box,
shadow, glyph, image, underline and selection, and the UI pipeline uses 9 of the 16 vertex
attributes the web intersection gives. `src/test/instanceLayoutCheck.ms` asserts both as
arithmetic, so the commit that first overflows either is the commit that goes red — which is
the commit that has to take the fallback.

For scale: GPUI's glyph instance is 112 B, Makepad's ~116 B, Ghostty's 32 B (integer grid coordinates — not reachable for general UI). Ceilings and addressing come from the web intersection above. Only what the fragment stage reads is passed as a varying (Makepad forwards every field, costly on tile-based GPUs). Sizes are estimates from planned layouts; 4-vertex instances should be checked against indexed quads on one Mali and one Adreno device before committing.

## Known defects in void2d (2026-09-20)

Each carries the phase that closes it. Each is also covered in `tests/PENDING.md`, whose
index names the coverage line by line: a defect with no capturable picture becomes a listed
failing case, and a defect that *has* a picture becomes a `regress/` golden instead, because
a golden says what the defect looks like and not merely that it exists. Either way the fix
has to touch the record — the listed case graduates, or the golden moves and can only be
regenerated by a commit that says why ([TESTING.md](TESTING.md) "PENDING").

- ~~**Atlas-full drops a *different* set of glyphs on every run**~~ — **closed in P1, as a holding fix**, and **the class removed in P3** with fontstash: glyph pages are fixed 1024² R8 that never grow or move a tile, a page with no live tile is reclaimed whole, and a glyph with no room fails loud (`AtlasError.Full`) instead of being dropped; `regress/atlasFull` was re-recorded with no report and two captures byte-identical. There was no `FONS_ATLAS_FULL` handler, so when the fixed 512² atlas filled, fontstash asked once, retried once and dropped the glyph — and *which* glyphs were dropped varied between runs of the same binary: three distinct outputs in ten, worst pair 28 740 of 80 000 pixels (35.9%) at max delta 207. The handler now doubles the atlas, height first because the packer fills row by row, up to a 2048 cap chosen as the smallest guaranteed maximum texture size across the backends this ships on; `fonsExpandAtlas` preserves the glyphs already placed and lets the retry succeed. **Re-measured: ten runs, one output**, and `regress/atlasFull` is a golden with no tolerance. The second half, `fons_resize` leaking the old image and view, is closed too and was made a number first: one capture of that one scene resized twice and left **3 atlas images alive, 0 freed**, against sokol's 128-slot pools. They cannot be destroyed on the spot — commands already recorded in that frame carry the old view id and the replay has not run — so they are retired and freed at the top of the next frame, the same frame-linear discipline the filter targets use. After the fix the same run reads **3 made, 2 freed, 1 alive**, and `void2dAtlasImagesAlive()` exposes it. A guarded `malloc` went in beside it: the mirror allocation was unchecked and `memset` followed it immediately.
- ~~**At most ~126 Labels/Graphics render**~~ — **closed in P1** (`d05601c`). Each Label and Graphics owned an `sg_buffer` against sokol's default pool of 128. One growing vertex buffer replaced them: `ui.buffersAlive` is **2** at 10 000 labels and constant in the node count, `ui.retainedNodes` is 10 000, and the golden `regress/nodeCap` now shows all 200 labels instead of 0–125. The `buffersRefused` counter was deleted with the defect — nothing is refused any more.
- ~~**Node filters do not work at all, and take the whole frame with them.**~~ — **closed in P1.** `drawFiltered` opened a render-target pass inside the swapchain pass; a debug build tripped `Assertion failed: !_sg.cur_pass.valid` and a release build presented only the clear colour. The second half of that was worse than recorded: the nested `begin2d` called `resetList()`, so it did not merely fail to draw the filtered node, it **erased the frame recorded so far** — which is why the siblings before and after vanished too. Both are gone: a filter now brackets a region of the display list, the block is moved out of the swapchain list when it closes, and the replay runs every target pass before the one swapchain pass. Nesting is correct by construction because targets close LIFO, so an inner target's block is appended ahead of the outer one that samples it — asserted in `displayList.ms`, not just hoped for. Five goldens on: `filter/blur`, `filter/glow`, `filter/dropShadow`, `filter/groupOpacity`, `regress/filterNestedPass`, all five re-run in a debug build with the validation layer linked.
- ~~**Filter semantics differ from h2d**~~ — **closed in P1**, all five: the node itself enters the target (`drawContent(n, ...)`, not a loop over `n.children`); alpha is applied once, because the filter takes the node's alpha over for the length of the target instead of letting `drawContent` multiply it in again; the target is object-local through a filter matrix, which is a translation the emitter subtracts as it records, so the subtree keeps its single sync instead of being walked and re-synced twice a frame; bounds are clipped to the viewport; and targets come from a frame-linear pool (`h3d/impl/TextureCache.hx`) capped at 16, so no node owns a texture any more. The kernel is guardrail 3's: downsample by 2^k, then blur at a one-texel step. The old code passed `radius / size` as the tap step, which put the outer taps at 3.23 × radius texels — at radius 5 it sampled 16 texels away, so it combed rather than blurred, and that is why the demo asked for 5 to get a 16-pixel spread. One implementation serves both the node filter and `filter.ms`'s manual helper; two would drift. **A sixth defect turned up while measuring** and is closed with them: a render target is premultiplied, so `texel * color` scaled only its alpha and left rgb at full strength — fading a filtered subtree changed its coverage and not its colour. `filter/groupOpacity` was read pixel by pixel against both models: without the filter the overlap measures (104,125,148) against a double-blend prediction of (104,124,148); with it, (48,107,137) against a single-composite prediction of (48,107,136).
- ~~**Fractional DPI puts every glyph off-grid**~~ — **closed in P1** (`d05601c`). `begin2d` takes a float logical size, so `Scene.presentAt` no longer truncates a 1.25 or 1.5 ratio to an integer. The golden `regress/dpiTruncation` moved: the rule now reaches the true right edge. `text/code13Dpi125`, `text/code13Dpi150`, `snap/hairlineDpi125` and `snap/hairlineDpi150` did **not** move — glyph origins are still rounded to integers inside fontstash, which is a separate defect listed under **P3**.
- ~~**Samplers are hard-wired REPEAT**~~ — **closed in P1**, its own commit as the phase asked. Four samplers now, indexed by `smooth * 2 + tileWrap`, with **clamp as the default**: a Tile is a sub-rect of an atlas page, so REPEAT on one that does not fill its page wraps a neighbour's pixels in at the seam. `smooth` became h2d's tri-state (`Smooth.Inherit/Off/On`) resolved against a new `Scene.defaultSmooth`, which is **linear** — h2d's own default is nearest (`h2d/RenderContext.hx:52`) and HEAPS.md "Do not copy from h2d" rejects it. Six goldens moved, all at max delta ≤ 2: `regress/samplerRepeat`, `image/subFlip` and the four `demo/` frames. Two goldens were **added**, because `tileWrap` and the scene default were new surface with nothing able to fail on them: `image/tileWrap` draws the same tile at u1 = 3 with the flag off and on, so clamp stretches the edge and repeat tiles 3×3; `image/sceneSmooth` puts an inheriting sprite beside an overriding one under a scene whose default is nearest. Noted against `regress/samplerRepeat`: it is a **weak scene**. It was authored at P0 to record this defect, but the sheet's left and right edges are both near-black, so REPEAT bled in a colour almost equal to the clamped one — 448 pixels at max delta 2, invisible to a reader of the diff. Zero tolerance means it still fails on a revert, so it was kept as the defect's own site; `image/tileWrap` is the scene that actually shows the mechanism.
- ~~**Per-frame vertex cap**~~ — **closed in P1** (`d05601c`). The fixed 65 536-vertex dynamic buffer grows by `max(2×)` instead, with a 192 MiB cap and a dropped frame plus an error on stderr past it. GPUI caps its native-only instance buffer at 256 MiB; Void's one allocation carries vertices plus both instance streams and must also run on wasm32, WebGL2 and mobile, so it deliberately keeps 64 MiB below that reference ceiling rather than letting one frame consume the full amount. This is a fail-loud ceiling, not a working-set target. The golden `regress/vertexCap` moved: the grid fills the canvas. Re-measured in a **debug** build, where sokol's validation layer is linked, both `regress/vertexCap` and `regress/nodeCap` capture normally — the `VALIDATION_FAILED` panic at `sokol_gfx.h:23960` is gone, so `tests/PENDING.md debug-abort:vertex-cap` was deleted.
- ~~**GPU calls are issued while the tree is walked**; a text change destroys and recreates its GPU buffer~~ — **closed in P1** (`d05601c`). The walk's only output is the command, effect and vertex streams; `void2dReplay` is the single draw-issuing function and runs after the walk has ended. No node owns a GPU buffer, so a text change rewrites a `float32[]` on the node and nothing else. **The T1 assertion that holds it exists now** — `tests/displayList/snapshot.ms`, "the walk records and uploads nothing" — and the three `tests/PENDING.md` rows that stood in for it were deleted in the same commit that wrote it. What the walk still does is *create resources*: a first-of-its-size filter target and an atlas growth both reach `sg_make_image`. That is stated in the exit table rather than glossed.
- ~~**`add` and `addChild` hand back the parent, not the node that was added**~~ — **found and closed in P1**, by writing a T1 scene the way a Heaps user would. `addChild` returned `n`, and `Scene.add` is `s.root.addChild(c)`, so `s.add(node)` returned the **scene root**. `const n = s.add(x); n.alpha = 0.5;` — the h2d idiom, `new Bitmap(tile, parent)` with the handle kept — configured the root instead, in silence, and `s.add(a).addChild(b)` made `b` a sibling of `a` rather than its child. Measured before the fix with a three-step probe: a scalar written through the handle left the tree's copy unchanged, and one `addChild` through it took the root from one child to two. Nothing in the tree was ever wrong *at rest*, because every scene in this repo builds a node fully and only then adds it — which is why 45 goldens and a demo never noticed. Both functions return the child now, `src/test/nodeCheck.ms` pins it, and the T1 `order` snapshot is the evidence: the nested child moved from world x 1.00 to 21.00, because it finally inherits its parent's transform.
- ~~**A rotated Mask clips to its AABB**, and culling tests the viewport rather than the active clip~~ — **closed in P2**. The command carries the Mask's two projection intervals, each vertex produces four signed edge distances, and every fragment pipeline discards outside them; the AABB remains only as a coarse hardware scissor. T1 `rotatedClip` pins the planes, `active-clip culling drops rows` proves off-clip instances are absent, and T2 `clip/rotatedMask` pins the pixels.
- ~~**Integer glyph origins and rounded advances**, `kern`-only metrics, `split(" ")` wrapping, no `textWidth`, ≤ 16 fonts, the atlas expanded R8→RGBA on the CPU and fully re-uploaded on any new glyph, text lines centred on fractional pixels~~ — **closed at P3 step 3.** Layout is float and unrounded (`textLayout.ms`), a pixel-exact label lands its baseline on a whole device pixel and each glyph on a quarter pixel, kerning reads the GPOS `kern` feature through Extension lookups (stb_truetype 1.26's own reader skips them and read Inter's A-V as 0), wrapping breaks on the layout (at U+0020 only until P4, which breaks by UAX #14), faces are a growing table, and pages are R8 uploaded whole only when dirty. The fallback chain landed at **step 5**: a face falls back per codepoint through `addFallbackFont`, the fallback face loads on the first real miss, hits and misses are cached, the layout records each glyph's face and kerns only within one, and `text/cjkFallback` (Inter + a 504-hanzi Noto Sans SC subset, `tests/fonts/`) draws in one run at DPI 1.25; the `Font` value, synthetic styles and size harmonisation landed later in step 5; the rest of the collection model is `tests/PENDING.md font-colour-emoji` (P6); whole-grapheme selection landed in P4. Still open: a glyph first rasterized into a page an earlier bracket already uploaded that frame is one frame late (`tests/PENDING.md glyph-page-second-upload`, P5).
- The h2d surface still missing — `TileGroup` — is listed in [HEAPS.md](HEAPS.md); `Mask.scrollX/Y` closed at **P5 step 10**; `parent`, `remove()`, reparenting with a cycle stop and the index queries closed at **P5 step 6**. `Tile.dx/dy`, `center()` / `setCenterRatio()` and uniform node pivots closed in **P2**; the text metrics (`textWidth`, `textHeight`, `calcTextWidth`, `splitText`, the node's `textLayout()` with per-glyph x and line boxes) at **P3 step 3**, read from the layout the label paints; the rest **P5**.
- ~~**Idle costs a draw**~~ — **closed at P5 step 9.** `Scene.isDirty()` says whether a frame would draw anything new, GPUI's `is_dirty` gating its frame callback (`window.rs:1798-1834`), so a host presents only then; since step 7 a present of a clean scene replays its list with no walk and no upload. T1 `tests/displayList/retain.ms` pins the flag, and the T4 row `idleDirty` is 0 on every bench scene.
- **Entry points declare `function main()` and nothing calls it.** Not a platform defect: `~/metascript/docs/CODE-STYLE.md` section 9 states the rule — "Nothing calls `main()`" — so an entry that ends at `return 0; }` builds a binary which exits at once everywhere, and a wasm module with the renderer linked out. `src/examples/mainSokol2d.ms` was fixed at P0: its WebGPU wasm was 48 064 B and is now 509 672 B, its WebGL2 wasm 111 522 B and now 410 724 B. `mainSokol.ms`, `mainCampfire.ms`, `iosEntryAnim.ms` and `iosEmbedEntry.ms` were void3d's entries and were left to that arc, which fixed all four at `7b7f163`; the `entry-main-not-called` PENDING row graduated when that reached `main` in `3860752` and was deleted in the commit that rebased onto it. — **closed everywhere: void2d at P0, the other four by the void3d arc.**
- ~~**A sokol view id past 2^24 names another slot in the replay.**~~ — **closed in P5** (REVIEWS.md "Audit before P4" #18). The display list stored `view` as one `float32`, exact below 2^24 only, where a sokol id is `(generation << 16) | slot`. A command now carries the id's two 16-bit halves in `CMD_VIEW` and `CMD_VIEW_HIGH`, rejoined by `void2dCommandView`, the one function the replay and the T1 test both read through; the emitter's saved view is a `uint32`. T1 "a view id past 2^24 reaches the replay whole" fails with one float and with a C rejoin that drops the high half.

## Guardrails

1. **Draw order.** Painter's order stays, and the unified UI pipeline makes it batch. BoundsTree reordering is not planned: GPUI rebuilds it from empty every frame, and it is O(log n) per primitive against the 1M-node target in [SCENE-SCALE.md](SCENE-SCALE.md). The cheap form is kept: `TileGroup`, and a node flag asserting that children do not overlap. No depth buffer for 2D order. Revisit only if measurements of real Neon UI show state-change draws dominating.
2. **Node width.** A node was one 71-field `Node2D` until P5 step 6 and is now a row of value groups, one per pass that reads them. Box style and text runs are read only when emitting, so they live in side tables — the side-table bar in SCENE-SCALE.md.
3. **Filters stay — and get fixed.** Render-target filters on arbitrary subtrees are h2d semantics; the `erf` shadow is a fast path beside them. The blur is corrected: downsample by 2^k then blur at a 1-texel step, or dual-Kawase.
4. **Paths: no MSAA intermediate, no baked fringe.** A pass break per path batch is a full tile store/load on mobile GPUs; a baked fringe scales with the node. Store the edge normal per fringe vertex and extrude in the vertex shader by `1px / scale`.
5. **MSAA is a knob, not a dependency.** Expose `sample_count` for iOS/Android instead of hard-coding 1. Analytic coverage is still required: the embed host owns the framebuffer and its sample count.
6. **Text is where the weight goes, so it is modular.** The glyph layer goes in by default. The shaper, a hinting rasterizer, colour emoji, the SDF text path, procedural sprite glyphs and the SVG rasterizer are compile-time modules; CJK and emoji families load on a real miss. A game build pays for none of them. Measure the wasm delta of each.
7. **No ClearType.**
8. **Pay for what you use.** Snapping, the pixel-exact text regime and the UI pipeline engage only for nodes that use them; a sprite-only scene must not regress at any step.
9. **Same pixels on every platform.** No OS text system, no per-platform text path (Makepad's slug on macOS/web, SDF on Windows), no runtime shader generation. **This is a number: 37/37 scenes byte-identical on D3D11 at P0, 48/48 at P1, 67/67 at P2, 69/69 at P3 and 72/72 at P4, where WebGL2 became the second measured surface at 65/69 (through ANGLE on D3D11; 68/72 at P4), with five other surfaces reported as SKIP with a reason** — GLES3 desktop, Metal macOS, Metal iOS, GLES3 Android, WebGPU. One golden set authored on D3D11, every backend compared against it, a pass rate per backend ([TESTING.md](TESTING.md) "Guardrail 9"). P3's five-backend run was not reached: GLES3 desktop and WebGPU are P6's, Metal and Android wait on the human's hardware. What each missing readback costs, and what browser conformance needs beyond a driver, is written down there rather than guessed at.

## AUDIT: corpus, oracle, QC and architecture at `59ac1cd` + P2 closure `9838fac`

**Verdict: the P0–P2 direction is sound.** The narrow waist in this document is present in
code: `displayList.ms` records flat commands and separate vertex/UI/sprite streams,
`batcher.c` owns replay and frame-linear GPU resources, and `draw.ms` is the bridge between
the retained tree and those streams. Box, shadow and glyph work now share the 108-byte UI
instance path without regressing the 64-byte sprite path. The ABI is not accepted on trust:
`instanceLayoutCheck.ms` compares the MetaScript layout with C `sizeof`/`offsetof`, and
`uiPipelineCheck.ms` checks run boundaries and per-stream offsets.

**Evidence actually held on tree `96875decbfc40fd33ae1f34b5a6f07d73b117b9c`.**
`sh scripts/gate.sh` was green with **681 tests**, **56/56 D3D11 goldens**, **40 PENDING
entries**, and **12 loud skips**. The strongest part is the split between evidence types:
T1 snapshots prove recording/order/growth without a GPU; T2 catches image drift; T3 computes
16×16 supersampled geometry and a numerical Gaussian integral independently of the shader,
then judges the committed captures. Its red controls are live: a hard edge, smoothstep
coverage and the wrong blur all exceed the accepted bounds; the real rotated edge measured
0.0502 against 0.06, and the real shadow measured 0.0251 against 0.035.

**P2 closure on tree `5e32ea0a6d639231ad02c56cb17c3a7c04763519`.**
`sh scripts/gate.sh --web` was green with **708 tests**, **67/67 D3D11 goldens**,
**28 PENDING entries**, **12 loud skips** and zero failures. The demo and mixed 3D/2D frame
passed; both web backends built at 727,447 B WebGPU and 632,772 B WebGL2; WebGL2 liveness
passed while WebGPU remained an explicit adapter SKIP.

**Findings, in closure order:**

1. ~~**The mixed void3d → void2d frame boundary was unproved and wrong.**~~ **Closed after
   this audit.** `renderer.endFrame` now imports the bridge's shared `commit`; the duplicate
   `gpu3dCommit` declaration, wrapper and direct `sg_commit` site are gone. The permanent
   `tests/integration/mixedFrame.ms` capture draws the cube and a void2d overlay in one
   swapchain pass, commits once, starts a second frame, and requires the two fixed-state
   captures to match. Its per-frame void2d draw-count assertion is the regression guard:
   the old path left that count accumulating because `void2dFrameEnd` never ran.
2. **Guardrail 9 is two measured surfaces of seven since P3 step 8.** WebGL2 has golden
   readback through headless Chrome: **65 / 69** against the D3D11 set, four structural failures
   named in `tests/PENDING.md conformance:webgl2-pixel-centre`; the first run also found and fixed
   a GL-origin dither bug. Headless WebGPU still has no adapter on this machine, and Metal and
   Android need hardware this box does not have (TESTING.md "Guardrail 9").
3. ~~**The performance gate protected shape, not timing.**~~ **Closed at the P2 phase end.**
   `tests/bench/baseline.json` now records load and an interleaved six-pair A/B against P1 tree
   `46d939b`: UI **21.36 → 12.13 ms** and sprites **2.11 → 1.77 ms**. The gate still owns the
   deterministic contract — one UI draw, 48,890 instances, 5,280,120 uploaded bytes — while
   the controlled run owns the timing claim. The isolated gate's sprite timing WARN does not
   replace that A/B.
4. ~~**The ledgers had drifted behind the executable evidence.**~~ **Corrected after this
   audit.** `tests/PENDING.md` now says its five rows are the oracles still unwired rather
   than claiming none exists; `docs/TESTING.md` records both coverage oracles, their capture
   checks and the current 67-scene D3D11 count.
5. ~~**Reserved UI modes need production reachability checks when they land.**~~ **Closed
   during P2.** T1 `gradients`, `imageStyle` and `textPrimitives` now start at retained nodes,
   pass through the production emitter and pin their effect or instance lanes; raw-mode tests
   remain only the lower-level layout and batching check.

All five audit findings are now closed or assigned at the correct later phase, and the fourth
fresh review records **SHIP WITH FOLLOW-UPS** for P2. P3 owns the next QC boundary:
cross-backend golden readback and conformance, starting with the existing GL/GLES path.
WebGPU still needs an adapter plus asynchronous readback; the compiler reachability card
remains open without a workaround in void.

## Roadmap

Seven phases. Each ends with something demonstrable; none leaves `src/examples/renderer2d.ms` — the demo the golden suite captures — broken; each names the "Known defects" entries it closes. How a phase is proved is [TESTING.md](TESTING.md), and the tier names below (T0–T5) come from there.

**Baseline — two of them**, because the roadmap has moved and one line here used to claim
both at once. Every run below is release, D3D11, 1280×720, `sample_count` 1, `high_dpi` 0,
20 warm-up + 120 measured frames.

**(a) P0, where the roadmap starts** (2026-09-20, before the display list). This is the
record of what each phase improves on. It is **not** in `tests/bench/baseline.json` and
**not** reproducible by `sh scripts/gate.sh`: `buffersRefused` was deleted with the defect it
counted (see "Known defects", the ~126-Label entry), so no build since P1 can produce this
table at all.

| row | ui | sprites |
|---|---|---|
| nodes | 20 000 | 10 000 |
| retainedNodes | 10 000 | 0 |
| draws | 253 | 1 |
| buffersAlive | **126** | 0 |
| buffersRefused | 9 874 | 0 |
| present.ms | ~4.2 (3.6–5.2) | ~1.7 (1.5–2.1) |

`retainedNodes` is how many nodes ask for a GPU buffer — the Labels; cards and sprites go
through the dynamic batcher and own none. So the UI pair reads as **10 000 labels asked,
126 drew**, which is the ~126-node cap as a number: past sokol's 128-object default pool
every `sg_make_buffer` is refused. `buffersRefused` is monotonic, so a scene that rebuilds a
mesh every frame shows a larger number than the difference.

**(b) P1, what `tests/bench/baseline.json` holds and what `sh scripts/gate.sh` gates against
today** (2026-09-20, at `da36060`). This is the table a phase is measured against now.

| row | ui | sprites |
|---|---|---|
| nodes | 20 000 | 10 000 |
| retainedNodes | 10 000 | 0 |
| draws | **20 000** | 1 |
| buffersAlive | 2 | 2 |
| vertices | 293 340 | 60 000 |
| uploads | 1 | 1 |
| uploadBytes | 9 386 880 | 1 920 000 |
| atlasImages | 1 | 1 |
| droppedFrames | 0 | 0 |
| present.ms | **19.9** (19.3–21.1) | **2.5** (2.2–3.1) |

**`draws` went 253 → 20 000 and `present` 4.2 → 17.8 ms, and neither is a regression.** P0's
two numbers were cheap because the frame drew 126 of the 10 000 labels it was asked for and
silently dropped the rest; P1 draws all 10 000. The cost of the pool cap was being paid in
missing pixels, and it moved to milliseconds once the pixels arrived. Collapsing the 20 000
back down is exactly what P2 is for, which is why P2's "Measure" anchors on 20 000 and not on
the 253 a reader would otherwise carry out of this section.

Counters gate; milliseconds report with a warn threshold at 1.5× and never fail a commit
([TESTING.md](TESTING.md) "T4").

**(b)'s two millisecond rows were re-taken on 2026-09-21**, at P2's first step, closing F-14 —
`ui.present.ms` had never been re-measured after P1's D8. They used to read 17.8 and 1.63 and
**neither could be reproduced by the commit they came from**. Measured on a box checked quiet
first (10.8% CPU mean over five one-second samples), by an interleaved same-box A/B between
`da36060` and `817f2c8`, six alternating pairs each: ui **19.95** (19.69–20.30) against **19.86**
(19.34–20.16); sprites **2.51** (2.24–3.06) against **2.48** (2.27–2.82).

Two things follow, and the second is the uncomfortable one.

- **Guardrail 8 holds.** Nothing between P1's land and here moved either row; the two columns of
  the A/B sit inside each other's spread.
- **The old numbers were wrong, not stale-because-busy.** `tests/bench/baseline.json` explained
  the gap to 1.63 as the machine, citing a run at 54% CPU. That explanation does not survive: at
  10.8% CPU, **P1's own rebuilt binary reads 2.51**. Correcting the baseline is not the forbidden
  move of raising a threshold to fit a reading — `warnFactor` is unchanged at 1.5, and what was
  replaced is a baseline proven unreproducible by its own commit's binary on a proven-quiet box,
  in an A/B rather than a single run. Leaving it meant the gate printed `WARN sprites.present.ms`
  on every green run, and a warning that always fires is a warning nobody reads.

A WARN on a millisecond row still means run that A/B, not that a phase regressed. Two decimals on
(a) would claim a reproducibility the number does not have; (b)'s ranges are what it does have.

**(c) P2, phase-end measurement at `3bc1b12`** (2026-09-22). The machine read 11.77% CPU
mean over five one-second samples before the run. Both release binaries used 20 warm-up and
120 measured frames at 1280×720, sample count 1 and high-DPI off. Six pairs per scene
alternated the current tree against the reachable P1 control `46d939b`, with order reversed
every pair:

| scene | P1 control | P2 | result |
|---|---:|---:|---|
| UI | 21.36 ms (19.83–23.23) | **12.13 ms (11.71–12.70)** | 43.2% faster; 20 000 → 1 draw |
| sprites | 2.11 ms (2.04–2.23) | **1.77 ms (1.74–1.79)** | 15.7% faster; guardrail 8 holds |

P2 did not reach the optimistic 2.0 ms UI prediction. It did remove the cost the phase owned:
the complete 20 000-node scene moved from 20 000 draws to one and from 9 386 880 to 5 280 120
uploaded bytes; no node or pixel was removed. The current `tests/bench/baseline.json` records
12.1/1.8 only as report thresholds, with the load and comparison context beside them.

The final review-fix gate built both backends with the same `msc 0.2.53 --release` command and
dependency checkout. Against `46d939b`, WebGPU wasm is **543 846 → 727 447 B** (**+183 601 B**,
33.8%) and WebGL2 is **449 188 → 632 772 B** (**+183 584 B**, 40.9%). This is P2's whole
instanced-primitives layer, not a module budget; P6 still owns the per-compile-time-module
size gate.

**Dependencies**, stated rather than implied:

```
P0 gate ──▶ P1 display list ──▶ P2 instanced primitives ──▶ P3 glyph layer ──▶ P4 text runs
                   │                      │                        │                │
                   └──────────────────────┴──▶ P5 retention, scroll, host ◀──────────┘
                                                         │
                                                         ▼
                                              P6 modules and hardening
```

P1 needs only P0. P2 needs P1's instance stream. P3 needs P2's instance layout, so the glyph layer is written once. P4 needs P3's shaped layout and P2's underline and selection modes. P5 needs P1's command stream and P2's stable per-instance bytes, and needs P4 for the scroll case that matters. P6 needs P2's pipeline and P3's atlas; nothing needs P6.

**What changed against the nine steps this replaces**, so the regrouping is visible rather than cosmetic:

- **The glyph layer moved behind the instanced pipelines** (old step 2 → P3, old step 3 → P2). A glyph is a mode of the unified UI pipeline; writing the glyph layer first means writing it against the vertex batcher and then rewriting it against the instance layout. fontstash keeps feeding the glyph mode across P2 — a coverage atlas is a coverage atlas — so nothing in the demo breaks while the supplier is swapped in P3.
- **Old step 6 is dissolved into P2.** The `erf` shadow, the image modes and clip-by-edge-distances are modes and rules of the pipeline P2 writes; keeping them apart means two passes over one shader and two rounds of goldens.
- **The blur correction moved forward** from old step 8 into P1, with the rest of the filter semantics: same code (`shader2d.glsl:81-87`), same goldens.
- **Old steps 7, 8 and 9 are one phase** (P6). Every item in them is a compile-time module or a hardening pass measured the same way — the wasm delta of guardrail 6 — and each is independently shippable.
- **P0 is new.** None of the nine could be checked by anyone but the session that wrote it: the image harness and the bench entry points live in `out/`, which `.gitignore:5` excludes.

### P0 — The gate

**Goal.** Make every later phase checkable by someone who is not the session that wrote it.

**Par.** Not applicable — this is the precondition, and on this axis the references are behind, not ahead: GPUI has no golden-image suite, and GPUI.md:62 records that no GPUI renderer counts draw calls, batches or instances. Void owns five backends and claims identical pixels across them; that claim is checked by pixels, not by reading.

**Lands** (all committed, 2026-09-20):

- `tests/capture/capture.{c,h}` — the D3D11 readback moved in from `out/tmp/`, behind one
  signature, plus `glReadPixels` for GL/GLES3 (written, not yet exercised by a GLES3 build)
  and a PNG writer through `deps/stb/stb_image_write.h`. Two capture slots, so the same
  frame can be grabbed twice and the two compared before either becomes a golden. Every
  other backend reports itself absent, so the gate says SKIP and never PASS.
- `tests/golden/{table,scenes,runner,compare}.ms` and `tests/golden/pngio.{c,h}` — the table
  as data (no GPU, so the comparator links no sokol), the builders, a one-scene-per-process
  runner and a comparator that applies the tolerance and PENDING policy.
- `tests/golden/d3d11/` — **37 scenes** at P0, **48** after P1 turned the filter rows on, **67** after P2 added the instanced primitives and their boundary cases, **69** after P3's `text/cjkFallback` and `text/fontStyles`, and **72** with P4's `text/filteredDpi125`, `text/decorations` and `text/caretSelection`.
- `tests/bench/bench{Ui,Sprites}.ms`, `check.ms` and `baseline.json`; `bench2d.ms` emits one
  machine-readable row per metric.
- `tests/PENDING.md`, opening with an index that maps every "Known defects" line to the row
  or the `regress/` golden that covers it, then the rows themselves: every unrenderable
  scene, every backend without a readback, every unwired oracle, and the two debug-build
  aborts P0 found.
- `scripts/gate.sh` — the first gate this repo has had — and `scripts/golden.sh`.
- `scripts/emccShim.c`, `scripts/build-emcc-shim.sh` and a reworked `scripts/build-web.sh`:
  emscripten ships `emcc.bat`, not `emcc.exe`, and msc spawns its C compiler as an
  executable, so an `--os=emcc` build on Windows died before compiling a line. The shim is
  committed so it stops evaporating into a scratchpad.
- `scripts/web-liveness.sh` — headless Chrome loads the built demo and the script checks the
  canvas is not blank. Liveness, explicitly not conformance.
- Three small renderer-side changes the harness needed: `voidRunConfigured` (sample count
  and high-DPI as parameters), `Scene.presentAt` (an explicit DPI, so a scene can pin 1.25
  or 1.5 on a 1.0 display), and `staticBuffersAlive`/`staticBuffersFailed` counters.
- [TESTING.md](TESTING.md).

**Defects closed.** None. Each becomes a listed, failing case, so the phase that fixes it deletes its entry in the same commit.

**Exit — what was asked, and what was measured.**

| Exit criterion | Result |
|---|---|
| `sh scripts/gate.sh` green on this box | **GATE GREEN**, 13 loud skips, ~40 s, from a tree with no `out/` at all |
| T0 green | 431 tests |
| every golden scene green on D3D11 | **37 / 37 byte-identical, zero tolerance budgets** |
| both web backends built | **yes** — 509 672 B wasm (WebGPU), 410 724 B (WebGL2) |
| both web backends captured in headless Chrome and compared to the D3D11 goldens | **not met.** The wasm build has no readback, so there is nothing to compare. What exists instead is liveness: WebGL2 draws the demo headless; WebGPU builds and runs but headless Chrome hands it no adapter. What conformance would take is written into [TESTING.md](TESTING.md) "Guardrail 9" |
| bench rows within baseline | ten counters gated, two milliseconds reported |
| Metal, iOS and Android reported as SKIP with a reason | yes, plus GLES3 desktop, WebGPU and WebGL2 — seven surfaces, one measured |
| the baseline reproduced by a committed command | `sh scripts/gate.sh`, via `tests/bench/check.ms` |
| the three harness self-checks pass | yes: the hand-computed scene, the deliberately wrong golden, and two draws of the same state compared before either is written out |
| `tests/golden/` under ~600 KB | **not met: 826 687 B**, measured in bytes rather than `du` blocks. **226 976 B is the 33 UI scenes, so the estimate held for what it was about**, and **599 711 B is the four 800x600 demo frames**, which are photographic and do not compress. Recorded rather than cut, because the integration capture is the most valuable golden in the suite; the lever, if it ever matters, is demo frames |

**Defects closed.** None, as planned. Each is now a listed, failing case, so the phase that
fixes it deletes its entry in the same commit.

**What P0 found that the plan did not predict.** Four things, all recorded in
`tests/PENDING.md` and corrected above in "Known defects":

1. **The node-filter path has never worked, and it takes the whole frame with it.** A debug
   build aborts on sokol's `!_sg.cur_pass.valid`; a release build presents nothing but the
   clear colour, including the siblings drawn before and after the filtered node. It had no
   caller: no example and no test sets `Node2D.filter`. Five scenes are therefore PENDING
   until P1.
2. **Atlas-full is nondeterministic, not merely lossy.** Three distinct outputs in ten runs,
   worst pair 35.9% of the image at max delta 207.
3. **The demo entry never ran.** `src/examples/mainSokol2d.ms` declared `function main()`
   and nothing called it, so the native binary exited at once and the wasm build linked the
   renderer out: **48 064 B instead of 509 672 B** on WebGPU and **111 522 B instead of
   410 724 B** on WebGL2. It is not a compiler defect — `~/metascript/docs/CODE-STYLE.md`
   section 9 says plainly that nothing calls `main()`, on any platform — it is entry files
   written against a rule they do not follow. Fixed here for void2d, and the gate now runs
   the demo for five seconds rather than only building it, because a build check cannot see
   this class of defect at all.
4. **The "frame 90 moves by 1–2 pixels" note from earlier sessions was 4× MSAA**, not the
   renderer. At `sample_count` 1 every scene is byte-identical across processes. Which is
   also the right setting for a golden set that five backends must match, since MSAA is on
   for the sokol_app entry only.

**Tests.** This phase *is* T2, T4 and the harness self-checks.

**Measure.** Nothing in the renderer moves. The point is that every later number is
comparable to a baseline anyone can regenerate.

**Unblocks.** Every phase. Without it, "no phase leaves the demo broken" is an assertion
nobody can check — and, as it turned out, an assertion that was already false.

**Risk → fallback.** The suite is written against a renderer P1 and P2 are about to rewrite, so most goldens are regenerated twice. That is the intended use, not a cost to avoid: the regeneration diff is the review artifact each change deserves. The real risk is the opposite one — freezing goldens later, against a renderer nobody can compare to what came before. No fallback is needed; if the scene table proves too large to regenerate comfortably, cut scenes from `prim/` and `image/` first, never from `regress/` or `harness/`.

### P1 — The display list

**Goal.** Nothing touches the GPU while the tree is walked: one command stream, one upload per bracket, draws over ranges.

**Par.** GPUI's frame shape exactly — build, finish, one `write_instances`, a pass that is only draws (GPUI.md:18) — minus the per-kind `Vec`s and the BoundsTree (guardrail 1), plus per-target lists hoisted so a filter never nests a pass.

**Lands.**

- A flat POD command stream and instance stream; `draw.ms` emits into it, `batcher.c` replays it. Each command records **why** it broke the previous batch, so a T1 snapshot names its own cause.
- One growing instance buffer — `max(2×, pow2)`, no shrink, a cap, a dropped frame with an error past it (GPUI.md:63) — replacing the per-node `sg_buffer` and the fixed 65536-vertex stream (`batcher.c:19`, `:85`).
- Per-target command lists, children recorded before consumers, replayed with no nesting (MAKEPAD.md:99; sokol asserts `!in_pass`).
- Filters to h2d semantics: the node itself enters the target, alpha applied once, the target in object-local space through a filter matrix, bounds clipped to the viewport, a frame-linear target pool, one subtree sync (HEAPS.md "The h2d contract").
- The blur kernel corrected — downsample by 2^k then blur at a 1-texel step (guardrail 3) — instead of multiplying tap spacing by the radius.
- `begin2d` takes a float logical size; the `int32` truncation goes.
- Clamp samplers, `smooth` as a tri-state with a scene default, `tileWrap`. **Its own commit**: it changes edge pixels.
- fontstash's `FONS_ATLAS_FULL` handled and the `fons_resize` image/view leak fixed — a holding fix, superseded when P3 removes fontstash.
- Frame counters: draw calls, instances, uploaded bytes, buffers and images alive. GPUI counts none of them (GPUI.md:62); T1 and T4 both read them.

**Defects closed** (named, with their sites): the ~126-node limit from one `sg_buffer` per Label/Graphics against sokol's 128 pool; the nested pass (`render.ms:216-283`, `scene.ms:88-102`); filter semantics and the double alpha; the blur kernel (`shader2d.glsl:81-87`); fractional-DPI truncation (`scene.ms:89`); REPEAT samplers (`batcher.c:136-143`); atlas-full (`batcher.c:147-148`, `:61-65`, held); the per-frame vertex cap; GPU calls issued during the walk (`batcher.c:218-251`, `draw.ms:264-277`, `:307-320`); a text change destroying its GPU buffer (`render.ms:110-111`).

**Exit.**

- All 10 000 labels of the bench UI scene draw. GPU buffers alive is constant in the node count.
- No **draw** and no **upload** happens between the start and the end of the tree walk — assertable, because the stream is the walk's only output, and asserted in T1 (`tests/displayList/snapshot.ms`, "the walk records and uploads nothing"). **Restated during P1's review**, because the criterion as originally written said *no `sg_*` call* and that is not true and was being reported as met: `acquireTarget` reaches `sg_make_image` when a filter first needs a target of a given size, and a glyph that does not fit reaches `sg_make_image` through `fonsExpandAtlas`, both inside `draw()`. Those are **resource creations, not frame work** — they happen once per new size and once per atlas growth, never per node and never per frame, and GPUI's own atlas does the same. The property that matters, and that P2 and P5 depend on, is that the walk issues no draw call and moves no bytes; that one is true and now has a test. Hoisting the two allocations to frame begin would need the walk's target sizes known before the walk, which is P5's retained-bounds work.
- Blur, Glow and DropShadow on a subtree compose as h2d does; group opacity does not double-blend.
- At DPI 1.25 and 1.5 box edges and text baselines land on device pixels.
- Golden regeneration is confined to `filter/`, `snap/` and the sampler-affected scenes; every other scene stays byte-identical.

**Tests.** **T1 is created here** — this is the tier the display list buys. It asserts painter's order; one upload per bracket; target lists before consumers and never nested; the growth policy at its boundary and the drop-with-error past the cap; and that recording an unchanged tree twice is byte-identical. T2 regenerates `filter/` and `snap/` and gains one `regress/` scene per defect above. T4 gates buffers-alive and draw calls.

**Measure,** taken 2026-09-20 on D3D11, `--release`, 1280x720, `sample_count` 1, 20 warm-up
and 120 measured frames; the committed row is `tests/bench/baseline.json`.

| | planned | measured | |
|---|---|---|---|
| Labels drawn | 126 → 10 000 | **10 000** | met |
| GPU buffers alive | constant in node count | **2**, was 126 | met, and the counter was made able to move |
| Uploads per bracket | 1 | **1** | met |
| Dropped frames | 0 | **0** | met |
| No draw or upload during the walk | asserted | **T1 asserts it**; `sg_make_image` for a new filter target or an atlas growth still happens in the walk, restated above | met as restated |
| `benchSprites` | unchanged, 1.7 ms / 1 draw | **1.63 ms / 1 draw** | met, guardrail 8 holds |
| `ui.draws` | ≤ 253 | **20 000** | **not met** |
| `ui.present` | ≤ 4.5 ms | **17.8 ms** | **not met** |

The last two were never reachable and the estimate was wrong, not the renderer. The bench UI
scene alternates a white-texture card with a font-texture label on every node, so the texture
binding changes at every node: 126 labels cost 253 draws, and therefore 10 000 labels cost
20 000. A display list records that alternation faithfully; it cannot collapse it. What
collapses it is one pipeline for both kinds plus a white texel in the glyph atlas, so that the
card and the label share a binding — and that is P2's first item, listed there, not here.
Pulling it forward would have made this table look right and left P2 measuring itself against
a number it had already spent.

Two batching wins that *do* belong to the display list were taken: a uniform block is re-bound
only when its contents change, and a pipeline only when it differs from the one already set.
Together they moved `ui.present` 20.4 → 17.8 ms at an unchanged draw count.

`ui.present` is reported, not gated — this is a shared developer box, and repeat gate runs on
an otherwise idle machine span 17.9–18.9 ms. The counters are what gate hard.

**Unblocks.** Everything: P2 needs the instance stream, P5 needs the command stream to hold persistent ranges.

**Risk → fallback.** The display list and the filter rework are two large changes whose goldens overlap, which makes a regression hard to attribute. Fallback: land the stream, the growing buffer and the counters first (no golden moves except the sampler commit), then filters as a second commit with its own regeneration. The exit does not change, only the shape of the diff.

### P2 — Instanced primitives

**Goal.** One shader, one instance layout, a per-instance `mode`; a UI subtree in tree order costs about one draw call and stays correct under an affine.

**Par.** GPUI's primitive look — per-corner radii, per-side borders, dashes, `erf` shadow drop and inset, per-pixel sRGB and Oklab gradients with dither, image `corner_radii` / `grayscale` / `ObjectFit`, the pixel-snapping rules — with the SDF re-derived in local space so it survives rotation and scale (GPUI.md:35-39), and without the per-kind pipelines that force GPUI's BoundsTree.

**Lands.**

- The flat sprite pipeline (64 B) that never runs SDF math, and the unified UI pipeline (~92 B packed) with modes box / shadow / glyph / image / underline / selection, plus a white texel in the glyph atlas.
- Local-space rounded-rect SDF: AA width `0.5 / scale`, `fwidth` otherwise, quad inflated ~1 device pixel. Shadow, fill and border in **one** instance with the quad inflated by the shadow extent (MAKEPAD.md:47); the standalone shadow mode stays for drop and inset.
- Per-pixel gradients with dither, keeping Void's radial and multi-stop; slash and checkerboard patterns.
- Snapping when the world transform is axis-aligned: independently rounded edges, `snap_stroke` 0→0 else ≥ 1 device pixel, `cover_bounds`, snapped offsets; complementary rounding for fractional splits (GHOSTTY.md:61); a `dpi_dilate` uniform for hairlines inside SDF shaders (MAKEPAD.md:49).
- Clip by four edge distances with `discard`, correct under a rotated Mask (replacing the scissor AABB at `render.ms:204`); CPU cull against the **active clip**, not the viewport (`render.ms:191-201`).
- `Tile.dx/dy` with `center()` / `setCenterRatio()`, so the pivot means one thing across node kinds instead of being applied for Rect/Sprite/Anim, ignored by ScaleGrid, Label and Graphics, and reinterpreted by Mask.
- Box and image style into side tables (guardrail 2; `Node2D` carries 71 fields).
- Glyph mode fed by fontstash. No text behaviour changes in this phase.

**Defects closed.** The pivot inconsistency and missing `Tile.dx/dy`; the rotated-Mask scissor AABB; culling against the viewport instead of the clip; per-vertex sRGB gradients. Not on the defect list but closed here: box-shaped UI stops depending on MSAA for its antialiasing, which today is on only for the sokol_app entry (`bridgeWin.c` `voidRun`) and off on iOS, Android and embed — paths themselves wait for P6.
The gradient slice stays on the existing vertex pipeline: `Graphics` keeps arbitrary polygon
tessellation and painter order, while each contiguous range selects an sRGB/Oklab gradient or
pattern through the existing effect record. That avoids a second geometry path and leaves the
UI instance layout unchanged. T0 pins published Oklab coordinates and the zero-mean 4×4 dither;
T1 pins range order and effect payloads; T2 pins sRGB, Oklab, radial, multi-stop, low-contrast
dither, slash and checker output, including an affine Oklab/sRGB comparison at DPI 1.25.
The image slice activates mode 3 only for styled `Sprite` and `Anim` nodes; unstyled sprites stay
on the 64-byte flat pipeline and therefore keep guardrail 8. A payload-indexed side table owns
per-corner radii, Rec.709 grayscale and the five GPUI `ObjectFit` choices. Fit is CPU arithmetic;
`Cover` crops UVs to the visible centre while the other modes change or clip the destination
bounds. T0 pins all fit branches and side-table reuse, T1 pins the image instance lanes, and T2
pins all five fits, an affine translucent four-radius image, and original/grayscale output.
The UI program has no arbitrary colour matrix, so combining an image style with `colorMatrix`,
`colorAdd` or `colorKey` is rejected loudly instead of dropping either effect silently.
BoxStyle with `colorMatrix`, `colorAdd` or `colorKey` emits a named runtime diagnostic and rejects
instead of silently falling back to a square vertex quad and discarding radii, borders and
shadow. Plain Rect keeps the existing vertex colour pipeline. P6 owns carrying that pipeline
through the unified UI shader; `tests/PENDING.md` names the unsupported combination.
Underline and selection activate modes 4 and 5 through retained nodes without adding a second
instance layout. A wavy underline uses GPUI's three-thickness bounds and sine-distance shader;
the straight form is the same mode with a strip distance. Each selection row carries the
neighbouring rows' relative x and width, then ports Makepad's radius-2 smooth union at
gloopiness 8. Its quad grows horizontally by that join radius but not vertically, so adjoining
translucent rows share an edge instead of double-blending an AA fringe. P4 still owns font
metrics, decoration placement, selection construction and caret blink; P2 supplies only the
retained primitives those behaviours emit. T0 pins the distance arithmetic and retained
bounds, T1 `textPrimitives` pins production reachability and all parameter lanes in one UI
run, and T2 `prim/textModes` pins affine translucent straight/wavy and ragged-row joins.
The Tile/pivot slice adds h2d's `dx/dy`: Sprite, Anim and ScaleGrid draw from that visual
offset, scaled when a node overrides the Tile's draw size, and flips mirror the offset with
the UVs. `center()` returns a centred value; `setCenterRatio` is a free writer because the
installed compiler cannot express a `ref this` receiver. Node `pivotX/Y` moved from selected
kinds' bounds into the affine itself, so Rect, Graphics, Label, Mask and every child now rotate
and scale around the same local point. T0 pins centre/ratio/flip arithmetic, scaled Sprite
bounds, pivot mutation and child propagation; T1's rotated-Mask stream pins the child move; T2
`xform/pivot` and `xform/tilePivot` pin the two contracts, while the Graphics-pivot demo and
Oklab captures move as the defect requires.
Dashed borders reuse GPUI's border style and arc-length layout without adding an instance:
the existing box parameter lane carries the style bit, rounded boxes run one clockwise phase
around all four sides and corners, and square boxes restart each side so both ends are dashes.
Dash length is twice the local border width with a one-width gap; per-side widths select their
own phase velocity, adjacent sides choose the slower corner velocity, and the final period is
adjusted to close without a seam. The dash mask multiplies only the analytic border ring, so
fill and the one-instance drop/inset shadow remain unchanged. T1 `boxStyle` pins the style bit
beside asymmetric radii and widths; T2 `prim/dashedBorder` pins rounded, square, rotated,
asymmetric and shadowed forms. T2 `snap/zeroBorder` separately proves a bright zero-width
border contributes no pixels.

Filter targets now separate physical storage from logical projection: allocation and blur radius
use device pixels, while the target viewport and composite quad stay in logical units. The
`filter/maskAtDpi150` golden moved from a low-resolution white frame to the intended masked,
blurred subject. `Scene.presentAt(dpi)` remains the explicit host/test input rather than retained
scene state: the framebuffer ratio can change between presentations, and the golden runner must
pin it per row. `begin2d` retains the value only for that frame's target allocation and scissors.
Unified-UI snapping and analytic AA use that same active target scale: CPU edge/stroke rounding
operates in device pixels and the shader converts one physical pixel back through both DPI and
the node affine. A DPI-1.5 target therefore does not inherit the swapchain's logical-pixel AA.
Mask scissors use `cover_bounds`: floor the near edge and ceil the far edge after target-scale
conversion, so the coarse hardware rect cannot discard a fragment accepted by a rotated Mask's
exact planes. For axis-aligned shadowed boxes the visible fill/border edges snap first, then the
separately snapped shadow offset inflates the quad; a fractional blur margin cannot move the
visible box back off-grid. Rotated boxes cannot snap edges without changing shape, so the shader
applies `dpi_dilate` per local axis: zero remains zero and every positive border is at least one
physical pixel.

The same `boxRenderBounds` result owns UI emission, viewport/Mask culling and public subtree
bounds. An outset analytic shadow therefore keeps drawing when only its penumbra reaches the
viewport, and a node filter allocates for that shadow before adding its own radius; inset shadows
do not enlarge either bound. T0 pins the public bound, T1 pins shadow-only visibility and
`filter/blur` composes an analytic shadow with a render-target blur.

The vertex path's `srcPremult` correction is intentionally disabled when an RGB colour add or
non-identity RGB matrix is active. That is required for the glow/drop-shadow alpha-only matrix:
it must turn the sampled render target into a new straight-colour silhouette before the shader
premultiplies it. The same gate would be wrong for an unrelated matrix applied directly to a
render-target texture because it would multiply coverage twice. The retained filter path avoids
that combination by applying node effects inside the target and resetting the composite; direct
render-target drawing must not combine an arbitrary colour matrix with that source until the
shader has an explicit unpremultiply-transform-premultiply path.

Every golden row now gates its draw count and live pooled-render-target count as well as pixels.
The expectations, 67 at P2, 69 at P3 and 72 in P4, live in table order beside the scene table; a pixel-identical draw-call
regression or target leak fails before the PNG is written. T1 also closes the batch-reason
cross-check: production `breaks`, `gradients` and `clip` scenes reach first/view/blend/sampler/
pipeline/effect/clip, and a no-GPU target bracket reaches barrier.

**Exit.**

- The bench UI scene draws in ≤ 4 draw calls.
- A rounded, bordered, shadowed card is one instance; at 37° its corner AA and border width are still right and its clip does not leak outside the rotated Mask.
- At DPI 1.0, 1.25 and 1.5 a one-device-pixel border expressed as `1 / dpi` logical units is
  exactly one device pixel, a zero border is zero, and the two halves of a 7-logical-pixel
  split touch with no gap.
- A sprite-only scene evaluates no SDF math — assertable in T1 by mode counts.

**Tests.** **T3 coverage oracle**: the rounded rect and the `erf` shadow supersampled 16×16 per pixel on the CPU, compared against the capture within a stated bound. This is the only tier that says the AA is *correct* rather than merely unchanged. T1: instance counts per mode, batch-break reasons on the bench scene, the snapping rules as numbers at three DPIs, and a scrolled list emitting nothing for off-clip rows. T2: `prim/`, `xform/`, `snap/`, `clip/` regenerated. T0: Oklab conversion, dither, the SDF distance function.

**Measure.** Draws **20 000** (P1 measured, not the 253 this line used to anchor on) → **1**;
the 20 000 nodes emit **48 890 UI instances × 108 B = 5 280 120 B**, the gated phase-end
measurement that replaces the ≈ 92 B estimate. The two millisecond figures this line used to
carry were both anchored on numbers that do not exist, and were corrected on 2026-09-21 when
the baseline was re-taken (see "Baseline" (b)):

- `present` ≤ 2.0 ms was set against a baseline of 17.8; the measured before is **19.9 ms**. The target is kept, because it is not arithmetically impossible the way P1's `≤ 253 draws` was — 20 000 draw calls at ~1 µs each is essentially all of the 19.9 ms, and removing them removes it. It is recorded as **optimistic**: the nearest measured floor on this box is `benchSprites`, which does *half* the nodes in *one* draw and still costs 2.5 ms. P2 is not failed by missing 2.0 — milliseconds never gate — but the phase reports the real number and says which of the two predictions it landed on.
- `benchSprites` ≤ 1.7 ms was derived from the unreproducible 1.63. **The guardrail-8 check is no longer a constant**: it is "no worse than the re-taken 2.5 ms (2.2–3.1), proven by an interleaved same-box A/B", because a fixed 1.7 would fail this phase on its first run for a reason that has nothing to do with this phase. The draw count stays absolute: `sprites.draws` is 1, and that gates.

**Unblocks.** P3 writes the glyph layer against a final instance layout; P5's persistent ranges need stable per-instance bytes.

**Risk → fallback.** One stride has to serve every mode, and ~92 B packed is an estimate from a planned layout, not a measurement. Past 15 `vec4` it breaks WebGL2's 255-byte stride ceiling (MAKEPAD.md:23), and 4-vertex instances have not been checked against indexed quads on a Mali or an Adreno. Fallback: two strides — a narrow box/glyph one and a wide one for gradients and shadows — which costs one batch break where they interleave and is still four pipelines fewer than GPUI's eight. Decide on the measured layout and record it; do not defend the estimate.

### P3 — The glyph layer

**Goal.** void2d owns text rasterization end to end, and a 13 px code font at 1× and 1.5× lands on the pixel grid.

**Par.** GPUI's text path where it is best — logical unhinted float layout, four x-variants with a whole-pixel baseline, 1:1 texel-exact sprites, the atlas key, the gamma and contrast function with its table — plus the font-collection model Ghostty has and GPUI does not, and without GPUI's three platform text systems, which are what guardrail 9 forbids.

**Lands.**

- fontstash out. stb_truetype v1.26 in: GPOS, `stbtt_MakeGlyphBitmapSubpixel`.
- Logical float layout, never rounded; the node holds its shaped layout. Four x-variants at 1/4 device pixel, baseline on a whole device pixel, sprites drawn 1:1.
- Coverage atlas pages at 1024² with a 1 px gutter, a CPU mirror per page, dirty pages uploaded once per frame, ref-counted tiles, and a repack that never moves a live tile (GHOSTTY.md:51).
- `Font { family, weight, style, features, fallbacks }` from bytes (what landed and what moved to P4 and P6: "Fonts" in Conclusions); the Ghostty collection model — ordered faces per style, deferred faces, explicit-versus-fallback presentation, a codepoint→face map that caches misses, whole-grapheme selection, fallback size harmonisation, synthetic bold and italic, CJK and emoji families loaded on a real miss.
- Gamma and contrast per fragment with GPUI's function and 13-row table.
- Decoration position and thickness from `post` / `OS_2` with broken-table fallbacks.
- The text metric surface the Neon host needs: `textWidth`, `calcTextWidth`, `splitText`, per-glyph x, line boxes — the same layout the node will paint, feeding Yoga's measure callback.
- `lineSpacing` in pixels, as h2d has it, replacing today's multiplier (`text.ms:49`).

**Defects closed.** Atlas-full, as a class rather than a patch. Integer glyph origins and rounded advances (`fontstash.h:1230-1244`, `:1314`). `kern`-only metrics. `split(" ")` wrapping (`text.ms:19`). The 16-font limit (`batcher.c:35`). No `textWidth`. The R8→RGBA CPU expansion and full atlas re-upload on any new glyph (`batcher.c:345-360`, `:207-216`). Text lines centred on fractional pixels (`text.ms:7`).

**Both open decisions resolve here.**

*The rasterizer — stb_truetype only, or FreeType as well.* The decision is **not** "module or not". Guardrail 9 requires one rasterizer everywhere, so a FreeType module that is compiled out of the web build would produce different pixels in the browser and break the guardrail it is meant to serve. The real question is whether FreeType ships in **every** build including wasm. Experiment: rasterize the same code-buffer sample at 13 px / 1×, 13 px / 1.5× and 14 px / 1.25× through (a) stb_truetype unhinted with the four x-variants and the gamma table and (b) FreeType with light hinting, both through the same pipeline; capture both through the P0 harness; compare side by side with a Zed capture taken under the T5 protocol. The evidence that decides: at 1×, whether unhinted stems land on the pixel grid darkly enough that the gamma and contrast table cannot close the gap, judged on stem darkness and stem-to-grid alignment; against that, the wasm delta of FreeType in both web backends, measured, not assumed. Constraint if FreeType comes: hinting only in the pixel-exact regime, the outline shifted **before** hinting, and hinted advances never fed back into layout (GHOSTTY.md:42; the integer-advance defect is what fontstash is being removed for). Default if the evidence is ambiguous: stb_truetype only — it is what macOS and Ghostty-on-macOS ship, and it is one dependency rather than two.

**Resolved at P3 step 8: stb_truetype only.** `sh scripts/experiment-rasterizer.sh [--wasm]` (`tests/experiments/`, FreeType 2.13.3 fetched by `VOID_FREETYPE=1 sh setup.sh`) draws one five-line code sample, light on dark, through the same atlas, gamma table and capture path with three rasterizers behind one seam (`void2dGlyphSetRasterizer`), and measures the capture: total ink, the share of ink in pixels covered ≥ 0.85, and the share of touched pixels that are grey. Deterministic run to run. FreeType unhinted matches stb within 1 % of ink and 0.5 pp of solid share, which proves the comparison isolates hinting. Light hinting raises the solid share by **2.5 pp at 13 px / 1×** (0.435 → 0.460), 1.8 pp at 13 px / 1.5× and 3.6 pp at 14 px / 1.25×, and at 1× the text is 3.8 % lighter. The zoomed captures show where: tops of the x-height and the baseline snap, **stems do not move** — light hinting is vertical only, so the `l`, `i` and `|` stems of all three arms are the same two-column greys. The question this experiment was set, whether stems land on the grid, is one FreeType light hinting does not touch. Its price is **+355 880 B in WebGPU and +356 158 B in WebGL2** (759 941 → 1 115 821 and 665 144 → 1 021 302, +47 %), about 12.6× the whole glyph layer. Because light hinting shifts only in y, the constraint "outline shifted before hinting" holds trivially for the x-variants. What stays owed is the T5 look beside Zed (Zed is not installed on this box); it can move the verdict on stem darkness only, and the lever for that is stem darkening or variable-font axes at P6, not a second rasterizer.

*Atlas page kinds — separate R8 and RGBA pages, or four coverage planes per RGBA page.* Experiment: both allocators behind a flag, one workload — a code buffer at three sizes and two DPIs, plus UI icons and an emoji run — measuring pages allocated, bytes resident, bind-slot changes per frame (which are batch breaks, so T1 sees them), and whether the per-instance plane selector costs any instance bytes. The prediction to test: sokol replaces a **whole image** per update, so a dirty coverage page costs 1 MB on an R8 1024² page and 4 MB on an RGBA four-plane one, and the four-plane page holds 4× the glyphs but is re-uploaded whenever any of its planes is dirty — a 4× upload penalty per new glyph, on the target where "upload bandwidth is scarcer" (see "Web and WebGPU"). Four planes wins only if it removes enough bind-slot changes to pay for that. Default if the measurement is a wash: R8 + RGBA, the simpler allocator and the smaller upload.

**Resolved at P3 step 8: R8 + RGBA.** `tests/experiments/pageKinds.ms` runs one workload through the real atlas and packer and reads it both ways (plane p of the four-plane layout is R8 page p on RGBA page p / 4, so one run answers both). The defined workload — code and prose at 12, 13 and 14 px at DPI 1.0 and 1.5 plus a 24-symbol icon run at 16 and 24 px, 3 456 glyphs, 1 384 tiles — fits **one** page either way: 1 MiB resident as R8 against 4 MiB as RGBA, 0 page switches either way, and every new glyph re-uploads 1 MiB against 4 MiB. Four planes win only under stress: ten sizes at four DPIs (5 910 tiles) need 3 R8 pages and switch pages 738 times in that draw order, where one RGBA page switches none — at 4 MiB against 3 MiB resident and the 4× upload per new glyph. The plane selector would cost no instance bytes (glyph mode leaves `params0.yzw` unused). Emoji do not enter the comparison: they need all four channels, so they take RGBA pages under both layouts and are not rasterized yet (`tests/PENDING.md font-colour-emoji`). If multi-page frames become common, binding several R8 pages at once removes the switches without the 4× upload.

**Exit.**

- The `text/` scenes at DPI 1.0, 1.25 and 1.5 are byte-identical across runs, and the 13 px capture is judged beside Zed under the T5 protocol, with the verdict written into this doc.
- Glyph rasterizations per frame reach 0 in a steady state; atlas bytes after a zoom sweep are bounded.
- `textWidth` and per-glyph x exist and agree with the painted layout — the same numbers feed measurement and paint.
- A missing glyph resolves through the fallback chain; a codepoint miss is cached.
- The **first five-backend conformance run** (TESTING.md guardrail 9) happens here, because text is where backends diverge most.

**Tests.** T3: fontTools for font and decoration metrics; the HarfBuzz oracle restricted to cmap and GPOS kerning with features off. T1: the four x-variants and the baseline snap asserted as exact numbers. T2: the `text/` group. T4: atlas pages and bytes gated; rasterizations per frame gated.

**Measure.** Against the baseline UI scene: draws unchanged from P2, `present` not worse. New rows: first-paint warm-up cost, atlas bytes after the zoom sweep, wasm delta of the glyph layer per backend.

**Measured at P3 step 8 (2026-09-24, D3D11, msc release, this box at 25-33 % CPU load).**
- **Draws unchanged**: `ui.draws` 1, `text.draws` 1, 48 890 UI instances as at P2 (`tests/bench/baseline.json`).
- **`present` is worse, and the phase does not meet this line.** `sh scripts/bench-ab.sh` interleaves pairs against the tree just before P3 (`8a473f3`, same `main` base): UI **26.66 → 29.35 ms** over eight pairs, ranges disjoint, sprites unchanged (4.93 → 4.93 ms). Bisected: step 3 alone carries it (step 3 against the head, 25.70 against 25.49 ms), and a phase timer put all of it in the walk's label emission, about +0.9 ms of 5 ms. The page view is now looked up once per page rather than twice per glyph and the per-glyph `vec2` temporaries are gone, which took the gap to **+1.4 to +1.8 ms (+5 to +7 %)**. What remains is a fixed cost per label per frame — the side-table read and the placement check, 140 to 180 ns per label over the bench's 10 000 labels, most of it reference counting in the generated C. P5's retained ranges remove the re-emission of unchanged labels altogether, and that is where it is owed; it is not worth a codegen workaround here.
- **Re-taken at P3.5 on a quiet box (2026-09-25): the 2.2× was load, and P3's own cost is about +0.5 ms.** Both arms above read about 2.2× P2's 12.13 ms. `scripts/bench-ab.sh` now samples load before and after every run and drops a pair with a sample over 40 % (TESTING.md "T4"). All 16 pairs were clean (13-25 %), on msc 0.2.55 (BUILD `8cdd91c6`), the three trees built the same day. P2's ship tree `2255d9f` reads **13.43 ms** against the pre-P3 tree `8a473f3` at **13.37 ms**: nothing between P2 and P3 moved it. `8a473f3` reads **12.76 ms** against the head at **13.29 ms**, +0.53 ms (+4 %) with the ranges overlapping, and that is P3's cost. Sprites read 1.81 to 2.54 ms against P2's 1.77, on untouched code, so P3's 4.93 was the same load. The same binaries read 14.5 to 24 ms while other sessions compiled beside them, and one run read 24.3 ms after a pre-run sample of 26 %: a sample taken only before a run misses a compile that starts during it, which is how the 26-29 ms were minted. About 1 ms stays unattributed (P2's 12.13 on msc 0.2.53 at 11.8 % load, 12.8 to 13.4 today). That is within the 0.6 ms this box drifts between two windows ten minutes apart (`8a473f3` read 12.76, then 13.37), and no 0.2.53 binary survives to separate the compiler from the background, so there is no compiler card.
- **The P3.5 head, 2026-09-25, against the same control: UI 13.54 → 13.05 ms.** `8a473f3` against `d56e513` (P3.5's source; `9d8b139` after it only moves the `Resize` arm of a per-frame `match`) under the 25 % limit: 7 of 8 UI pairs clean, ranges 12.79-14.91 and 12.68-13.64 ms overlapping; sprites 2.61 → 2.59 ms over 5 clean pairs. The frame-path arrays P3.5 removed (−0.69 ms, `9115c7b`) outweigh P3's +0.5 ms. The same window gave the P3 head against `d56e513` no clean UI pair (samples 17-68 %), so P3.5's own delta, about −1 ms (the P3 head +0.53 over the control, the P3.5 head −0.49 under it), is read across two windows, not from one pair.
- **First paint**: 40 rasterizations for the UI bench (10 digits × 4 x-variants), 63 for the 40-line code block; 3.5 ms for the text scene's first frame.
- **Zoom sweep**: 0.5× → 4× over 64 frames rasterizes 3 907 glyphs and never holds more than **2 pages (2 MiB)**; after it, **0 rasterizations per frame** — the steady state the exit asks for, now gated as `glyphRasterizationsSteady`.
- **wasm delta of the glyph layer**: against the pre-P3 tree built the same way, WebGPU **731 641 → 759 941 B (+28 300)** and WebGL2 **636 966 → 665 144 B (+28 178)**, fontstash removed and stb_truetype 1.26, GPOS, the atlas, layout, fallback, `Font` and synthetic styles added. After the review's defect fixes the gate at `682966f` built **761 810 B** and **667 012 B** (+30 169 and +30 046 against the same pre-P3 tree).
- **Conformance: the exit's five-backend run is not met — 2 of 7 surfaces measured.** D3D11 69 / 69 byte-identical; WebGL2 65 / 69, and all seven `text/` scenes are byte-identical there. The WebGL2 number is narrower than a second driver: headless Chrome reports `ANGLE (NVIDIA, NVIDIA GeForce RTX 5090 ... Direct3D11 vs_5_0 ps_5_0, D3D11)`, so it proves the GLSL ES path, GL's conventions (the dither bug above was one) and ANGLE's translation, on the same GPU and D3D11 driver. GLES3 desktop and WebGPU move to P6, which can run both on this box; Metal macOS, Metal iOS and GLES3 Android wait on the human's hardware (`tests/PENDING.md backend:*`).
- **The Zed half of the first exit bullet is not met** either: the T5 capture beside Zed is owed by the human (above). The byte-identical half is met: the gate captures every `text/` scene twice, at DPI 1.0, 1.25 and 1.5.

**Unblocks.** P4; and the Neon host's Yoga measure callback, which is the gate on a Void-backed Neon app rendering text at all. The host can bind it now. P3.5 made one measure call cost one glyph lookup per glyph, gated in T4 as `text.measureGlyphLookups` (80 for the bench's 80-character line, 176 before the face's heights and decoration were measured once per face), and stopped `textWidth` and `textHeight` copying the layout (REVIEWS.md P3 F2). The font API's shape under CODE-STYLE §14 (F9) is still open: its app-visible half is the human's call.

**Risk → fallback.** This is the largest phase and the one carrying both open decisions. If the 1× captures are not good enough with stb_truetype and FreeType's wasm cost is unacceptable, the fallback is not a second rasterizer but a narrower claim: ship the pixel-exact regime at DPI ≥ 1.25 where unhinted coverage is sufficient (GPUI ships exactly that on macOS), record 1× as a known weakness with its captures, and revisit with variable-font axes or stem darkening in P6. Do not resolve it by adding a per-platform text path — that is guardrail 9.

### P4 — Text runs and the editor surface

**Goal.** A read-only code-editor view: syntax-coloured runs, decorations, selection and a caret, correct and cheap.

**Par.** GPUI's shaped-line model — `TextRun`, a style change splitting the shaping run so a ligature is never two-tone, run backgrounds as quads painted before glyphs, underline and strikethrough as their own primitive, wrap boundaries and truncation and `x_for_index` / `index_for_x` / `force_width` / `split_at` all over shaped glyphs (GPUI.md:46-49) — with Ghostty's caret and selection discipline on top, and Makepad's selection geometry.

**Lands.**

- `TextRun { len, font, color, background, underline, strikethrough }`; a style change splits the run.
- Run backgrounds, underline, strikethrough and wavy as instances of the UI pipeline, with thickness and position from the font metrics P3 extracted, snapped.
- Wrap boundaries indexing the unwrapped glyph list, so a width change never re-shapes; the CJK break rule; hanging indent; truncation at start, middle and end; `force_width` snapping base glyphs to a monospace cell grid with combining marks left attached; `split_at` cutting a shaped line without re-shaping. **Landed in P4** (`textLayout.ms` `shapeText` / `wrapText`, cached per label in `labelText.ms`): a label shapes again only when its text, font, size, letter spacing, runs or shaping breaks change, and T1 holds a width change to zero glyph lookups. Line breaks are UAX #14 and computed on the first wrap that needs them; the ellipsis glyph is looked up on the first truncation that needs it. Three places where void2d is not GPUI, each for a reason: a tab on a wrapped line takes its stop from that line's start, where GPUI has no tabs; `force_width` finds a base by its grapheme boundary, because GPUI finds it by x, which holds only once a shaper has put the marks over their base; the hanging indent is the pixel value the author gives (`setHangingIndent`), where GPUI derives it from the first line's leading spaces. Truncation cuts only where a grapheme starts, and `splitAt` cuts a one-line layout, as `ShapedLine::split_at` does. A grapheme is kept only when its marks fit as well as its base. An End ellipsis trims the whitespace and ASCII punctuation before it, as GPUI's `truncate_line` does (`line_wrapper.rs:286-290`, Rust's `char::is_whitespace` and `is_ascii_punctuation`); Start and Middle trim nothing, in GPUI and here. Middle gives two thirds of the room to the front and one third to the back, as GPUI's `should_truncate_line_middle` does (`line_wrapper.rs:215-216`). A word longer than the box overflows it, as h2d's does with `wordBreak` off, its default (`Text.hx:113-118`); GPUI breaks it at the character that overflows (`line_wrapper.rs:115-122`). That is a **W**, h2d's semantics, and h2d's `wordBreak` option is not offered. `calcTextWidth` and `splitText` on a Label lay the text they are given out with the label's style and line options (`setForceWidth`, `setHangingIndent`, `setTruncate`); runs and shaping breaks index the label's own text, so they do not apply.
- `x_for_index` and `index_for_x` over glyph positions; line boxes — the geometry the host needs for caret, selection and IME candidate placement — tall enough for the tallest face on the line, where P3's use only the primary face's ascent and descent. **Line boxes landed in P4** (`textLayout.ms` `tallestFaces`, `LineBox.height`): a line is the largest ascent plus the largest descent of the faces drawn on it, plus the primary's line gap, and lines stack by their own heights, as CSS line boxes do; a line in the primary face alone keeps its height, so only `text/cjkFallback` and `text/fontStyles` moved, both of which put a fallback hanzi on every line. GPUI keeps one line height and centres the tallest face in it, which lets a taller fallback overflow the box that caret and selection read. An index that a wrap with no separator shares with the next row belongs to the upper row, as in GPUI's `WrappedLineLayout::position_for_index` (`line_layout.rs:427-454`), because `index_for_position` returns that index for a click past the row's end: the caret stays on the row clicked, and a click before the lower row's first glyph lands at the upper row's end, the trade GPUI makes as well.
- **Caret and selection as their own instances**, never part of a text range, so a blink dirties nothing else (GHOSTTY.md:90); selection as per-row quads carrying the neighbouring rows' x and width, unioned by smooth-min in the fragment shader, so concave joins are filleted with no geometry (MAKEPAD.md:78). **Landed in P4** (`setSelectionRange`, `setCursorIndex`, `setCursorBlinkTime` on a Label; `render.ms` `emitSelection` / `emitCaret`): the selection draws over run backgrounds and under the glyphs, the caret last, so T1 holds a blink to the caret's own instance and nothing else; a caret is 2 px wide (Zed's) at least one device pixel, blinks at h2d's 0.5 s through `update(dt)` and restarts when it moves; a selected line break shows as a 4 px tail. A selected row runs to its last glyph, trailing whitespace included, as an editor's does, where the line's `width` stops at its last ink. With `lineSpacing`, each row covers half of it above and half below, so rows still meet: h2d's TextInput ignores line spacing when it draws a selection (`TextInput.hx:797`), and Makepad's rows are adjacent by construction. The caret keeps the line box's height, as h2d's `cursorTile` keeps the font's line height. Under `setForceWidth` a row that ends in a mark ends at its last cell. A caret or selection index past the text is drawn at its end, as h2d's `getCursorXOffset` does (`TextInput.hx:603`). `text/caretSelection` is one draw call, and `tests/golden/invariants.ms` holds its row joins to one composite with no gap, a check shown to fail on a doubled selection and on a 4 px gap.
- Shaping break at an index, as an input on `Text` (GHOSTTY.md:35) — the mechanism, not Ghostty's terminal defaults.
- Whole-grapheme face selection: a multi-codepoint grapheme takes the first face that covers all of it (GHOSTTY.md:27), over the grapheme segmentation this phase wires. P3 selects a face per codepoint.
- Line-break opportunities by UAX #14, computed once per layout, so a width change only picks among them. **W against GPUI's break rule**, decided by the human on 2026-09-26 on the UCD oracle's numbers (`docs/TESTING.md` "T3"; the PENDING row closed at `bc3f832`): GPUI's word-character list breaks inside every alphabet it does not name, and OS text systems, browsers and `kb_text_shape` (P6's shaper candidate) all break by UAX #14, so the Void host wraps the same text as Neon's other hosts. The code tailoring was measured before anything was built (2026-09-26): over the 13 377 lines of `src/**/*.ms` longer than 20 characters, UAX #14 offers 71 354 break opportunities and GPUI's rule 89 026, because GPUI breaks before every `(`, `[`, `.` and `&&` it meets (`foo(` 1 424 times, `s[` 1 160); UAX #14 keeps those together and breaks inside 1 418 token positions GPUI does not, most of them after a `!` (`!=` 219, `!` before a name about 400) or after the `/` of a path, which GPUI breaks before instead. So UAX #14 is already the better rule for code, and the one tailoring the numbers argue for is no break after `!` before a non-space. Whether to offer it, as `setCodeWrap(true)`, waits on the human (asked 2026-09-26). **Landed in P4** (`lineBreak.ms` over the generated `lineBreakTable.h`, 2 038 ranges): against `LineBreakTest-18.0.0.txt` UAX #14 agrees on 19 346 / 19 346 rows and 41 439 / 41 439 positions, where GPUI's rule agreed on 11 398 rows and 32 774 positions and the U+0020 rule P3 shipped on 12 566 and 34 104. Two tailorings, both in `breakAfter`: no break before the first non-space of a line (GPUI's `first_non_whitespace_ix`), and only U+000A ends a line, as in h2d, so UAX #14's other mandatory breaks wrap like soft ones. Opportunities are computed only for a label with a `maxWidth`, so a measure call pays nothing.
- Carried from P3's review (REVIEWS.md P3, follow-ups): a placement stays invalid while any glyph is refused (F1); filter targets snapped to device pixels, with golden `text/filteredDpi125` (F3); `\r` and tab drawn as nothing and a tab stop, C0 controls kept out of the fallback probe, GPUI's break rule, and h2d's `maxWidth` centring for `align` (F4); pins for the page cap, the refusal report and the `sizeAdjust` guard (F8); the font API under CODE-STYLE §14 (F9), and with it the half of F9 no app sees: `faceAtPath`, `bestFace`, `styled`, `loadFace` and `syntheticFace` still answer `-1`, and private `T[]` parameters remain where CODE-STYLE asks for `Span<T>` (`sortByZ`, `effectMatrixSame`, `sameStrings`, `pushEffect`, `setEffect`, and `polyArea2`, `isEar` and `triangulate` in `graphics.ms`) (REVIEWS.md P3.5 review). From P3.5's re-review: a line in a `tests/PENDING.md` table that the record check cannot parse fails the gate and names the line, where today it is skipped in silence; and the gate prints `msc --version` and `~/.metascript/BUILD`, so its log names the compiler it certified.

**Steps, in order** (written 2026-09-26, before P4's code). Steps 4-7 build what an app author
writes or reads. The human was sent the app code before and after on 2026-09-26 and approved every
proposal the same day: the font API as `Result` with a `FontId`; the BoxStyle builders as
extensions; text metrics on a non-Label failing loud; `textAlign: Align`, centred inside
`maxWidth`; a Label carrying `setTextRuns`, `setSelectionRange`, `setCursorIndex`, `xForIndex`,
`indexAt` and `lineBoxAt`, every index a UTF-16 code unit as MetaScript's `string.length` counts
them; `setTruncate`, `setHangingIndent`, `setForceWidth`, `splitAt` and `setShapingBreaks`, and a
wrap tailoring for code measured on code before it is fixed.

1. **The gate names what it cannot read and what compiled it** (P3.5 re-review #3, #8). A line in
   a `tests/PENDING.md` table that `pendingRows` cannot parse fails the record stage and is named;
   the gate log opens with `msc --version` and `~/.metascript/BUILD`. T0 over the parser in
   `tests/harness/record.ms`, and a planted control per case: a `T2/T4` tier, an id with a space,
   a row missing its date cell.
2. **P3's follow-ups with no app surface.** F1: a placement with a refused glyph stays invalid, so
   the label retries it next frame (T1). F3: filter targets open on device pixels; golden
   `text/filteredDpi125` (T2). F4's internal half: `\r` draws nothing, a tab advances to a tab stop,
   C0 controls never probe the fallback faces (T0 on the layout, T4 `fallbackProbes`). F8: pins for
   the page cap, the refusal report and the `sizeAdjust` guard; the page cap in its own process,
   since exhausting the page table starves every later test (T0). F9's internal half: F-c's `Span`
   parameters, F-d's `Result` returns, `cornerArc`'s unread `Node2D`. Every golden but the new one
   stays byte-identical.
3. **Segmentation, as T3 first.** `GraphemeBreakTest.txt` and `LineBreakTest.txt` vendored under
   `tests/oracle/ucd/` with their Unicode version; a grapheme segmenter over generated property
   tables, held to the grapheme file; the line-break pass rate printed for the U+0020 rule, then
   again after GPUI's break rule replaces it (F4), because that pair of numbers is the argument
   for the cheap rule (TESTING.md "T3"). Then whole-grapheme face selection on top
   (`font-grapheme-selection`), T1 as numbers. Measured: wasm delta of the property tables.
   The break rule moved here from step 2 so the oracle exists before the rule changes. Then
   UAX #14 replaces GPUI's rule (the human, 2026-09-26), held to every `LineBreakTest.txt` row,
   with its table's wasm delta measured.
4. **The app-facing half of F4 and F9**: the font API as `Result` with a
   `FontId`, the BoxStyle builders as extensions, text metrics on a non-Label failing loud, `Align`
   with h2d's `maxWidth` centring. Neon's call sites get a note in `.inbox/neon/`.
5. **`TextRun`**: run splitting, backgrounds before glyphs, underline,
   strikethrough and wavy as UI instances placed from the font's metrics and snapped. T1: a style
   change splits the run; decoration position and thickness as numbers. T2: golden
   `text/decorations`.
6. **Wrap, truncation and hit-testing over the unwrapped glyph list**: wrap
   boundaries, hanging indent, truncation at start, middle and end, `force_width`, `split_at`, the
   shaping-break input, `x_for_index` / `index_for_x`, line boxes over the tallest face (F11). T0
   for the boundary arithmetic; T1 that a width change lays out no glyph again.
7. **Caret and selection as their own instances**: the smooth-min union in
   the fragment shader. T1: a blink changes no text instance. T2: golden `text/caretSelection`,
   and a capture check that a ragged selection has no gap and no doubled alpha. The Zed look is
   asked of the human once this renders.
8. **The 200 × 80 editor bench scene**: draws, instances and `present` (T4); P4's `present` by
   `scripts/bench-ab.sh` against the P3.5 head `4d357f7`; the wasm delta against a tree built on
   the same compiler the same day.

**Defects closed.** The remaining h2d text surface: the `Text` metric surface and the `Align` enum.

**Exit.**

- A 200-line × 80-column buffer with syntax colours, a selection spanning several rows and a caret renders correctly, in a small bounded number of draw calls.
- A ligature never spans two colours; a wavy underline follows the font's metric, snapped.
- Caret blink changes no text instance.
- Selection across a ragged range joins without gaps or overlapping alpha.
- The T5 look beside Zed at 13 px, 1× and 1.5× is taken by the human, and its verdict is written into P3 (REVIEWS.md P3 F12). **Not met when P4 shipped**: the capture is the human's, and P4 ships without it.

**Closes** (`tests/PENDING.md`, checked by the gate): nothing left open. The five rows P4 owned (the two text goldens, grapheme face selection, the UCD oracle and the UAX #14 divergence) were deleted by the commits that closed them.

**Tests.** T3: the UCD conformance files for grapheme clusters and line-break opportunities, every row held (853 / 853 and 19 346 / 19 346) since the human chose UAX #14 over GPUI's rule on those numbers; no PENDING reason is left for either. T1: run splitting, wrap boundaries, decoration placement and whole-grapheme face selection as numbers. T2: the editor scenes and the decoration group. T0: truncation and `split_at` boundary arithmetic.

**Measure.** P4's `present` becomes P5's baseline, so it is taken with `scripts/bench-ab.sh` against the P3.5 head, whose number against the pre-P3 control is the bullet "The P3.5 head" in P3 "Measured at P3 step 8" (REVIEWS.md P3 F10, closed at P3.5); the absolute moves by a millisecond with the box's load, so P4 takes its own pairs. Then a new bench scene — 200 lines × 80 columns with runs, a selection and a caret: draw calls, instances, `present`. It becomes the scroll case P5 is measured on.

**Measured in P4 so far (2026-09-26).** wasm, each tree exported with `git archive` and built by
`scripts/build-web.sh` as the gate builds it, the same day, on msc 0.2.55 BUILD `2925176a`
(WebGPU / WebGL2 bytes):

- the P3.5 head `4d357f7`: 1 519 453 / 1 291 871;
- `fada0ee`, P4 steps 1 and 2 and GPUI's break rule: +3 420 / +3 411;
- `4090e51`, the grapheme table (1 386 ranges, 5.5 KB of rodata), the UAX #29 segmenter and
  whole-grapheme face selection: +11 924 / +11 932;
- `6d42072`, UAX #14 (the line-break table, 2 038 ranges, 8.2 KB, and its rules) in place of
  GPUI's rule: +28 891 / +28 942. That is as much as P3's whole glyph layer (+28 300 / +28 178).
  Taken apart on WebGL2 by building HEAD with a part cut out: the rules are 12 845 B, the table
  8.2 KB and the rest, 6.4 KB, is building the units, their `Vec`s and the lookup; UAX #14 whole
  is 27 458 B. A `--release` web build is byte-identical, so these are the shipped sizes. It ships
  in every build that links `textLayout.ms`; guardrail 6's module budget is P6's to set.

The three older trees carry the `sortByZ` park of `dedf023` applied by hand, because without it no
tree after `314370f` builds for the web (`tests/PENDING.md style:span-of-interface-param`, deleted at P5 step 6 with `sortByZ`).

The whole phase, both trees rebuilt the same way on msc 0.2.55 BUILD `598ca62e` (installed at
19:20 that day; `4d357f7` builds byte-identical on it and on `2925176a`, so the bullets above stay
comparable): the P4 head, tree `4b94899`, is +103 828 / +103 943 bytes over `4d357f7`.

The editor scene, `tests/bench/benchEditor.ms` (`404ece0`, gated in `tests/bench/baseline.json`):
1 draw call, 13 214 UI instances, 1 427 112 bytes uploaded and 51 glyph rasterizations on the first
paint. Its first timing, 6.12 ms, was one standalone run on a busy box, and it carried a whole
`TextLayout` copy per selection row per frame that the design pass found (`6a378e3`).

**P4's `present`**, the P5 baseline: `scripts/bench-ab.sh out/snap/4d357f7 . 8`, both trees built
with `--release` on BUILD `598ca62e`, the P4 head `c85f5d0` (tree `2497f5d`) against the P3.5 head
`4d357f7`, 2026-09-26 late evening:

- UI: 12.58 ms at `4d357f7`, **12.41 ms** at P4, 8 clean pairs of 8 at 2.5-20.3 % load. P4 was
  slower in five pairs and faster in three, by +0.30 ms at the median pair, so P4 does not move
  the UI bench beyond this window's noise. The load fell from about 17 % to 3 % across the pairs,
  and both sides fell with it from 13.6 ms to 8.3 ms, which is why P5 reads this against its own
  pairs rather than the absolute.
- Sprites: 1.72 ms at `4d357f7`, 1.57 ms at P4, 8 clean pairs of 8: guardrail 8 holds.
- The editor scene, P4 only, in the same window: **0.58 ms**, the median of the five runs taken
  below 25 % load on both sides (0.54-0.60 ms); two runs taken as the box filled read 1.10 and
  1.22 ms. `tests/bench/baseline.json` holds 0.58 in place of the 6.12 taken with the copy.

**Unblocks.** P5's scroll measurement, and the editor claim in "The bar".

**Risk → fallback.** Without the shaper (P6) there are no ligatures, so a code font's `calt` is absent and the editor scene looks wrong to anyone who knows the font. Fallback: state it, capture it, and keep the shaping-break input in place so the shaper drops in without touching this surface. Do not pull the shaper forward — it is the single largest wasm item in guardrail 6 and it needs its own measurement.

### P5 — Retention, scroll and the host contract

**Goal.** An unchanged node costs nothing, a scroll is a snapped translation rather than a rebuild, and the host can ask whether anything changed.

**Par.** Past all three references. Makepad is the only running example of persistent instance ranges with an in-place paint-only patch (MAKEPAD.md:33, 102); none of the three has a cheap scroll — GPUI rebuilds every visible item, Makepad re-records, Ghostty re-emits rows. A retained tree is what makes the cheap form possible, and this phase is where Void's model earns its keep.

**Lands.**

- Persistent instance ranges with dirty-range upload; draw order rebuilt only on structural change; "identical bytes → skip the upload" (MAKEPAD.md:117). **Landed at P5 step 7**, the upload written per stream: a changed range re-uploads its whole stream until sokol writes a range of a buffer.
- The in-place paint-only patch: a paint-only write and a caret blink write instance floats and never walk the tree. void2d has no hover or focus; what the host does on either is a colour or alpha write, and that is the paint-only case.
- `TileGroup` — the h2d-native retained multi-quad node on one texture — and the non-overlap node flag, with Makepad's lane fallback where a draw cannot join the unified pipeline (a custom shader, a second atlas page), guarded by the flag rather than by a depth buffer.
- `Mask.scrollX/Y` applied as a list-level shift after the per-instance clip: `clamp(clamp(p, clip) + shift, viewClip)` — the formulation Makepad wrote and never used (MAKEPAD.md:111) — with the offset snapped to a device pixel, so a text run's subpixel variants survive the translation.
- `Scene` reports whether it changed and can re-present its last list; scheduling stays the host's.
- The missing `Object` surface: `parent`, `remove()`, reparent-on-add with a cycle guard, `getChildAt` / `getChildIndex` / `numChildren`, `name`; `localToGlobal` syncing first instead of returning last frame's matrix (`node.ms:344-350`). **Landed at P5 step 6**: `localToGlobal` and `globalToLocal` multiply the node's ancestors' local matrices when asked, so they answer after a write and before any frame.
- The camera out of every world matrix and into a uniform, as h2d has it, so a camera move stops re-multiplying the tree (`scene.ms:115-121`: `presentAt` hands the camera and scale mode to `sync` as the root's parent world). **Landed at P5 step 10 for the translation**, as the root's scroll scope; a zoom or a rotation still re-multiplies the tree, since a label is rasterised at the scale it is drawn at.
- A Label that leaves the scene without `dispose` stops pinning its glyph pages. h2d ties allocation to `onAdd` / `onRemove`, and this phase's `remove()`, like the existing `removeChild` and `removeChildren`, is where void does the same; T1 asserts that a removed Label holds no tile reference (closes `tests/PENDING.md label-dispose-pins-page`). **Landed at P5 step 4** for `removeChild` and `removeChildren`: a removed subtree's Labels release their tiles and keep their shaped layout, so a label added back places again from the atlas's index, hitting the tiles still resident, and only `dispose` frees the layout. `remove()` (step 6) goes through `removeChild`.
- Multi-bracket frames draw every glyph in the frame that first asks for it: a page already uploaded this frame takes no new tile and is not reclaimed (C tracks `s_pageUploaded`), which closes `tests/PENDING.md glyph-page-second-upload`. **Landed at P5 step 4**: the upload state moved from `batcher.c` into `glyph.c` beside the page's dirty flag (`void2dGlyphPageTakeUpload`), so the atlas asks it directly and T1 drives it with no GPU; a glyph that finds every page full or uploaded this frame at the page cap is refused this frame and placed the next, which is F1's retry.
- Host-facing rendering services collected into one surface: text measurement, text geometry, hit geometry (`globalToLocal`, world bounds, clip-aware containment), the change flag, and the frame counters from P1.
- Render bounds apart from h2d's `getBounds`. Since P4 an editing label's `getBounds` grows by the selection's gloop, half its line spacing and its trailing whitespace once a caret or a selection shows, because the filter target and culling read it; h2d's TextInput bounds do not move with the caret (REVIEWS.md "P4 re-review" F-b). A run's colour multiplying with the label's, h2d's rule (P4 F2, answered 2026-09-27), landed before this contract.

- Carried from P3.5's audit (REVIEWS.md "Audit before P4"): a view id stored as its two 16-bit halves in the command stream's two spare floats, rejoined by the replay and the T1 printer, with a T1 test on an id past 2^24 (#18, `tests/PENDING.md display-list-view-id-float32`); the UI instance as one record the persistent ranges store, replacing `drawUiInstance`'s 25 positional lanes, with the 108-byte layout generated for `instance.ms` and C from one table instead of held together by a runtime check (#19, #23); a retained node's dirty booleans as a `BitSet` once retention redefines them (#24); a filtered node that did not change reusing its target instead of rebuilding two arrays and a blur every frame (#21); and the allocation stage following calls out of its listed functions, so a copy one call deeper fails (P3.5 re-review).

**Steps, in order** (written 2026-09-27, before P5's code, from the brief the human approved that
day; the citations above were checked against the code after P4). The internal pieces the
persistent ranges stand on come first; what an app author writes or reads is built only after the
human has seen it as app code; the phase measurement comes last.

1. **The allocation stage follows calls** out of its listed functions (P3.5 re-review #4): a
   function a listed one calls is held to the caller's rule unless a list names it, and a bench
   reaches `update`, so `advanceBlink` is read (P4 re-review N-b). Control: a private helper
   returning `labelTexts[i].layout`, called from `textWidth`, fails the stage.
2. **The view id in two halves** (#18). T1 on an id past 2^24; closes
   `display-list-view-id-float32`.
3. **The UI instance as one record** (#19, #23), its 108-byte layout generated for `instance.ms`
   and C from one table. Every golden byte-identical, the bench counters unchanged.
4. **Glyph pages.** A page uploaded this frame takes no new tile and is not reclaimed (F7, closes
   `glyph-page-second-upload`, T1 over two brackets in one frame); a Label that leaves the scene
   through `removeChild` or `removeChildren` releases its tiles, as h2d's `onRemove` does (F6, T1:
   a removed Label holds no tile reference; closes `label-dispose-pins-page`, since `remove()` in
   step 6 goes through `removeChild`).
5. **The change model — decided by the human on 2026-09-27: void3d's data model, Bevy's change
   detection.** "An unchanged node costs nothing" needs the write itself to mark the node, and
   `n.x = 5` on today's `Node2D` is a store nothing observes. What was weighed, and what ruled
   each out:
   - A compare sweep over every node (A): 13.2-13.6 ms a frame at 100 000 nodes even when idle,
     5.3-5.8 ms comparing x and y alone ("Measured in P5 so far"). The cost is reaching each
     71-field object, so fewer comparisons do not rescue it.
   - h2d's own answer, a property whose setter sets `posChanged` (`h2d/Object.hx:51`, `995-997`):
     msc has no accessors; `get x()` / `set x(v)` in a class parse and vanish
     (`~/metascript/.inbox/compiler/2026-09-27-ts-accessors-parse-and-vanish.md`). h2d also walks
     and draws every object every frame (`Object.hx:600-626`, `963-990`), so its answer only saves
     the matrix, never the walk.
   - `setDynamicField` / `getDynamicField` (LANG.md "Convention-based dispatch protocols"): built
     for open shapes such as JSON. With `key: string` a misspelt field compiles; typed as a
     string-literal union, TypeScript's way, it is a compile error (`out/tmp/p5probes/kf/sdf1.ms`,
     `sdf2.ms`). What still rules it out for writes: a write compares its key at run time, 15-19 ns
     against 13 ns for a binder (release, `kf/cost.exe`); `n.x += 1.0` and a `const` handle are
     refused; each field is named twice, in the union and in the `match`; and a second value type
     needs overloads that differ by a literal type, which msc drops
     (`~/metascript/.inbox/compiler/2026-09-27-overloads-by-literal-type-drop-all-but-first.md`).
   - A `valueOf`-style protocol on the field's type: it sees the value, never the node holding it,
     so it cannot mark the owner.
   - `readonly` fields behind setters: `readonly` on an interface field crashes codegen
     (`~/metascript/.inbox/compiler/2026-09-27-readonly-interface-field-unresolved-type.md`).

   **Chosen:** SCENE-SCALE.md's model, which void3d already cut its types by (VOID3D.md "Data
   types", `src/void3d/scene.ms` `Scene`, `NodeId`, `setLocal`): nodes are handles into a scene's
   tables, per-node state is value structs grouped by the pass that reads them, and a write is a
   binder that replaces a group, skips an equal value (Bevy's `set_if_neq`), sets the group's bit
   and pushes the node onto a dirty list. The handle an app holds is a `NodeRef` (the scene plus a
   `NodeId`), with binders named after h2d's own methods: `setPosition`, `move`, `setScale`,
   `rotate`, `setAlpha`, `setColor`, and a per-field `setX` where h2d has a property. The h2d
   model stays (retained tree, painter's order, an affine on every node, alpha down the tree, Mask
   as a node, filters as a property); what changes is the call shape, from a field store to a
   binder. Neon's `Host` ops (`setText`, `setStyle`, `setStyleProp`) map one to one onto binders.
   Steps 6-14 were rewritten around this data model the same day.

   **The call shape, decided by the human the same day.** A write is a call: `card.setLocal(l)`
   for a group, and h2d's names over it (`setPosition`, `move`, `rotate`, `setX`). A read is a
   call: `card.local().x`, which is the handle's row lookup and generation check, not an
   observation, and the form every handle-based store has (Bevy `query.get(e)`, EnTT
   `registry.get<T>(e)`, flecs `e.get<T>()`). Property syntax on the handle was weighed and not
   taken:
   - Write sugar. The data-oriented stores write through calls: EnTT `patch` / `replace` (a write
     through a reference fires no `on_update`), flecs `set`, or `ensure` then `modified`, Godot's
     `RenderingServer.canvas_item_set_transform(rid, …)`. Unity deprecated Aspects, C# properties
     on a struct handle over component storage, in Entities 1.4 ("use component and query APIs
     directly"). Bevy's `Mut<T>` and becsy's `write()` mark a component changed on mutable access
     even when nothing is written. Swift has the form only through a language feature,
     `nonmutating set`. msc has none, and `setDynamicField` is ruled out above, so Zig's rule, no
     hidden control flow, is the one kept.
   - Read sugar through `valueOf` on the handle works today (`out/tmp/p5probes/vo/local1.ms`, C and
     JS), but `valueOf` does not see the member's name, so every read builds the whole node view:
     16 ns against 9.5 ns for `local().x` (release, `vo/readcost.exe`). A `local()` method and
     `card.local.x` cannot share the name (`vo/local2.ms`), and `card.local.x = 20` fails as
     "Property 'local' does not exist".
   - Read sugar through `getDynamicField` keyed by a literal reads the same bytes at the same
     cost, 8.9 ns each (`vo/gdfcost.exe`), but only one group can have it (the overload card
     above), and `msc lsp` does not see the member: `card.` does not list `local`, and hover on
     `.x` shows `getDynamicField` (`vo/lspProbe.mjs` over `vo/lsp1.ms`). `card.local().x` hovers
     right at every level; completion after any call is empty
     (`~/metascript/.inbox/compiler/2026-09-27-lsp-no-completion-after-a-call.md`).
6. **The data model** (#24; closes `h2d-object-surface`, `one-node-two-parents`).
   - **Rows.** `Scene` owns the tables, and a node is a row: a `NodeId` (index, generation;
     void3d's shape), stable rows, the generation bumped by `dispose`, a LIFO free list
     (SCENE-SCALE.md "Confirmed, not challenged"). The app holds a `NodeRef`, the scene plus a
     `NodeId`, 16 bytes, compared with `==`. A stale ref stops and names the node and both
     generations.
   - **Groups, by the pass that reads them** (SCENE-SCALE.md rule 1), each a `Vec` of a value
     struct: `Local2D` (x, y, scaleX, scaleY, rotation, pivotX, pivotY) for the transform pass;
     `Paint2D` (color, alpha, colorAdd, colorKey, blend, smooth, tileWrap) for emission, the
     group step 8 patches in place; the content group (w, h, tile, and the per-kind numbers
     `Node2D` overloads today: ScaleGrid borders, an underline's thickness and wave, a
     selection's neighbours); the filter; the order group (zIndex, visible, name) and the tree
     (parent, children). Per-kind state stays behind `payload` in side tables: box and image
     styles and label text as today, joined by the label's text and text style, a Graphics'
     mesh and records, and an Anim's frames. What a pass computes, the world matrix and the
     content bounds, is a column only passes write. The `last*` fields and `sync`'s compare are
     deleted; a binder that skips an equal value replaces them.
   - **Binders**, one per group (`setLocal`, `setPaint`, void3d's names) and over them one per h2d
     property or method: `setX`, `setY`, `setPosition`, `move` (along
     the rotation, `h2d/Object.hx:1023-1026`), `setRotation`, `rotate`, `setScale`, `scale`,
     `setScaleX`, `setScaleY`, `setAlpha`, `setColor`, `setVisible`, `setText`, `setFilter`,
     `setSize`, `setTile` and the rest; `at` stays as the chaining form of `setPosition`. A
     binder replaces its group, returns when the value is equal (Bevy's `set_if_neq`), and
     otherwise calls the scene's one `markChanged`, which sets the group's bit in the node's
     `BitSet<Changed>` and pushes the node onto the dirty list the first time. The push lives
     there and not in each binder: "set the bit, push once" has one owner, and a mutating builtin
     through a `NodeRef` parameter is refused by the checker today
     (`~/metascript/.inbox/compiler/2026-09-27-value-param-mutator-crosses-reference.md`;
     `out/tmp/p5probes/noderef2.ms` is the shape, green on C and JS). A group is read whole,
     `card.local().x`. The binders that exist (`setBoxStyle`, `setTextRuns`, `setCursorIndex`,
     ...) move from `Node2D` to `NodeRef` unchanged, and `tick` sweeps the Anim and label side
     tables instead of walking the tree.
   - **The tree**, h2d's `Object` surface: `addChild` takes the child out of its old parent
     first and stops, naming both nodes, when the child is the parent or one of its ancestors
     (`Object.hx:411-430`); `addChildAt`, `removeChild`, `removeChildren`, `remove()`,
     `parent()`, `getChildAt`, `getChildIndex`, `numChildren`, `name`; `localToGlobal` and
     `globalToLocal` sync the node's ancestors first (`Object.hx:359`). A structural change sets
     the scene's `structureChanged`, which step 7's draw order reads. Children are one
     `Vec<int32>` per parent, Bevy's `Children`; SCENE-SCALE.md's shared arena replaces it only if
     the 100 000-node build measures the per-parent allocation.
   - **Constructors on the scene**: `s.rect(w, h, color)`, `s.label(text, size, color)`,
     `s.sprite(t)` and the rest return a detached `NodeRef`; `s.add(c)` stays.
   - **The frame does not change yet.** `present` still syncs and draws every node from the
     tables, `sync` reads the `Local` bit where it compared seven fields, and `present` clears
     the bits and the list. Every golden byte-identical, the bench counters unchanged, UI
     `present` A/B'd against the step 5 head.
   - T0: an equal write marks nothing; a write sets one bit and pushes once; a stale ref stops;
     reparenting, the cycle stop, `remove()`, the index queries; `dispose` frees the row.
     Measured: ns per binder write, and build and teardown of the 100 000-node scene against
     `Node2D`.
   - Every consumer moves in the commit that moves the renderer, since `Node2D` and the tables
     cannot both hold the truth: the examples, the benches, the golden scenes, the tests,
     `graphics.ms` and `layout.ms`. Neon's `host.ms` is Neon's to move, through
     `~/metascript/.inbox/neon/`, once the human has approved the API.

   **Landed at P5 step 6** (`0eec46f`, `e64af7f`): the renderer and every consumer in this repo on
   the tables in one commit, `Node2D` deleted, every D3D11 golden byte-identical (72/72), the bench
   counters unchanged, T0 in `src/test/nodeCheck.ms` (51 tests) and two aborts, `staleNode` and
   `addChildCycle`. Neon's note is `~/metascript/.inbox/neon/2026-09-28-void2d-noderef.md`. What
   the build decided that the plan above does not say:
   - **The binder writes the local matrix**, not `sync`. `present` clears the bits, so a node
     written while it hangs outside the tree would lose its `Local` bit before any sync saw it and
     keep a stale matrix once added back (T0 "a node moved while detached is drawn where it was
     moved once added back"). A write that changes the group runs `trs2d` once; an equal write
     returns before it. `sync` rebuilds a world matrix when the node's `Local` bit is set or its
     parent's world changed, and `addChild` sets the child's bit.
   - **Children stay sorted by `zIndex` as they change**, at `addChild`, `addChildAt` and
     `setZIndex`, instead of at draw: the stable order is the one `sortByZ` produced, and
     `getChildAt` answers in drawn order. `setZIndex` on a child re-stacks it at once, where a
     field store waited for the next add or remove. The first version re-sorted the whole sibling
     list on every add, which made the 100 000-node build quadratic (1.1 to 1.9 s against 51 to
     121 ms for `Node2D`); `e64af7f` moves only the child that changed.
   - **`tick` sweeps the scene's rows** by kind, advancing an Anim's clock and a label's blink.
     The label side table is shared by every scene, so sweeping it would blink a second scene's
     caret twice as fast; a row sweep advances this scene's nodes, attached or not.
   - **Side tables.** An Anim's frames and a Graphics' mesh and records moved into the scene
     (`anims`, `meshes`, each with a free list, void3d's `meshes` and `lights`); box and image
     styles and label text stay module tables. The label's text and text style joined
     `LabelText` beside a `stale` flag that `sync` and the text metrics reshape on, and a label
     takes its row when it is made rather than at its first sync.
   - **`removeChildren` is one pass.** Removing one child scans its siblings, as h2d's
     `children.remove` and Bevy's `Children` do, so taking 50 000 siblings apart one at a time is
     quadratic; the experiment's teardown goes through `removeChildren`.
   - `==` on `NodeRef` fails to build on C and JS in a module that does not import `NodeId`
     (`~/metascript/.inbox/compiler/2026-09-28-struct-eq-nested-type-not-imported.md`);
     `src/test/nodeCheck.ms` names `NodeId` for it and is the parked site.
   - The allocation stage lists the new frame path (`drawRow`, `syncRow`, `meshBounds`,
     `clearChanges`, `refOf`, `liveRow`, `imageStyleOf`). On BUILD `3f6873ee` it also found
     `faceAtPath` copying each `LoadedPath` in a `for..of` on the rebuild path, already so on
     the step 5 head built on that compiler; `2cfc821` reads it by index.
7. **Retention**, consuming the dirty list: a draw order flattened and rebuilt only when
   `structureChanged` (SCENE-SCALE.md "Flatten traversal order"), persistent instance ranges,
   re-recording only the dirty nodes and, for a transform, alpha or filter change, what inherits
   it, found by descending from the changed set with value-equality pruning (the Bevy form
   SCENE-SCALE.md says to measure against upward marking); dirty-range upload, identical bytes
   skipping the upload, a filtered node that did not change reusing its target (#21). T1: one
   mutated node, one dirty range of a known size; byte-identical re-records; the order rebuilt
   only on a structural change.

   **The plan, 2026-09-28.** Measured first on the step 6 head: the UI bench's `present`, 20 000
   nodes, spends 4.0-4.4 ms of 4.9-5.5 walking the tree and emitting, 0.39-0.47 ms in `sync`,
   0.49-0.55 ms packing and uploading and 0.02 ms replaying (release, load 6-19 %, three runs of
   `out/tmp/p7probes/presentSplit.ms`). Emission is what retention removes.
   - **7a. The list belongs to its scene.** The display list becomes a record the scene owns, as
     void3d's `Renderer` owns its `PassList`s; the emitter writes into the list in use, and a
     bare `begin2d` bracket (the manual targets, the T1 snapshots) uses a module default. Two
     scenes presented in one process (`tests/integration/twoViews.ms`) each keep their own last
     frame. Every golden and snapshot byte-identical.
   - **7b. The draw order, flattened** (Bevy `UiStack`, `stack.rs:11-19, 94`): the rows in
     painter's order, each position's subtree end, each row's position and whether a filter sits
     above it, rebuilt from the root only when `structureChanged`. A scene's full frame syncs and
     records by scanning it: a Mask pushes its clip before its children and pops at its subtree's
     end, an invisible node skips its subtree, and a filtered node hands its subtree to
     `drawFiltered`, which keeps the recursive walk, h2d's `drawRec` of a subtree into a target, as
     `NodeRef.draw` does. The accumulated alpha becomes a column beside `worlds`. T1: a paint or a
     move rebuilds no order, an add, a remove and a `setZIndex` do.
   - **7c. Paint ranges.** A full frame records, for each row it emits, the emitter's position in
     every stream and its run state before and after the row's own content: GPUI's `PaintIndex`
     and `Range<PaintIndex>` (`window.rs:1014`, `3887`), kept in place instead of copied into the
     next frame. A frame with no structural change, and the same viewport, DPI, view matrix and
     scene sampler, emits again only the rows that changed and what inherits from them: from each
     dirty row it descends the row's positions recomputing world and alpha, and prunes a
     descendant whose two values came out equal and that has no bit of its own (Bevy `set_if_neq`,
     `systems.rs:450-459`, in the descend-from-the-changed-set form of
     `visibility_propagate_system`, `mod.rs:419-456`). Each such row is emitted again from its
     recorded start and kept when the emitter ends exactly at its recorded end, the same cursors
     and the same run state; otherwise the frame records in full, which is Makepad's granularity
     and the phase's stated fallback. The full frame is also taken for a structural change, an
     order change, a change to a Mask or a filter or anything under a filter, and a label whose
     glyphs were refused (F1's retry). `tick` marks an Anim whose frame index moved and a label
     whose caret flipped; step 8 turns the second into a patch. Upward marking is measured
     against the descent in `tests/experiments/`, as SCENE-SCALE.md asks. T1: after each write of
     a corpus (a move, a colour, a group's alpha, text of the same length and of another, a
     reparent, `setZIndex`, a visibility flip, a mask resize, an Anim frame, a caret) the retained
     streams equal a full record of the same scene byte for byte, and a card's colour rewrites one
     UI record and nothing else.
   - **7d. Upload what changed.** A scene's list gets its own GPU buffer, written only when a
     range changed; the pack to GPU records runs over the changed ranges alone, and a range whose
     bytes came out identical is dropped (MAKEPAD.md:117). A frame that changed nothing uploads
     nothing, and a frame that re-records no target runs no target pass, so a filtered node that
     did not change keeps its target (#21); a target goes back to the pool of the list that
     holds it. At the pinned sokol a written buffer is replaced whole, once a frame
     (`sg_update_buffer`); a range write is the `write_persistent` upstream has announced
     (SOKOL.md). T4: the bench counters of a still frame.

   **Landed at P5 step 7** (7a `ffe1f48`; 7b `a1cca15`, `dddf379`; 7c `e4bc00c`, `cce59f3`,
   `70092c6`; 7d `ebc5a5f`, `d013f58`, `2802c7a`): every D3D11 golden byte-identical (72/72), now
   captured on retained frames, since the runner's second and third draws of a scene change
   nothing. What the build decided that the plan does not say:
   - **The oracle resyncs every world.** `tests/displayList/retain.ms` compares, after each write
     of the corpus, the retained streams with a full record of the same state, and the full
     record recomputes every world from the locals. The first version did not: a patch that
     left a descendant's world stale copied it into both sides, and a mutation skipping the
     descent passed. It fails now, as does one skipping the in-place emission.
   - **A bracket starts its runs in the UI pipeline** (`e4bc00c`). `begin2d` never reset the
     open run's pipeline, so the reason recorded for the first draw after a scissor or a target
     barrier depended on where the previous bracket ended. The stored snapshots had been written
     after brackets that ended in the UI pipeline, so starting there keeps every one of them;
     the replay does not read the reason, so no pixel moved.
   - **A pooled target belongs to the list that took it** until that list records afresh, a
     serial per list, replacing the frame-linear pool whose release at every scene `present`
     handed a retained filter's target to the next bracket (the demo's pool grew 5 → 10 before
     this). A retained frame runs no target pass: a filtered node that did not change keeps its
     target and its pixels (#21), and the nine filter goldens' draw counts fell by their target
     passes (`filter/blur` 6 → 1, `regress/filterNestedPass` 7 → 3; `tests/golden/table.ms`).
     Two lists no longer share a target; the demo still holds 5.
   - **A scene list writes its own GPU buffers**, one per stream, with `sg_update_buffer` only
     when that stream's bytes changed; the UI pack runs over the changed ranges alone, and a
     re-emitted row whose bytes came out equal adds no range (T1: a colour write marks one range
     one record long, a write undone in the same frame marks none). The default list, which
     re-records every bracket, keeps the frame's append buffer, and so does a second write of
     one list in one frame, since sokol allows one update per buffer per frame. The range is
     known; its GPU write is the whole stream until sokol has a range write (`write_persistent`,
     SOKOL.md), so a colour write re-uploads the list's whole UI stream.
   - **What takes the full frame**, read off the corpus: a structural change, `setZIndex`, any
     order change (a visibility flip), a Mask's size, text of another length, and anything under
     a filter. A move, a colour, a group's alpha, text of the same length and an Anim frame are
     emitted in place, and since step 8 a caret that flips.
   - **Descent from the changed set against upward marking** (`tests/experiments/propagate.ms`,
     100 251 nodes: 250 column groups of 200 cards with a label each, release, load 6 %, three
     rounds of 20 passes): one card 0.07-0.10 µs against 1.4 µs, every 50th card 0.019 against
     0.10-0.115 ms, one column 2.9 against 4.0 µs, every card 0.73-0.77 against 0.87-0.92 ms, the
     root 0.72 against 0.77-0.80 ms, both writing the same worlds. Upward marking scans the top
     level on every frame and walks up once per changed node; it wins no case here, and the
     descent is what the frame runs.
   - **A shape change splices the next frame from the last** (`5dd8a9a`), GPUI's `reuse_paint`
     (`window.rs:3887`) over its `rendered_frame` / `next_frame` pair: the scene holds two lists,
     and when the in-place patch cannot keep a row's shape, or the order changed, it scans its
     draw order into the other list, copying the bytes of each clean row whose recorded run state
     and mask match the running ones, one `memcpy` per run of adjacent clean rows, and emitting
     the rest; then the two swap. A clean row with a command or an effect of its own is emitted,
     since commands are not copied. The in-place attempt writes through a window bounded by the
     row's recorded end, so a row that grew spills past the frame's end and the old list stays
     a whole source. The full record is left to a first frame and a viewport, DPI, camera or
     scene-sampler change. The oracle now compares the paint ranges too, and caught the first
     batching, which ran rows with a command of their own into a copy.
   - **What a shape change costs.** A probe shaped like terminator's grid
     (`out/tmp/p7probes/termGrid.ms`, 60 labels of 150-200 monospace cells with three runs,
     release, windowed), before the splice, quiet box: a still frame 0.013-0.016 ms and 0 B; one
     row rewritten at its length 0.17 ms and 972 000 B, patched; one row one cell longer
     0.52-0.58 ms, recorded whole; every row rewritten 2.5-2.7 ms, most of it shaping. On the UI
     bench scene (`hoverUi.ms`), one card's colour 0.30-0.31 ms and 5 280 120 B, one label's
     length 5.4-5.8 ms. With the splice, headless on the UI bench scene with every row clean,
     interleaved in one process: 1.09-1.41 ms against 5.36-5.93 for a full record, and
     1.77-2.75 against 7.65-9.75 on a loaded box; the windowed probes were not re-read on a quiet
     box. Step 14's A/B reads them again.
   - **A changed range re-uploads its stream, and stays so.** No reference writes a range of a
     persistent buffer: GPUI uploads every instance on every drawn frame
     (`wgpu_renderer.rs:1542-1579`), Ghostty its whole buffer (`generic.zig:1817-1819`), Makepad a
     whole draw item. void2d uploads nothing on an unchanged frame and one stream on a changed
     one; on the UI bench that stream is 5 280 120 B and 0.30 ms. sokol's `write_persistent` is
     taken if upstream ships it; the fork gets no patch for it. Decided 2026-09-28, when the
     human handed mechanism calls to the references.
8. **The paint-only patch**: a `Paint2D` write and a caret blink rewrite the node's instance
   floats in place. T1: a blink writes the caret's instance and nothing else; a colour write
   uploads a known number of bytes.

   **Landed at P5 step 8** (`e060562`, `a9a9b92`), on step 7's paint ranges rather than a second
   path: a paint write re-emits the node's own content in place, which walks no tree, and the
   changed range is now the first to the last record whose bytes moved, not the row's whole
   range. A hidden caret keeps its instance at alpha 0, so a blink changes one float and no count,
   and is patched where step 7 took the full frame; P4's T1 "a caret blink changes no instance
   but the caret's" now pins the same length and the caret's fill alpha, and
   `tests/displayList/retain.ms` pins that a blink marks the label's last record and nothing
   else. A hidden caret still costs its quad. The bytes a colour write or a blink sends to the
   GPU are the whole UI stream, which step 7 keeps: no reference writes a range of a buffer.
9. **The change flag and the camera uniform.** T4: an idle frame issues no draw and no upload
   (closes `idle-costs-a-walk`); T1: a camera move re-multiplies no node.

   **The change flag landed at P5 step 9**, in GPUI's shape: `s.isDirty()` is true while a
   binder has marked something, the structure or the camera's view changed, the scene sampler
   changed, or no frame was drawn yet, and a host presents only then (GPUI draws only when
   `is_dirty`, `window.rs:1798-1834`); `s.present()` of a clean scene replays its list, GPUI's
   `present()` without a `draw()`. Neon's host drops its own `markDirty` for it, through
   `~/metascript/.inbox/neon/2026-09-28-void2d-noderef.md`. **The camera half moves to step 10**,
   found while building this one: a camera outside the world matrices still decides what is
   culled, since culling reads the viewport and the active clip, so a pan must emit the rows it
   brings on screen. A Mask's scroll meets the same problem inside its clip. Both take one
   mechanism, the list-level shift with a cull pass over what the shift uncovers, built in step
   10.
10. **Scroll**, after the human has seen it as app code: `Mask.scrollX/Y` with h2d's
    `scrollTo` and `scrollBy` (`h2d/Mask.hx:70-104`) as binders, applied as the list-level shift,
    snapped. T2 golden `clip/maskScroll`; a scroll bench over the editor scene, CPU and uploaded
    bytes per frame, the bytes gated (T4).

    **The plan, 2026-09-28**, on the human's hand-off of mechanism calls to the references. h2d
    moves a Mask's children by `-scroll` in `calcAbsPos` and keeps the clip where the Mask is
    (`Mask.hx:115-119`, `maskWith`); `scrollBounds` clamps (`:103-113`). The call shape is step 5's:
    `mask.scrollTo(x, y)`, `mask.scrollBy(dx, dy)`, `mask.setScrollX(x)`, `mask.setScrollY(y)`,
    `mask.setScrollBounds(b)`, read as `mask.scroll().x`; a Mask keeps its scroll in a side
    table behind its payload.
    - **10a, h2d's meaning.** The scroll enters the children's world matrices, as `calcAbsPos`
      does, so culling, `getBounds`, `localToGlobal` and `globalToLocal` all answer in scrolled
      space and a scroll write is a change the retained frame patches or splices. T2 golden
      `clip/maskScroll`; T1 on the queries.
    - **10b, the list-level shift.** Makepad's `clamp(clamp(p, clip) + shift, viewClip)`
      (MAKEPAD.md:111), which Makepad wrote and never used: a Mask that has scrolled records its
      subtree unscrolled and uncut by its own clip, every command recorded inside it names the
      Mask's scroll scope, and the replay adds the scope's shift, snapped to a device pixel, to
      positions and to the clips recorded inside it, and cuts with the Mask's own clip. A scroll
      write then changes one entry of the scope table: no instance byte, no command, no walk. The
      price is that a scrolled Mask's content is emitted whole rather than culled to the Mask;
      content far larger than the view is the app's to virtualize, as GPUI's `uniform_list` is.
      A rotated Mask keeps 10a's path. T1: a scroll changes no instance and no command; T4: the
      editor scene scrolled every frame uploads nothing and re-emits nothing.
    - **The camera** (moved from step 9) takes the same shift at the root after 10b, with a cull
      pass over the rows the shift brings into the viewport, since the viewport culls there.

    **Landed at P5 step 10** (10a `063c691`, golden `de200e5`; the shader `cc30261`; 10b below).
    `clip/maskScroll` is byte-identical under both paths. What the build decided:
    - **A scope is a Mask with a scroll whose world, and every Mask world above it, is
      axis-aligned** (`scrollScope`). Anything else keeps 10a's meaning, the scroll in its
      children's worlds, because a rotated clip outside the scope would have to cut shifted
      positions while clips inside it cut unshifted ones.
    - **The shift lives in three places**: every 2D vertex stage adds a `shift` uniform after the
      clip distances are taken, so a clip recorded inside the scope cuts unshifted positions; a
      command names its scope in its last spare float (`CMD_SCOPE`); the list keeps a scope record
      per Mask, its local shift snapped to a device pixel and its view, which `resolveScopes`
      chains through the parents at every flush and the replay reads for the shift uniform and
      for the scissor, `(clip + shift) ∩ view`, an empty one drawing nothing.
    - **Inside a scope the clip starts empty**: a Mask nested in the scrolled content intersects
      only with Masks inside the same scope, and leaving the scope records the outer clip again.
      Viewport culling and a filter's viewport crop are off inside a scope, since both would
      compare unshifted positions with the screen.
    - **A scroll write marks `Changed.Scroll`**, which the descent skips for a scope: the frame
      patches nothing and `refreshScopes` writes the new shift. The first scroll of a Mask, or its
      first `scrollBounds`, marks `Local` instead, since it turns the Mask into a scope and
      changes how its subtree records: the oracle caught that one, a first scroll that patched
      the old recording.
    - `getBounds` answers in scrolled space by adding the scopes above and inside the node;
      filters keep the unshifted bounds they record in. `localToGlobal` already did.
    - Measured, the gate's bench, one run: the scroll scene (the editor label in a 1264 x 704
      Mask, a new offset every frame) presents in **0.031 ms and uploads 0 bytes a frame**, one
      draw over the 13 214 instances of the whole content; the editor scene before step 7
      uploaded 1 427 112 B every frame, and P4 measured its `present` at 0.58 ms. Content far
      larger than its Mask costs its whole instance count, since a scope does not cull.

    **The camera half landed** after 10b. The view's translation leaves the world matrices for a
    scope every scene list opens at its root (`enterCamera`), and the worlds keep the view's
    linear part.
    - **The translation is snapped to a device pixel**, as h2d rounds its camera's
      (`h2d/Camera.hx:227`). A pan by less than half a device pixel is no change. The demo, the
      only golden with a camera, moved: its fitted camera sits at (8.163, 14.286) and now draws at
      (8, 14). Its four goldens were regenerated. Every other scene stayed byte-identical, and so
      did `clip/maskScroll`, whose Mask scope now chains under the root's.
    - **A zoom or a rotation still re-multiplies the tree.** A label is rasterised at the scale
      it is drawn at (P3), so moving the linear part into a uniform would scale finished glyphs.
      GPUI and Makepad have no camera zoom to take from.
    - **Culling stays exact.** Each painted row keeps the box its viewport test read (`culls`).
      A pan runs one pass over the order and queues the rows whose test flips between the old
      and the new shift, and the patch or the splice redraws them. A filtered node whose
      viewport crop moves takes the splice, which re-renders its target.
    - **`localToGlobal`, `globalToLocal` and `getBounds` add the root's shift**, so they answer
      where the node is drawn.
    - T1 (`tests/displayList/retain.ms`): a pan that crosses no row patches, writes no instance,
      leaves every world matrix alone and moves `localToGlobal`. A pan that uncovers rows or
      takes them off splices and records what a full frame records. A zoom takes the full frame.
    - **A pan is a pure translation, to the byte.** Golden `clip/cameraPan` (DPI 1.25, a camera
      at (-140, -8.3)) was captured once as it is and once with no camera and every node placed
      where the camera shows it: the two PNGs are identical. Three things stood between them,
      each fixed on its own:
      - GPUI rounds an edge half toward zero (`snap_bounds`) in screen space, where every
        coordinate it snaps is positive, so in effect half down. Under the camera or a scroll
        scope void2d snaps in unshifted space, where negative coordinates are ordinary, and
        toward zero put such an edge a device pixel off. `snapEdge` now rounds half down
        everywhere, GPUI's result for whatever lands on screen. A shadow offset is a
        distance, not a position, and keeps half toward zero (`snapOffset`).
      - A filter's target was sized as `ceil((xMax - xMin) * dpi)` after flooring `xMin`, which
        read 65 device pixels in one place and 64 in the other for the same target (a
        204.8-wide logical viewport is not exact in float32). Each edge is now floored or
        ceiled on its own and cut against the framebuffer's integer size less the shift.
      - `clipOf` clamped a clip to zero when it was recorded. A Mask left of zero lost its
        clip, and one wholly left of it recorded width 0, which the replay reads as no clip,
        so a child reaching the screen drew uncut. That was a defect before the camera too,
        for a Mask wholly left of the viewport, and the camera made it common. The record
        keeps the true rect and the replay, which already clamps, cuts it. A Mask nested
        outside its parent had the same symptom through an empty intersection, and an empty
        clip now culls every quad under it. T1 in `tests/displayList/snapshot.ms`.
      None of the other 73 goldens moved.
    - Measured, `out/tmp/p7probes/panCost.ms` (release, 1280 × 720, a grid of 40 000 nodes twice
      the viewport's width, three runs, not an A/B):
      - a still frame: 0.020-0.022 ms;
      - a pan of 1 px a frame: **0.25-0.26 ms and 81 810 B a frame** on average (111 frames
        patched, 9 spliced where a column crossed an edge);
      - a pan of one column a frame: 1.65-1.74 ms and 1 090 800 B (all spliced);
      - the same 1 px pan forced through the full frame, what every pan cost before: 8.3-10.7 ms
        and 1 090 800 B.
11. **`TileGroup`**, after the human has seen it: the non-overlap flag and the lane fallback.
    T1. Closes `h2d-tilegroup`.
12. **The host services** in one surface, and render bounds apart from `getBounds` (P4 re-review
    F-b), shown to the human first as Neon's `host.ms` before and after. The run-colour rule
    (P4 F2, h2d's multiply, answered 2026-09-27) landed first.
13. **`oracle:h2d`** (T3), Heaps compiled to JS and run on node by SCENE-SCALE.md "Reproducing";
    `haxe` 4.3.7, `heaps` and `format` are on this box (2026-09-27). HEAPS.md's deliberate
    divergences seed its PENDING list.

    **Landed at P5 step 13.** `sh tests/oracle/h2d.sh` compiles `tests/oracle/h2d/Oracle.hx`
    against Heaps `b9aa6dcb`, runs it on node and writes `tests/oracle/h2d.json`: fifteen trees of
    `h2d.Object`, `Bitmap` and `Mask`, and what Heaps answers for `getBounds`, `localToGlobal` and
    `globalToLocal` on every node. The scale modes come from h2d's own `checkResize`, run on an
    engine and a scene made with `Type.createEmptyInstance`, since a real `h2d.Scene` needs a
    window. `src/test/h2dOracleCheck.ms` rebuilds each tree in void2d inside T0. The first run
    agreed on 8 of 15 trees and found three places void2d had left h2d's meaning, all on
    surfaces HEAPS.md keeps as h2d's. Each is fixed:
    - `getBounds` of a Mask is its content cut to the Mask's rect (`Mask.hx` `getBoundsRec`),
      where void2d joined the rect with the uncut content.
    - `getBounds` of a node with nothing to bound is a point at its origin, and the answer
      replaces what `out` held, as h2d empties it (`Object.hx:146-158`).
    - A Mask's own space is scrolled: `mask.localToGlobal` and `globalToLocal` subtract its
      scroll, as `calcAbsPos` does (`Mask.hx:115-119`), while its clip stays where the Mask is.
      Step 10a's T1 had asserted the opposite and is corrected.
    - `LetterBox` and `Fixed` centre on whole scene units, as `checkResize` floors. The margin is
      taken in float64, since a float32 one read -1 px at 801 x 599.

    The render bounds that filters and culling read are unchanged; they are step 12's. `Zoom`
    and `AutoZoom` mean something else in void2d, a design size where h2d takes a zoom level.
    Which meaning void2d takes is asked of the human, and the two are listed until then
    (`tests/PENDING.md` "h2d oracle divergences"). The gate now reads **15 / 15 trees and 4 / 6
    scale modes**. Two compiler cards came out of it:
    `2026-09-28-narrowed-ref-union-loses-extensions` and
    `2026-09-28-c-backend-fuses-multiply-add`. The second is why `wholeSceneUnits` keeps its
    product in a binding of its own: C fused `window - design * zoom` into one rounding where
    JavaScript did not.
14. **The measurement** listed under "Measure", and the wasm delta against the P4 head built the
    same day on the same compiler.

**Measured in P5 so far (2026-09-27).** The installed msc changed from BUILD `598ca62e` to
`c54a8671` during step 4. It makes `const` deep through `struct`, `T[N]` and `Vec<T>`, so every
binding void writes became `let` (`6e90500`, void3d's included; `~/metascript/.inbox/void/`
has the note). Every number below is on `c54a8671`, and an older tree needs the same lines to
build on it.

- Step 3, the `UiInstance` record: an interleaved A/B against `e98a67b` was inconclusive on a busy
  box (UI 10.20 → 10.81 ms at the median over 5 clean pairs of 6, then 4 clean of 10), and a
  GPU-free emission loop over the UI bench scene, the minimum of 40 × 5 frames, read −0.9 to
  +0.5 ms pair by pair. The phase A/B reads it again.
- Step 5, change model A, `tests/experiments/changeModel.ms` at `6a0e682`, deleted with `Node2D` at
  step 6 (release, D3D11, 1280 × 720): 100 000
  nodes, 50 000 cards each with a two-digit label, a snapshot of every field that reaches the
  instance bytes, 120 frames per reading. Of five runs, the two with load under 25 % on both sides
  read 13.2 and 13.6 ms per frame for the sweep, the same idle or with one node changed; comparing
  x and y alone read 5.3 and 5.8 ms; `present` on the same scene today read 70.5 and 71.6 ms. The
  cost is reaching each 71-field `Node2D` object, not the comparisons: about 130 ns a node, so
  2.7 ms for the 20 000-node UI bench and 0.3 ms for a 2 000-node window, paid on every frame,
  idle or not. Under B an idle frame costs nothing and a write costs one push onto a dirty list
  (SCENE-SCALE.md, about 23 ns for the binder path). The human chose binders over tables, step 5.
- Step 6, the tables, on BUILD `3f6873ee`, release, a quiet box (load 3-12 % around every run),
  `out/tmp/abStep6.sh`. Tree A is `2cfc821`, the step 5 head plus the `faceAtPath` fix; the fix
  alone is neutral, `ff232e7` against `2cfc821` reads UI 10.61 against 10.61 ms (6 clean pairs of
  8) and sprites 1.70 against 1.59 ms (8 of 8). `scripts/bench-ab.sh`, 8 interleaved pairs:
  **UI `present` 11.78 → 5.58 ms** (5 clean pairs of 8; B ranged 5.22-5.74), **sprites 1.91 →
  1.05 ms** (8 of 8). The frame still walks and draws every node, so this is what the old
  frame spent reaching 71-field objects and comparing seven transform fields, eight text
  fields and a string per label every frame, which a `Local` bit and a `stale` flag replace.
- Step 6, `tests/experiments/nodeTables.ms` against the same loops over `Node2D` built in
  `2cfc821` (`out/tmp/p6probes/node2dControl.ms`), 100 000 nodes (50 000 cards, each with a
  two-digit label), 3 interleaved pairs of 5 rounds: **build 61-81 ms against 48-62 ms**. A
  label takes its side-table row, with an empty shaped text, when it is made instead of at its
  first sync, and 50 000 `allocateLabelText` calls alone take 21-23 ms
  (`out/tmp/p6probes/alloc/labelAlloc.ms`), which is the gap; **teardown 27-33 ms against
  87-131 ms**
  (`removeChildren` on the root, then `dispose` on each card). A `setX` that changes the value
  costs **51-63 ns**, an equal one **34 ns**, over a loop that alone costs 0.33 ns a node:
  twice SCENE-SCALE.md's 23 ns estimate, which had no generation check and no `trs2d`. The
  same loop storing `card.x` on `Node2D` read 288-445 ns against 2.3-3.8 ns for reading it,
  unexplained and not pursued, since the field store is gone.
- Step 7, retention, on BUILD `3f6873ee`, the gate's bench, one run each and not an A/B: a still
  frame's `present` reads **UI 0.014-0.016 ms, sprites 0.013-0.015 ms, text 0.010-0.012 ms,
  editor 0.018 ms**, uploading 0 bytes (`uploads` 0 on every bench scene; frame 1's upload is
  the new `firstPaintUploadBytes` row). With 7c alone, when a still frame emitted nothing but
  still packed and uploaded the whole list, UI read 0.58-0.63 ms. Step 14's A/B reads them again.

**Defects closed.** Two "Known defects" lines: the h2d surface — `parent`, `TileGroup`, `Mask.scrollX/Y` and the text metrics it points at — and a sokol view id past 2^24 naming another slot. Also the idle cost: `Scene.present` walking and drawing every frame with nothing knowing whether the tree changed.

**Exit.**

- Scrolling the P4 editor scene uploads only the shift and walks no tree. Met at step 10 for a Mask that is a scroll scope: the scroll bench uploads 0 bytes a frame.
- A caret blink and a hover re-emit their one node, upload only the stream it changed, and cause no structural change. Amended 2026-09-28 from "upload a known small number of bytes": no reference writes a range of a buffer (step 7).
- An idle frame issues no draw and no upload.
- A fully static 100 000-node frame costs a column sweep, not a tree walk (the SCENE-SCALE.md budget).
- One node can no longer sit under two parents (`node.ms:305-309`).

**Closes** (`tests/PENDING.md`, checked by the gate): `h2d-tilegroup`, `h2d:scale-Zoom`, `h2d:scale-AutoZoom`. Closed and deleted: the view id row, at step 2; the second-upload and dispose-pins rows, at step 4; the object-surface and two-parents rows, at step 6, with the span-of-interface style row, whose sortByZ step 6 deleted; the idle row, at step 9; the scroll golden row, at step 10; the h2d oracle row, at step 13.

**Tests.** T1 carries this phase: mutate one node, assert exactly one dirty range of a known size; assert byte-identical re-records; assert zero instances written on a blink; assert the draw order rebuilds only on structural change. T3: the h2d oracle for `getBounds`, `localToGlobal` / `globalToLocal`, mask intersection and scale modes, with HEAPS.md's deliberate divergences as the seed PENDING list. T4: scroll and idle budgets gated on uploaded bytes, which are deterministic.

**Measure.** Scrolling the 200-line text view: CPU per frame and uploaded bytes per frame, both against P4's numbers. A static 100 000-node frame: CPU. An idle frame: zero draws. The UI bench scene must not regress, and **UI `present` must come back to or below the pre-P3 control `8a473f3` under `scripts/bench-ab.sh`, with every pair clean** — the label-emission cost P3 left, +0.5 ms on a quiet box and +1.4 to +1.8 ms under load, is owed here (P3 "Measured at P3 step 8"). P3.5's head already reads below it, 13.05 against 13.54 ms, but over 7 clean pairs of 8, so the line is not yet met by its own rule.

**Unblocks.** The Neon Void host; SCENE-SCALE.md's columnar model has a consumer for the first time.

**Risk → fallback.** Persistent ranges and the in-place patch depend on per-instance bytes being stable across frames, which P2's layout decides and T1's idempotence assertion is the only guard on. If snapping or a gradient parameter turns out to depend on something that changes every frame, ranges thrash and the phase delivers nothing. Fallback: keep dirty-range upload for the subtrees that are provably stable (`TileGroup`, text runs) and re-record the rest, which is Makepad's granularity and still far better than today. The assertion that catches it early is in P1, not here.

### P6 — Modules and hardening

**Goal.** Everything that is optional, measured by what it costs; and the paths that make a failure survivable.

**Par.** The remaining taken items across all four references, each behind a compile-time switch, so a game build pays for none of them (guardrail 6).

**Lands.** Each item is independently shippable and carries its own wasm measurement.

- **Shaper module** (candidate `kb_text_shape`): GSUB features, ligatures, complex scripts, shaping breaks as an input. The largest wasm item; measured alone.
- **SDF text** for the transformed regime: one ~32 px/em distance field per glyph, derivative-scaled ramp, luma bias (MAKEPAD.md:112) — so zoom and animation cost nothing, and void3d gets world-space text through the same glyph layer.
- **Colour emoji**, a compile-time module, decided at P3's review. stb_truetype reads no colour table, so the module reads them itself: CBDT/CBLC and sbix bitmap strikes decoded by `stb_image`, already a void dependency (`src/assets/image.c`), and COLRv0 as layers of stb outlines, each tinted by its palette entry. The module builds the RGBA page kind P3 decided but did not build (P3 "Atlas page kinds"): the page format, its view and a colour draw path at a whole-pixel origin with no gamma correction, as GPUI does (GPUI.md:51). Bitmap strikes are pre-shrunk into 1.25× size buckets, so a zoom does not churn the atlas (MAKEPAD.md:114). Explicit-versus-fallback presentation comes with it (GHOSTTY.md:24), VS15/VS16 over P4's grapheme segmentation. Deferred faces, which let a family answer coverage before it loads, land in the default glyph layer rather than in the module, because the lazy CJK families need them too.
- Variable-font axes and stem darkening **only if** the T5 capture beside Zed asks for them. The hinting rasterizer is decided out (P3 "Resolved at P3 step 8").
- **SVG → R8 mask → tinted sprite**, the icon path, with a single-header C rasterizer.
- Procedural sprite glyphs — box drawing, blocks, braille, powerline — for a terminal widget.
- Animated image frames keyed by frame index.
- `Graphics` antialiasing by a vertex-shader fringe: the edge normal per fringe vertex, extruded by `1px / scale`. No MSAA intermediate, no baked fringe (guardrail 4). `sample_count` exposed as a knob on the mobile bridges instead of hard-coded 1 (guardrail 5) — the one place this phase touches void3d, since the swapchain sample count must match its pipelines.
- Device loss: drop every GPU object, re-arm every dirty flag, redraw, with a **fault-injection switch** (MAKEPAD.md:104) — which is also how the path is tested. void3d already has the Android form of this (`voidEmbedLoseContext`); this generalises it and covers the atlas and the instance buffer.
- Warm-up of pipelines, device and the font database off the first-frame path; release of GPU resources when occluded; a synchronous draw during live resize; discard of a late frame at the wrong size.
- **The guardrail-9 backends this box can run**, which P3 did not reach: a desktop GLES3 build of the golden runner (a GL variant of `src/sokol/sokolWin.c` and `glsl430` shaders; `tests/capture/capture.c` already has the `glReadPixels` path, which WebGL2 exercises), and WebGPU's `copyTextureToBuffer` + `mapAsync` readback in a headed browser, since headless Chrome hands WebGPU no adapter here. Metal macOS, Metal iOS and GLES3 Android run on the human's hardware.
- The mesh path's pixel-centre ties: bias mesh geometry by −1/64 px in device space, the fix `tests/PENDING.md conformance:webgl2-pixel-centre` proposes, which keeps D3D11's tie results and gives GL the same.
- The P2 rows this phase owns: styled-box colour effects (`ui-box-color-effect`), the independent non-uniform-SDF bound (`sdf-non-uniform-bound`) and the repository-wide line-length pass (`style:line-length`).
- The frame profiler: histograms of dirty-to-present, draw time and input latency, plus the draw-call, instance and upload-byte counters GPUI lacks, drawn outside invalidation.

**Defects closed.** None remaining; "Known defects" is empty by the end of P5.

**Exit.**

- The editor scene shows `calt` ligatures; the shaper's pass rate against the HarfBuzz oracle is printed and its PENDING list is explicit.
- Text at 4× zoom and under rotation is crisp through the SDF regime, and the atlas does not grow with the zoom level.
- Every module's wasm delta is recorded per backend and gated against a committed budget; a build with all modules off is measured too, and is the number guardrail 6 is about.
- The fault-injection switch loses the device mid-frame and the next frame is correct.
- `sample_count > 1` works on the iOS and Android bridges without breaking void3d's pipelines.
- Guardrail 9 prints a pass rate for GLES3 desktop and WebGPU instead of a SKIP.
- The colour-emoji line (TESTING.md `text/`) draws in colour through the module, presentation selectors pick text or emoji per grapheme, and a build with the module off pays none of it.
- A deferred CJK or emoji family answers coverage without loading, with the module on or off.
- WebGL2 and GLES3 desktop show no structural failure, and every `tests/PENDING.md` row owned by P6 is closed or re-owned by name.
- Metal macOS, Metal iOS and GLES3 Android have their readbacks written, and each reports a pass rate from a run on the human's hardware or stays a SKIP that names the missing run.

**Closes** (`tests/PENDING.md`, checked by the gate): `golden-missing:text/ligature`, `golden-missing:text/colourEmoji`, `golden-missing:image/animatedFrames`, `font-colour-emoji`, `style:line-length`, `ui-box-color-effect`, `sdf-non-uniform-bound`, `backend:gles3-desktop`, `backend:metal-macos`, `backend:metal-ios`, `backend:gles3-android`, `backend:webgpu`, `conformance:webgl2-pixel-centre`, `oracle:harfbuzz-full`.

**Tests.** T3: the full HarfBuzz shaping oracle, cases as data rows, snapshot committed, CI never needing `hb-shape`. T4: the wasm budget per module — the only gate that makes guardrail 6 real. T2: ligature, emoji, zoom and rotation scenes. Device loss is tested by its own switch, which is why the switch is a deliverable and not a debug aid.

**Measure.** wasm bytes per backend for: no modules, shaper, SDF text, emoji, SVG, sprite glyphs. Atlas bytes across a zoom sweep with the SDF regime on. Frame-profiler overhead when the overlay is off.

**Unblocks.** Nothing depends on P6; that is what makes it the place for everything optional.

**Risk → fallback.** The shaper is a third-party C library that has to build for five targets including wasm, and none of the three references shares it — GPUI uses the OS or cosmic-text, Makepad uses rustybuzz, Ghostty uses HarfBuzz or CoreText. If `kb_text_shape` does not build or does not cover enough, the fallback is HarfBuzz itself, which builds everywhere and costs more wasm, with the cost measured and stated rather than avoided. Without either, P4's surface still works: cmap, GPOS kerning, NFC input and fallback by coverage, with no ligatures — which is the state P4 ships in, so nothing regresses.

### The budget, at every phase

Checked and recorded per phase, from `tests/bench/`: draw calls, instances and uploaded bytes at 10 000 Box + 10 000 Label; frame time of the sprite-only scene, which must not regress (guardrail 8); CPU time of a fully static 100 000-node frame and of the scrolling 200-line text view from P5 on; atlas pages and bytes after a zoom sweep; wasm size per backend and per module. Counters gate; milliseconds are reported with a warn threshold and never fail a commit — the reasoning is in [TESTING.md](TESTING.md) "T4".

## Open

- **WebGPU uniform budget**: two uniform blocks per draw cost 512 B of the per-frame uniform buffer on WebGPU and Metal. Measure at P1 and fold what does not change per draw into fewer blocks if it bites.
- Reference facts were read from source, not benchmarked. Instance sizes and the one-draw-call claim are from planned layouts, not measured — P2's exit is where they become numbers.
- Non-uniform scale on SDF boxes and `erf` shadows is approximated; the error has not been characterised. It has a golden scene from P0 (`xform/`) and no bound yet.
- The command carries one rotated clip basis. Nested rotated Masks with the same world edge axes intersect exactly; different axes are rejected loudly rather than leaking. Whether Neon needs arbitrary rotated-mask intersections is unknown.
- System font discovery is host work; whether Ion or the Neon host owns it is undecided. Ghostty's Windows scanner is a stopgap, not a model.
- The Zed editor element (`crates/editor`) is outside the sparse clone: how it uses `paint_layer`, `split_at` and tab expansion was not read.
- **Headless Chrome has no WebGPU adapter on this box**, measured at P0 with and without `--use-angle=swiftshader`: the canvas is black. WebGPU conformance can only be taken headed until that changes, which is the one part of guardrail 9 that is blocked by something outside this repo.

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
| **fontstash** | removed at P3 step 3 | The text path before P3; stb_truetype 1.26 replaced it. | Its integer layout, its single fixed atlas. |

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
