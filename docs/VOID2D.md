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
2. **Retained node tree** — since P5 step 6 a node is a row in its scene's tables, held as a `NodeRef` and written through binders. Current ownership is `node.ms` `Scene2D`; construction is `scene.ms` `Scene2D.create`. This is the host the JSX/Solid reconciler binds to. Retention records changed rows or replays the unchanged list rather than walking every node on every frame.

Both required from day one: face 1 ships HUD/game now; face 2 is what the reconciler (`createNode` / `setProp` / `appendChild`) will drive later. A pure immediate-mode 2D layer would have no host for the JSX layer to reconcile onto. With the display list below, face 1 becomes "append to the list" and face 2 "a tree that appends to the list".

## The bar (2026-09-20)

Heaps is a game engine. Void is a rendering engine, and void2d must carry **application-UI rendering** when Void is a Neon backend — concretely, render a code editor like Zed: fine font control, high-quality antialiasing, fast and smooth. Decisions are judged against "a 13 px code font at 1× and 1.5× DPI looks and scrolls like Zed", not against HUD needs.

**The spirit (the human, 2026-09-29).** Void is a pure rendering engine and was never Heaps: WebGPU and sokol are first-class, and P5 step 5 already replaced h2d's objects with void3d's data model. Rendering power and performance come first. void2d exposes raw capability and leaves the app as much control as it can; convenience (policies, defaults, widgets, layout) is Neon's layer. Its syntax is the one that fits MetaScript's power and idiom best, not the one a Heaps user expects.

**The rule.** For every surface and every mechanism:

- **Capability first.** Expose what the GPU and the mechanism can do: bulk writes over spans, explicit promises that buy speed (children that do not overlap), raw transforms. A policy built on a capability is a helper, or Neon's. A convenience may be cut, since Neon can cover it; a capability never is (the human, 2026-09-29). Before dropping a reference's call, check that what it could do is still reachable.
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
- Where a draw cannot join that pipeline (custom shader, second atlas page, a sprite), the fallback is Makepad's **lanes** — backgrounds may cross a content barrier of the same parent — guarded by an explicit "children do not overlap" flag rather than Makepad's depth buffer. `TileGroup` is the h2d-native form of the same assertion. Landed at P5 step 11 with a lane as a run's place in its child's own sequence, since one pipeline holds both boxes and glyphs.

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
- **Fonts**: `Font { family, weight, style, features, fallbacks }` from bytes (G, M). The collection model is Ghostty's: ordered faces per style, deferred faces, explicit-vs-fallback presentation, a codepoint → face map that caches misses, whole-grapheme selection, **fallback size harmonisation**, synthetic bold/italic, lazy CJK/emoji families (Gh, M). System font discovery is host work. **Landed at P3 step 5** (`font.ms`): `registerFace(path, family, weight, style)` registers a face without loading it; `resolveFont(Font)` interns the value, picks the face in the CSS Fonts 4 weight order with italic preferred for italic, loads it, and synthesizes bold (weight ≥ 600 over a lighter face) and italic from the outline — Ghostty's policy on stb_truetype: `FT_Outline_EmboldenXY` ported to float at `lineHeight / 32` units, the advance widened by that strength as `FT_GlyphSlot_Embolden` does (Ghostty does not widen, because a grid cell is fixed), and a `tan 12°` skew about the baseline. A label takes it as h2d's `text.font = f`, spelled `setFont(id)`: since P4 `addFont` and `resolveFont` return `Result<FontId, FontError>`, so a refused font is the caller's to handle, not a label that silently keeps its old font. `features` honours `kern` only; any other tag refuses the font by name unless the shaper module (`-d:voidShaper`) is built, which takes any four-character tag. Fallback families resolve in the font's own weight and style, synthesized when they lack it. **Size harmonisation is Ghostty's `ic_width → ex_height → cap_height → line_height` chain, off by default** (`Font.sizeAdjust`). Measured on Inter + Noto Sans SC: `IcWidth`, Ghostty's default, draws hanzi 19.6 % larger than the Latin size — right for a terminal cell, wrong for UI text — while `ExHeight` moves them 0.5 %. The other references, read 2026-09-24 at the human's request, agree with off: GPUI does nothing (Rexa on GPUI adds only symbol fallback families), and WezTerm (`b09b56c`) has only an opt-in cap-height match, `use_cap_height_to_scale_fallback_fonts`, default false. **Colour emoji landed in P6 as the compile-time module `-d:voidColourEmoji`** (P6 "Colour emoji" has what was built and measured). stb_truetype reads no colour table and every reference draws colour glyphs through FreeType or the OS, so void reads them itself. Explicit-versus-fallback presentation and deferred faces are in the default glyph layer. **Whole-grapheme selection landed in P4** (`textLayout.ms` `assignFaces`, over `grapheme.ms`'s UAX #29 segmenter): a multi-codepoint grapheme takes the face of its first codepoint whose face covers every codepoint in it, joiners (ZWJ, VS15, VS16) ignored, as Ghostty's `indexForCell` does (`src/font/shaper/run.zig:318-382`). Where no one face covers it, Ghostty draws U+FFFD, because a terminal cell holds one font; a proportional line keeps a face per codepoint instead, so the text stays readable at the cost of a mark placed by another face's metrics.
- **Runs and decorations**: `TextRun { len, font, color, background, underline, strikethrough }`; a style change splits the shaping run, so a ligature is never two-tone (G, Gh). Backgrounds, underline, strikethrough and wavy are instances of the UI pipeline; thickness and position from the font's `post` / `OS/2` metrics with broken-table fallbacks (Gh), snapped. **The metrics landed at P3 step 6** as `TextLayout.decoration` (`glyph.c` `void2dGlyphDecoration`), float, y-down from the baseline to the top of each stroke, from the primary face: Ghostty's rule exactly, where a zero thickness marks a table broken but keeps a non-zero position, and each missing value is estimated from the ex height (OS/2 v2+, else the measured `x`, else 0.75 of the cap height, itself OS/2, the measured `H`, or 0.75 of the ascent). One divergence: the ascent in that last estimate is stb_truetype's `hhea` ascent, where Ghostty prefers `OS/2` typo metrics; the two agree for Inter. Emission and snapping are P4's, with runs. **Landed in P4** (`setTextRuns`, `textLayout.ms` `layoutRuns`, `labelText.ms` `runDecorations`): `len` counts UTF-16 units and the runs must cover the text exactly, or the label stops and says so; a run's colour multiplies with the label's, as h2d's `setColorSegments` does with `textColor` (GPUI's replaces it); kerning stops at a run boundary, standing in for the shaping-run split until P6's shaper; the decoration boxes are laid out with the text and only transformed and snapped when drawn, so a frame builds no array for them. A decoration runs on across the runs that share it (kind, colour, position and thickness), as GPUI's does (`line.rs:633-663`), so a squiggle under several syntax runs keeps one phase. Each run's decoration sits on its own face's metrics, Ghostty's rule as the P3 metrics have it, so one that crosses faces with different metrics steps there and restarts its wave, where GPUI puts one offset on the whole line: a **W** for metric fidelity. A styled label's bounds reach its widest row's end, so a background or underline over trailing spaces is neither culled nor clipped. The human chose h2d's multiply on 2026-09-27 (asked 2026-09-26); **landed in P5**, before the host contract: a styled label is written white and coloured by its runs, as in h2d, and T1 pins the product. Backgrounds, glyphs and lines bind the same glyph-page view, so `text/decorations`, three styled labels, is one draw call.
- **Caret and selection are their own instances**, never part of a text range, so a blink dirties nothing else (Gh, M). Selection is per-row quads unioned by smooth-min (M).
- **Atlas**: coverage pages and colour pages, 1024², a new page when full (G); 1 px gutter; a CPU mirror per page, dirty pages uploaded once per frame (sokol replaces whole images); ref-counted tiles; **a repack never moves a live tile** (Gh). **Resolved at P3 step 8: R8 coverage pages, with colour glyphs on a separate RGBA page kind**, not four planes per RGBA page (M) — P3 "Atlas page kinds" has the measurement. The R8 coverage kind is always built; the SDF kind is built with `-d:voidSdfText` and the RGBA kind with `-d:voidColourEmoji` (P6); the mask kind is not built. A page is reclaimed whole once no live tile and no quad of the current frame uses it. One divergence from GPUI: a glyph larger than a page (1023 px with the gutter) is refused with `AtlasError.TooLarge`, where GPUI gives an oversized item its own texture (GPUI.md:127); those sizes belong to the SDF regime.
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
- ~~**Integer glyph origins and rounded advances**, `kern`-only metrics, `split(" ")` wrapping, no `textWidth`, ≤ 16 fonts, the atlas expanded R8→RGBA on the CPU and fully re-uploaded on any new glyph, text lines centred on fractional pixels~~ — **closed at P3 step 3.** Layout is float and unrounded (`textLayout.ms`), a pixel-exact label lands its baseline on a whole device pixel and each glyph on a quarter pixel, kerning reads the GPOS `kern` feature through Extension lookups (stb_truetype 1.26's own reader skips them and read Inter's A-V as 0), wrapping breaks on the layout (at U+0020 only until P4, which breaks by UAX #14), faces are a growing table, and pages are R8 uploaded whole only when dirty. The fallback chain landed at **step 5**: a face falls back per codepoint through `addFallbackFont`, the fallback face loads on the first real miss, hits and misses are cached, the layout records each glyph's face and kerns only within one, and `text/cjkFallback` (Inter + a 504-hanzi Noto Sans SC subset, `tests/fonts/`) draws in one run at DPI 1.25; the `Font` value, synthetic styles and size harmonisation landed later in step 5; the rest of the collection model, colour emoji, landed in P6; whole-grapheme selection landed in P4. Still open: a glyph first rasterized into a page an earlier bracket already uploaded that frame is one frame late (`tests/PENDING.md glyph-page-second-upload`, P5).
- ~~The h2d surface still missing~~ — **closed at P5 step 11** with `TileGroup`, the last of it ([HEAPS.md](HEAPS.md)); `Mask.scrollX/Y` closed at **P5 step 10**; `parent`, `remove()`, reparenting with a cycle stop and the index queries closed at **P5 step 6**. `Tile.dx/dy`, `center()` / `setCenterRatio()` and uniform node pivots closed in **P2**; the text metrics (`textWidth`, `textHeight`, `calcTextWidth`, `splitText`, the node's `textLayout()` with per-glyph x and line boxes) at **P3 step 3**, read from the layout the label paints; the rest **P5**.
- ~~**Idle costs a draw**~~ — **closed at P5 step 9.** `Scene.isDirty()` says whether a frame would draw anything new, GPUI's `is_dirty` gating its frame callback (`window.rs:1798-1834`), so a host presents only then; since step 7 a present of a clean scene replays its list with no walk and no upload. T1 `tests/displayList/retain.ms` pins the flag, and the T4 row `idleDirty` is 0 on every bench scene.
- **Entry points declare `function main()` and nothing calls it.** Not a platform defect: `~/metascript/docs/CODE-STYLE.md` section 9 states the rule — "Nothing calls `main()`" — so an entry that ends at `return 0; }` builds a binary which exits at once everywhere, and a wasm module with the renderer linked out. `src/examples/mainSokol2d.ms` was fixed at P0: its WebGPU wasm was 48 064 B and is now 509 672 B, its WebGL2 wasm 111 522 B and now 410 724 B. `mainSokol.ms`, `mainCampfire.ms`, `iosEntryAnim.ms` and `iosEmbedEntry.ms` were void3d's entries and were left to that arc, which fixed all four at `7b7f163`; the `entry-main-not-called` PENDING row graduated when that reached `main` in `3860752` and was deleted in the commit that rebased onto it. — **closed everywhere: void2d at P0, the other four by the void3d arc.**
- ~~**A sokol view id past 2^24 names another slot in the replay.**~~ — **closed in P5** (REVIEWS.md "Audit before P4" #18). The display list stored `view` as one `float32`, exact below 2^24 only, where a sokol id is `(generation << 16) | slot`. A command now carries the id's two 16-bit halves in `CMD_VIEW` and `CMD_VIEW_HIGH`, rejoined by `void2dCommandView`, the one function the replay and the T1 test both read through; the emitter's saved view is a `uint32`. T1 "a view id past 2^24 reaches the replay whole" fails with one float and with a C rejoin that drops the high half.
- ~~**P5 retained lists outlive a closed Scene**~~ — **closed in P5** (B1, `8c48dd7`; review fix `d543f17`, REVIEWS.md "P5 re-review"). A release consumer creating and dropping 16 one-Rect scenes increased `buffersAlive` from 4 to 19; `batcher.c` `listAt` holds the buffers/staging and `render.ms` `poolOwner` holds filter targets after the owner disappears. Explicit Scene/context disposal follows `h2d/Scene.hx` `dispose` (`:727-730`), not P6's different device-loss/occlusion transition. The first prototype hit the compiler's `Vec<BitSet<E>>` reference-destructor bug and was reverted; the fix (recompiler `eacd555b`) is in BUILD `5c4246fb`. Now `scene.ms` `close` releases the list (`batcher.c` `void2dReleaseList`, retired while a frame is open), closes the filter targets the context owns (`render.ms` `closeContextTargets`), retires the context id for reuse (`displayList.ms` `retireContext`) and frees every row through the subtree walk `dispose` uses (`node.ms` `closeRows`); later use of the scene or its handles stops by name. Columns are not cleared one by one: their memory goes when the last handle does. Measured 2026-10-05 on BUILD `5c4246fb`, D3D11: `tests/integration/sceneLifetime.ms` (gate.sh) closes 16 blurred scenes beside a kept one with buffers and targets back to the kept baseline each time, the kept scene's pixels unchanged, and the last close back to the start; the same churn without `close` grows buffers 5 → 35 and filter targets 4 → 64 over 16 frames.

## Guardrails

1. **Draw order.** Painter's order stays, and the unified UI pipeline makes it batch. BoundsTree reordering is not planned: GPUI rebuilds it from empty every frame, and it is O(log n) per primitive against the 1M-node target in [SCENE-SCALE.md](SCENE-SCALE.md). The cheap form is kept: `TileGroup`, and a node flag asserting that children do not overlap, both since P5 step 11. No depth buffer for 2D order. Revisit only if measurements of real Neon UI show state-change draws dominating.
2. **Node width.** A node was one 71-field `Node2D` until P5 step 6 and is now a row of value groups, one per pass that reads them. Box style and text runs are read only when emitting, so they live in side tables — the side-table bar in SCENE-SCALE.md.
3. **Filters stay — and get fixed.** Render-target filters on arbitrary subtrees are h2d semantics; the `erf` shadow is a fast path beside them. The blur is corrected: downsample by 2^k then blur at a 1-texel step, or dual-Kawase.
4. **Paths: no MSAA intermediate, no baked fringe.** A pass break per path batch is a full tile store/load on mobile GPUs; a baked fringe scales with the node. Store the edge normal per fringe vertex and extrude at the vertex stage by `1px / scale`: today that is `draw.ms` `drawMeshRange`, where void2d already transforms a mesh's vertices on the CPU, and it moves into the vertex shader with that transform if a measurement ever asks for it (P6 "Graphics antialiasing").
5. **MSAA is a knob, not a dependency.** Expose `sample_count` for iOS/Android instead of hard-coding 1. Analytic coverage is still required: the embed host owns the framebuffer and its sample count.
6. **Text is where the weight goes, so it is modular.** The glyph layer goes in by default. The shaper, a hinting rasterizer, colour emoji, the SDF text path, procedural sprite glyphs and the SVG rasterizer are compile-time modules; CJK and emoji families load on a real miss. A game build pays for none of them. Measure the wasm delta of each.
7. **No ClearType.**
8. **Pay for what you use.** Snapping, the pixel-exact text regime and the UI pipeline engage only for nodes that use them; a sprite-only scene must not regress at any step.
9. **Same pixels on every platform.** No OS text system, no per-platform text path (Makepad's slug on macOS/web, SDF on Windows), no runtime shader generation. **This is a number: 37/37 scenes byte-identical on D3D11 at P0, 48/48 at P1, 67/67 at P2, 69/69 at P3 and 72/72 at P4, where WebGL2 became the second measured surface at 65/69 (through ANGLE on D3D11; 68/72 at P4), with five other surfaces reported as SKIP with a reason** — GL core 4.3 desktop (glsl430), Metal macOS, Metal iOS, GLES3 Android, WebGPU. One golden set authored on D3D11, every backend compared against it, a pass rate per backend ([TESTING.md](TESTING.md) "Guardrail 9"). P3's five-backend run was not reached: GL core 4.3 desktop and WebGPU are P6's, Metal and Android wait on the human's hardware. What each missing readback costs, and what browser conformance needs beyond a driver, is written down there rather than guessed at.

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
   this audit.** P2 unified the commit path; after M18–M20 the caller owns it explicitly.
   `tests/integration/mixedFrame.ms` prepares the `ForwardRenderer`, opens one shared screen
   pass, draws its lit scene and the void2d overlay, ends the pass and commits once. Its real
   readbacks also exercise a foreign registered shader, blending and both registration orders.
   The old cube-only/endFrame description no longer names this consumer.
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
| Metal, iOS and Android reported as SKIP with a reason | yes, plus GL core 4.3 desktop (glsl430), WebGPU and WebGL2 — seven surfaces, one measured |
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
The UI program carries the effect row, so an image style and a BoxStyle compose with
`colorMatrix`, `colorAdd` and `colorKey` (`b76fee5`, `04484fd`, `4f5c8b7`): the fragment stage
applies the effect after the mode's colour, and the `prim/effectOnUi` golden draws every UI kind
plain and under grayscale. Plain Rect keeps the existing vertex colour pipeline.
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

The vertex path's `srcPremult` correction is intentionally disabled when any colour effect is
active: a matrix other than the identity, any `colorAdd` lane including alpha, or a `colorKey`
(the key since G). That is required for the glow/drop-shadow alpha-only matrix:
it must turn the sampled render target into a new straight-colour silhouette before the shader
premultiplies it. The same gate would be wrong for an unrelated matrix applied directly to a
render-target texture because it would multiply coverage twice. The retained filter path avoids
that combination by applying node effects inside the target and resetting the composite. Since
2026-10-03 the shader has that path ("Door closure" G): a premultiplied source with any effect is
unpremultiplied at the sample, and the silhouette's alpha-only matrix draws the same bytes
through it.

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

**Resolved at P3 step 8: R8 + RGBA.** `tests/experiments/pageKinds.ms` runs one workload through the real atlas and packer and reads it both ways (plane p of the four-plane layout is R8 page p on RGBA page p / 4, so one run answers both). The defined workload — code and prose at 12, 13 and 14 px at DPI 1.0 and 1.5 plus a 24-symbol icon run at 16 and 24 px, 3 456 glyphs, 1 384 tiles — fits **one** page either way: 1 MiB resident as R8 against 4 MiB as RGBA, 0 page switches either way, and every new glyph re-uploads 1 MiB against 4 MiB. Four planes win only under stress: ten sizes at four DPIs (5 910 tiles) need 3 R8 pages and switch pages 738 times in that draw order, where one RGBA page switches none — at 4 MiB against 3 MiB resident and the 4× upload per new glyph. The plane selector would cost no instance bytes (glyph mode leaves `params0.yzw` unused). Emoji do not enter the comparison: they need all four channels, so they take RGBA pages under both layouts; they were not rasterized when this was measured and are since P6 (`-d:voidColourEmoji`). If multi-page frames become common, binding several R8 pages at once removes the switches without the 4× upload.

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
- **Conformance: the exit's five-backend run is not met — 2 of 7 surfaces measured.** D3D11 69 / 69 byte-identical; WebGL2 65 / 69, and all seven `text/` scenes are byte-identical there. The WebGL2 number is narrower than a second driver: headless Chrome reports `ANGLE (NVIDIA, NVIDIA GeForce RTX 5090 ... Direct3D11 vs_5_0 ps_5_0, D3D11)`, so it proves the GLSL ES path, GL's conventions (the dither bug above was one) and ANGLE's translation, on the same GPU and D3D11 driver. GL core 4.3 desktop and WebGPU move to P6, which can run both on this box; Metal macOS, Metal iOS and GLES3 Android wait on the human's hardware (`tests/PENDING.md backend:*`).
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

**Review status, 2026-10-05: SHIP WITH FOLLOW-UPS** (REVIEWS.md "P5 re-review"), closing the
2026-09-30 SEND BACK. Permanent Scene teardown is `Scene2D.close` (B1), and the re-review's
in-frame closure defect is fixed. Landed on main at `dcfa744`. The follow-up is the post-rebase
web gate, blocked by Yoga's emcc provider.

**Par.** Past all three references. Makepad is the only running example of persistent instance ranges with an in-place paint-only patch (MAKEPAD.md:33, 102); none of the three has a cheap scroll — GPUI rebuilds every visible item, Makepad re-records, Ghostty re-emits rows. A retained tree is what makes the cheap form possible, and this phase is where Void's model earns its keep.

**Lands.**

- Persistent instance ranges with dirty-range upload; draw order rebuilt only on structural change; "identical bytes → skip the upload" (MAKEPAD.md:117). **Landed at P5 step 7**, the upload written per stream: a changed range re-uploads its whole stream until sokol writes a range of a buffer.
- The in-place paint-only patch: a paint-only write and a caret blink write instance floats and never walk the tree. void2d has no hover or focus; what the host does on either is a colour or alpha write, and that is the paint-only case.
- `TileGroup` — the h2d-native retained multi-quad node, one sprite run per change of texture — and the non-overlap node flag, with Makepad's lane fallback where a draw cannot join the unified pipeline (a custom shader, a second atlas page), guarded by the flag rather than by a depth buffer. **Landed at P5 step 11**, all three.
- `Mask.scrollX/Y` applied as a list-level shift after the per-instance clip: `clamp(clamp(p, clip) + shift, viewClip)` — the formulation Makepad wrote and never used (MAKEPAD.md:111) — with the offset snapped to a device pixel, so a text run's subpixel variants survive the translation.
- `Scene` reports whether it changed and can re-present its last list; scheduling stays the host's.
- The missing `Object` surface: `parent`, `remove()`, reparent-on-add with a cycle guard, `getChildAt` / `getChildIndex` / `numChildren`, `name`; `localToGlobal` syncing first instead of returning last frame's matrix (`node.ms:344-350`). **Landed at P5 step 6**: `localToGlobal` and `globalToLocal` multiply the node's ancestors' local matrices when asked, so they answer after a write and before any frame.
- The camera out of every world matrix and into a uniform, as h2d has it, so a camera move stops re-multiplying the tree (`scene.ms:115-121`: `presentAt` hands the camera and scale mode to `sync` as the root's parent world). **Landed at P5 step 10 for the translation**, as the root's scroll scope; a zoom or a rotation still re-multiplies the tree, since a label is rasterised at the scale it is drawn at.
- A Label that leaves the scene without `dispose` stops pinning its glyph pages. h2d ties allocation to `onAdd` / `onRemove`, and this phase's `remove()`, like the existing `removeChild` and `removeChildren`, is where void does the same; T1 asserts that a removed Label holds no tile reference (closes `tests/PENDING.md label-dispose-pins-page`). **Landed at P5 step 4** for `removeChild` and `removeChildren`: a removed subtree's Labels release their tiles and keep their shaped layout, so a label added back places again from the atlas's index, hitting the tiles still resident, and only `dispose` frees the layout. `remove()` (step 6) goes through `removeChild`.
- Multi-bracket frames draw every glyph in the frame that first asks for it: a page already uploaded this frame takes no new tile and is not reclaimed (C tracks `s_pageUploaded`), which closes `tests/PENDING.md glyph-page-second-upload`. **Landed at P5 step 4**: the upload state moved from `batcher.c` into `glyph.c` beside the page's dirty flag (`void2dGlyphPageTakeUpload`), so the atlas asks it directly and T1 drives it with no GPU; a glyph that finds every page full or uploaded this frame at the page cap is refused this frame and placed the next, which is F1's retry.
- Host-facing rendering services collected into one surface: text measurement, text geometry, hit geometry (`globalToLocal`, world bounds, clip-aware containment), the change flag, and the frame counters from P1.
- Render bounds apart from h2d's `getBounds`. P4 grew an editing label's query with the selection's gloop and leading because culling and filters shared that box (REVIEWS.md "P4 re-review" F-b). **Built at P5 step 12:** the query excludes editing growth; culling and filters retain it. A run's colour multiplying with the label's, h2d's rule (P4 F2, answered 2026-09-27), landed before this contract.

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

   **Landed at P5 step 6** (`bbcc975`, `20453c8`): the renderer and every consumer in this repo on
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
     121 ms for `Node2D`); `20453c8` moves only the child that changed.
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
   - **A row's Yoga node is freed where the row leaves the tree**, because the host owns that
     free (`~/metascript/yoga/docs/ARCHITECTURE.md` "Integration modes": the pass cannot tell a
     dropped node from one that moves, so it frees neither). `removeChild`, `removeChildren`
     (so `remove()`), `addChild` under a different parent, and `dispose`'s walk call
     `freeLayoutTree` on a row that holds one; the next pass builds a fresh node and re-applies
     the style. Adding a child again under its own parent keeps its node, so a bring-to-front
     does not rebuild a subtree. A move had to free because the old Yoga parent still owns the
     node, and Yoga's single-owner assert aborts when the new parent is synced first; only the
     moved top can be owned from outside, so only it is checked. Cost, `msc test` debug build on
     a loaded machine, one run: `removeChildren` of 20 000 laid-out siblings 3.7 to 88 ms
     (Yoga's child removal scans the owner's children), of 20 000 rows with no layout 3.7 to
     4.5 ms. Pinned by `src/test/layoutCheck.ms` and, counting the process heap on macOS,
     `tests/isolated/yogaLeak.ms`.
   - `==` on `NodeRef` fails to build on C and JS in a module that does not import `NodeId`
     (`~/metascript/.inbox/compiler/2026-09-28-struct-eq-nested-type-not-imported.md`);
     `src/test/nodeCheck.ms` names `NodeId` for it and is the parked site.
   - The allocation stage lists the new frame path (`drawRow`, `syncRow`, `meshBounds`,
     `clearChanges`, `refOf`, `liveRow`, `imageStyleOf`). On BUILD `3f6873ee` it also found
     `faceAtPath` copying each `LoadedPath` in a `for..of` on the rebuild path, already so on
     the step 5 head built on that compiler; `c139456` reads it by index.
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

   **Landed at P5 step 7** (7a `bbf7aca`; 7b `50b18fb`, `b26c73e`; 7c `2429d22`, `16a55ed`,
   `91cc7c0`; 7d `cfd83ea`, `6797d6f`, `74dc2e8`): every D3D11 golden byte-identical (72/72), now
   captured on retained frames, since the runner's second and third draws of a scene change
   nothing. What the build decided that the plan does not say:
   - **The oracle resyncs every world.** `tests/displayList/retain.ms` compares, after each write
     of the corpus, the retained streams with a full record of the same state, and the full
     record recomputes every world from the locals. The first version did not: a patch that
     left a descendant's world stale copied it into both sides, and a mutation skipping the
     descent passed. It fails now, as does one skipping the in-place emission.
   - **A bracket starts its runs in the UI pipeline** (`2429d22`). `begin2d` never reset the
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
   - **A shape change splices the next frame from the last** (`adf81a7`), GPUI's `reuse_paint`
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
     1.77-2.75 against 7.65-9.75 on a loaded box; the windowed probes were re-read on a quiet
     box at step 14, below.
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

   **Landed at P5 step 8** (`213e55e`, `b4dec89`), on step 7's paint ranges rather than a second
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

    **Landed at P5 step 10** (10a `a5e2b45`, golden `9da2a4f`; the shader `022d376`; 10b below).
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

    **The surface, decided by the human on 2026-09-29** under "The rule": raw capability, and
    every capability of h2d's `TileGroup` kept (`h2d/TileGroup.hx:562-718`,
    `h2d/impl/BatchDrawState.hx:43-61`). Only its conveniences are cut.
    ```ts
    const map = scene.tileGroup();
    map.setTiles(cells);        // replace all; a tile: position, a Tile (any texture), RGBA, scale and rotation
    map.appendTiles(more);      // grow without rewriting the tiles already there
    map.setTile(42, cell);      // rewrite one tile in place
    map.setRange(100, 500);     // draw tiles 100..599 only (h2d's rangeMin / rangeMax)
    map.clear(); map.count();
    list.setNoOverlap(true);    // a promise that buys batching; a debug build checks it and names the overlap
    ```
    - **Kept as capability:** tiles from several textures in one group, drawn as one run per
      texture as h2d's `BatchDrawState` splits them; a tint and a transform per tile; appending
      without a full rewrite, since `setTiles` alone would make growth quadratic; the sub-range.
    - **Cut as convenience:** `add`, `addColor`, `addAlpha` and `addTransform`, which are one
      appended tile with fields filled in; `setDefaultColor`, since the colour is in the tile;
      `invalidate`, since a write marks the group itself. Neon can wrap any of them.
    - The group's own tint, alpha, blend and filter are the node's, as for every node.

    **The group landed at P5 step 11**, the flag and the lanes after it (below). What the
    build decided that the surface does not say:
    - **A tile is one instance of the flat sprite pipeline**, so a tilemap pays for no SDF
      (guardrail 8). The group's runs split where the texture changes, in tile order, as
      `BatchDrawState.setTexture` splits them (`h2d/impl/BatchDrawState.hx:43-61`); tiles are
      never sorted by texture. Each run resolves its command once and appends its tiles with
      no state check (`draw.ms` `beginSprites`, `appendSprite`: Makepad's
      `begin_many_instances`, MAKEPAD.md:107). A group with a colour effect takes the vertex
      path tile by tile, as a Sprite does. A tile's colour multiplies with the node's colour
      and alpha, as h2d's vertex colour meets the Drawable's in the shader.
    - **`setRange(first, count)`** draws tiles `first` to `first + count - 1` that exist;
      `ALL_TILES` is the default count, where h2d marks an unset `rangeMax` with -1, and a
      negative start or count stops and names both. The bounds hold every tile whatever the
      range, as h2d's `getBoundsRec` reads its whole content (`h2d/TileGroup.hx:593-596`),
      with each tile's four corners through its own scale and rotation. Five oracle trees
      check it against Heaps (`tileGroup*` in `tests/oracle/h2d.json`): the gate reads
      **20 / 20 trees**.
    - **`clear()` is one call** for a Graphics and a TileGroup, in `node.ms`, and stops on any
      other kind: two `clear` extensions on `NodeRef` from two modules would collide in an
      importer that takes both.
    - **`setTile(index, cell)` overloads the Sprite's `setTile(tile)`.** An object literal as
      its cell resolves no overload, a compiler defect
      (`~/metascript/.inbox/compiler/2026-09-29-object-literal-argument-misses-arity-overload.md`);
      an app binds the cell first. Nothing in void is parked on it.
    - **A write that reshapes the group re-emits it**, step 7's path: `setTiles`,
      `appendTiles`, `setRange`, `clear`, and a `setTile` that moves, resizes, turns or
      re-textures its tile. The in-place attempt keeps it when the runs keep their shape and
      splices otherwise.
    - **A `setTile` that keeps its tile's shape and texture writes that tile's one sprite
      record in place**, Makepad's paint-only path (MAKEPAD.md:33) at tile granularity
      (`render.ms` `retileRow`), and uploads the sprite stream only if the record's bytes
      moved. Three conditions keep it right, and T1 has a case for each that fails when
      the condition is dropped: the group took no other write that frame (a colour with the
      edit), did not move or fade through a parent, and recorded one sprite per drawn tile
      (not the vertex path of a colour effect, not culled; dropped, the write lands outside
      the stream and the test binary stops). A camera pan that flips the group's cull and
      more edits in a frame than an eighth of its tiles (16 at least) re-emit the group
      instead; those two save work and guard nothing.
    - **Appending re-emits the group**, and stays so: no reference appends to a retained
      range. h2d's `add` fills a CPU buffer that `invalidate` re-uploads whole
      (`h2d/TileGroup.hx:610-612`, `alloc` at `:513-520`), and Makepad re-records the draw
      item. What the call keeps is the capability: a group grows without the app sending its
      tiles again.
    - Measured, `out/tmp/p11probes/tileCost.ms` (release, 1280 × 720, one texture, one run
      of 120 frames per row, twice, on a box at 57 % load, so not an A/B), 10 000 and 100 000
      tiles: a still frame 0.02 ms and 0 B; one `setTile` a frame **0.03 and 0.24-0.41 ms**,
      against 0.35 and 3.2 ms before the in-place record, with the whole sprite stream
      uploaded (320 000 and 3 200 000 B, step 7); one appended tile a frame 0.95-1.1 and
      8.4-9.0 ms, spliced; `setTiles` of every tile 0.41-0.44 and 4.1-4.2 ms, plus 0.08 and
      0.9-1.1 ms for the write.
    - T0 `src/test/tileGroupCheck.ms`; T1 snapshot `tileGroup` (three sprite runs, views 11,
      12, 11, and the vertex fallback) and the writes in `tests/displayList/retain.ms`; aborts
      `tileOutOfRange`, `tileRangeNegative`, `clearOnRect`; T2 `image/tileGroup`, two
      textures, tints, a turned, a stretched and a flipped tile, and a red tile outside the
      range covering the rest if the range fails. Every other golden stayed byte-identical.
    - The T1 printer dropped the sign of a value between -1 and 0 (`snapshot.ms` `f2` printed
      -0.5 as `0.50`), so a rotation lane could flip its sign unseen; `rotatedClip` and
      `textPrimitives` moved by their signs alone.

    **The flag and the lanes landed at P5 step 11.** `list.setNoOverlap(true)` writes the order
    group, so making or withdrawing the promise re-records the parent. What the build decided:
    - **The rule.** Under a node that promised no overlap and has two children or more, the
      k-th run of every child draws before the (k+1)-th run of any child, and each child's own
      runs keep their order. Makepad's lanes are two fixed ones, quads then text, where only a
      quad may cross a text call of the same parent, because a depth buffer backs the move
      (MAKEPAD.md:30, `platform/src/draw_list.rs:2554-2584` at `5e9a697`). void2d draws boxes
      and glyphs in one pipeline, so a lane is a run's place in its child's own sequence, and
      the promise stands where Makepad's depth buffer stands. GPUI's `paint_layer` puts a
      layer at one order and draws it kind by kind (GPUI.md:20): the same promise, with
      void2d's runs as the kinds.
    - **How it records.** The scan splits the open run where the parent's own content ends and
      where each child starts (`draw.ms` `splitRun`: a non-empty run is closed and reopened in
      the same state), records the children as before, and at the subtree's end lays the
      region's commands out lane by lane (`displayList.ms` `layLanes`): each run's records move
      so that runs of one state are contiguous, adjacent runs of one state merge, and the
      first folds into the run before the region when the two meet. The last run is reopened,
      so what follows the region continues it as it would have continued the unsplit run.
    - **Where it keeps painter's order.** A region holding anything but draws (a Mask's
      scissor, a filter's target, a blur) or a colour effect is not reordered; its splits
      merge back and it records what no promise records, byte for byte. So does a promise
      with nothing to gain.
    - **Retention.** A row whose own content is one run gets its paint range moved to where
      its records went, with that lane's run state, so a colour, text of the same length or a
      tile edit inside the region still patches in place. A row whose content spans runs or
      streams (a label over two glyph pages, a TileGroup of several textures) takes
      `PaintState.InLanes`, and a write to it scans: Makepad's granularity. A splice still
      copies the region's clean rows, but never joins a run across a child boundary.
    - **A debug build checks the promise** (`render.ms` `checkNoOverlap`): once the region is
      laid out, the children's drawn bounds, cut by their Masks, are swept along the axis they
      spread on, and an overlap stops the frame naming the parent and both children (abort
      `overlapPromise`). A release build trusts the promise. Touching edges are no overlap; a
      shadow that reaches a neighbour is one.
    - Measured, `out/tmp/p11probes/laneCost.ms` (release, 1280 × 720, run from the repo root
      so the default font loads, 120 frames a row, twice, load 18 %, not an A/B): 288 cells
      of a box, an icon sprite and a label under one parent draw in **577 draws without the
      promise and 3 with it**; a still frame 0.22 → 0.011-0.015 ms, the replay of 577 draws
      gone; a full frame 0.45-0.48 → 0.42 ms, the layout costing less than the draws it
      drops; one cell's colour 0.21 → 0.026-0.028 ms and a label's text of the same length
      0.33-0.35 → 0.037 ms, both patched in place; the bytes uploaded unchanged.
    - T1 in `tests/displayList/retain.ms`: six rows draw 13 runs without the promise and 3 with
      it; the promise with nothing to gain and a region holding a clip record byte-identical
      streams; every instance of painter's order is drawn under the same state, and each
      row's own draws keep painter's order; the retained frame equals a full one across a
      colour, text of the same length and longer, an icon's texture, a move, a row added and
      hidden, the promise withdrawn and made again, and a pan; nested promises. T0 in
      `src/test/nodeCheck.ms`. T2 `order/noOverlapLanes`: one list in lanes beside the same list
      in painter's order, byte-identical by `tests/golden/invariants.ms`. The controls: not
      moving the UI records fails the order check and the writes; not moving the rows' ranges
      fails the writes; not folding into the run before the region fails the counts and both
      identities; reversing the lanes fails the golden's invariant.
12. **The host services** in one surface, and render bounds apart from `getBounds` (P4 re-review
    F-b), shown to the human first as Neon's `host.ms` before and after. The run-colour rule
    (P4 F2, h2d's multiply, answered 2026-09-27) landed first.

    **Built at P5 step 12, approved 2026-09-30.** `render.ms` `hitTest` supplies the geometric
    query; Neon owns dispatch and picking order. It reads the live local matrices rather than
    the last frame's world cache, takes the same inverse-affine and scroll composition as
    `node.ms` `globalToLocal`, and tests each ancestor Mask before entering its scrolled content.
    Invisible subtrees and collapsed geometry do not hit. It tests content bounds, not texture
    alpha, glyph coverage, shadows or editing gloop; it adds no event system.

    `getBounds` now excludes a label's editing gloop and leading, recursively through parent
    and Mask queries. The render path keeps both for culling and filter crops. T0
    `src/test/nodeCheck.ms` holds cursor, selection, parent, live-transform, nested rotated Mask,
    scroll and collapsed-node cases. T1 `tests/displayList/snapshot.ms` holds the seam: text wholly
    outside the viewport still records the selection whose gloop reaches it. The old bounds
    assertions requiring a query to enclose editing pixels were removed, not re-pinned.

    Font-true measurement already exists: `render.ms` `calcTextWidth`, `textWidth`, `textHeight`,
    `xForIndex`, `indexAt` and `lineBoxAt`; no callback or second measurer is added. A standalone
    consumer built with `MSC_NO_GLOBAL_CACHE=1 msc build hostServices.ms --release` under
    `out/tmp/p14probes`, run from the repo root, read CJK text at 32 px and identical bounds
    before and after editing. The temporary consumer was removed after proof; the permanent
    measurement contracts remain in `src/test/textMetricsCheck.ms`. Neon receives the host
    migration note; Yoga receives the missing measure-hook request, rather than a binding
    change made from this worktree.

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
    and `AutoZoom` mean something else in void2d, a design size where h2d takes a zoom level;
    the human kept void2d's on 2026-09-29 (HEAPS.md "Do not copy from h2d"), so the oracle
    compares the other four. The gate now reads **15 / 15 trees and 4 / 4 scale modes**. Two compiler cards came out of it:
    `2026-09-28-narrowed-ref-union-loses-extensions` and
    `2026-09-28-c-backend-fuses-multiply-add`. The second is why `wholeSceneUnits` keeps its
    product in a binding of its own: C fused `window - design * zoom` into one rounding where
    JavaScript did not.
14. **The measurement** listed under "Measure", and the wasm delta against the P4 head built the
    same day on the same compiler.

**Measured in P5 so far (2026-09-27).** The installed msc changed from BUILD `598ca62e` to
`c54a8671` during step 4. It makes `const` deep through `struct`, `T[N]` and `Vec<T>`, so every
binding void writes became `let` (`b06e7e9703507b9228d93517cc1dbf59b875e02a`, void3d's included; `~/metascript/.inbox/void/`
has the note). An older tree needs the same binding changes to build on it. The step 3 and
step 5 readings used `c54a8671`; later readings name their own BUILD below.

- Step 3, the `UiInstance` record: an interleaved A/B against `2ee05c2af670e499f478be4103c95a1c0af6354e` was inconclusive on a busy
  box (UI 10.20 → 10.81 ms at the median over 5 clean pairs of 6, then 4 clean of 10), and a
  GPU-free emission loop over the UI bench scene, the minimum of 40 × 5 frames, read −0.9 to
  +0.5 ms pair by pair. Step 14 measures the net phase, not this record change in isolation.
- Step 5, change model A, `tests/experiments/changeModel.ms` at `754dc9fff61a47d2e805c8d01624600e780eb418`, deleted with `Node2D` at
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
  `out/tmp/abStep6.sh`. Tree A is `d7a2c72192c3c3750932c553e2473a810eed3e23`, the step 5 head plus the `faceAtPath` fix; the fix
  alone is neutral, `5d4bf10a3aabddae0f5a7feaf758c27cb5d6e237` against `d7a2c72192c3c3750932c553e2473a810eed3e23` reads UI 10.61 against 10.61 ms (6 clean pairs of
  8) and sprites 1.70 against 1.59 ms (8 of 8). `scripts/bench-ab.sh`, 8 interleaved pairs:
  **UI `present` 11.78 → 5.58 ms** (5 clean pairs of 8; B ranged 5.22-5.74), **sprites 1.91 →
  1.05 ms** (8 of 8). The frame still walks and draws every node, so this is what the old
  frame spent reaching 71-field objects and comparing seven transform fields, eight text
  fields and a string per label every frame, which a `Local` bit and a `stale` flag replace.
- Step 6, `tests/experiments/nodeTables.ms` against the same loops over `Node2D` built in
  `d7a2c72192c3c3750932c553e2473a810eed3e23` (`out/tmp/p6probes/node2dControl.ms`), 100 000 nodes (50 000 cards, each with a
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
  still packed and uploaded the whole list, UI read 0.58-0.63 ms. Step 14's readings follow.

**P5 step 14 measured, 2026-09-30.** All native binaries are release, D3D11, 1280 × 720,
sample count 1, high DPI off, 20 warm-up plus 120 measured frames, msc 0.2.55 BUILD `35601908`.
The B arm is original tree `81722cbb846ae1e6b6ef789b9d8690f8a2bb08e2`, before step 12's
host queries. A arms are archived `8a473f3`, tree
`5c2ddf9a967800a2fba91fd0729f8118b8ec15e1`, and P4's measured head `c85f5d0`, tree
`9754328484f77e9604b4e18718e288a5340f8c42`. Both archives need the `const` → `let` binding
changes described above on today's compiler; the P4 web archive also takes its recorded
`sortByZ` span park. `4d357f7` is the P3.5 head, not the P4 head.

- `sh scripts/bench-ab.sh out/snap/8a473f3 . 8 Ui Sprites`: the fourth run has **8/8 clean
  pairs on both scenes**, no broken or noisy pair, load 6.4–16.0 %. Median UI `present`
  **15.269 → 0.01895 ms** (A 13.81–19.10, B 0.01594–0.02225); sprites **3.6247 →
  0.01727 ms** (A 3.53–4.48, B 0.01572–0.02317). The pre-P3 timing exit holds by its
  every-pair-clean rule. The earlier three noisy runs are discarded.
- The same command against `out/snap/c85f5d0`: UI **15.389 → 0.01817 ms**, 8/8 clean
  pairs; sprites **3.5005 → 0.01644 ms**, 7/8 clean pairs, one noisy pair discarded under
  T4's rule. These are unchanged-frame `present` costs: A walks and uploads every frame,
  B replays a retained list without uploading. They are not a claim about a frame that
  changes every node, nor about first-paint cost.
- HEAD-only bench readings at load 7–16 %: UI 0.0190, sprites 0.0188, text 0.0164,
  editor 0.0267 and scroll **0.0349 ms**, all uploading **0 B**. Scroll retains the editor's
  13 214 instances and one draw; P4's recorded editor reading was 0.58 ms and 1 427 112 B
  per frame, on its earlier BUILD, not a same-scene scroll A/B. `idleDirty` is 0: a host
  that gates presentation on `isDirty` issues no idle draw. Calling `present` anyway still
  replays its one draw, by contract.
- `out/tmp/p14probes/static100k.ms`, run from the repo root, load 21 %, one reading:
  **100 251 nodes** (50 000 cards, each with a label, 250 groups and the root), static
  `present` **0.0333 ms, 0 B**. The probe prints its card count, 50 000. One card's colour
  write presents in 1.206 ms and uploads 15 660 000 B, the whole UI stream, as step 7 requires.
  These are 120-frame averages, not A/B deltas.
- Windowed probes, rebuilt on this BUILD and run from the repo root: `termGrid.ms`, load
  20 %, still 0.0247 ms / 0 B, same-length row 0.232 ms / 972 000 B, one growing row
  0.562 ms / 980 694 B (120 splices), every row rewritten 3.413 ms / 987 120 B.
  `hoverUi.ms`, load 13 %, still 0.0288 ms / 0 B, colour 0.511 ms / 5 280 120 B,
  changing a label's length **1.692 ms / 5 280 174 B** (120 splices). These re-read step 7's
  windowed cases, not an A/B against the older BUILD.
- `out/tmp/p7probes/spliceCost.ms`, headless, load 7 %, three interleaved rounds of 20:
  splice **1.022–1.318 ms** against full record **5.635–5.779 ms**. Its printed `reused`
  is sampled after the full record resets it, so that row proves no reuse count.
- Both archived web trees built today through `scripts/build-web.sh`, same compiler and
  dependencies: B WebGPU / WebGL2 **2 110 022 / 1 882 147 B**, P4 **1 703 539 /
  1 474 971 B**, delta **+406 483 / +407 176 B**. This is the pre-host-query tree above,
  not a post-rebase size. P6 owns module weight and the wasm budget; no size threshold is
  claimed here.

**Defects closed.** Two "Known defects" lines: the h2d surface — `parent`, `TileGroup`, `Mask.scrollX/Y` and the text metrics it points at — and a sokol view id past 2^24 naming another slot. Also the idle cost: `Scene.present` walking and drawing every frame with nothing knowing whether the tree changed.

**Exit.**

- Scrolling the P4 editor scene uploads only the shift and walks no tree. Met at step 10 for a Mask that is a scroll scope: the scroll bench uploads 0 bytes a frame.
- A caret blink and a hover re-emit their one node, upload only the stream it changed, and cause no structural change. Amended 2026-09-28 from "upload a known small number of bytes": no reference writes a range of a buffer (step 7).
- An idle frame issues no draw and no upload.
- A fully static 100 000-node frame costs a column sweep, not a tree walk (the SCENE-SCALE.md budget).
- One node can no longer sit under two parents (`node.ms:305-309`).

**Closes** (`tests/PENDING.md`, checked by the gate): every original row P5 owned is closed and deleted. The view id row, at step 2; the second-upload and dispose-pins rows, at step 4; the object-surface and two-parents rows, at step 6, with the span-of-interface style row, whose sortByZ step 6 deleted; the idle row, at step 9; the scroll golden row, at step 10; the h2d oracle row, at step 13, and the two scale-mode rows it opened, when the human kept void2d's own Zoom and AutoZoom (2026-09-29). The new Scene-teardown finding is still open, blocked by its compiler-owned row; the phase has not shipped.

**Tests.** T1 carries this phase: mutate one node, assert exactly one dirty range of a known size; assert byte-identical re-records; assert zero instances written on a blink; assert the draw order rebuilds only on structural change. T3: the h2d oracle for `getBounds`, `localToGlobal` / `globalToLocal`, mask intersection and scale modes, with HEAPS.md's deliberate divergences as the seed PENDING list. T4: scroll and idle budgets gated on uploaded bytes, which are deterministic.

**Measure.** Scrolling the 200-line text view: CPU per frame and uploaded bytes per frame, both against P4's numbers. A static 100 000-node frame: CPU. An idle frame: zero draws. The UI bench scene must not regress, and **UI `present` must come back to or below the pre-P3 control `8a473f3` under `scripts/bench-ab.sh`, with every pair clean** — the label-emission cost P3 left, +0.5 ms on a quiet box and +1.4 to +1.8 ms under load, is owed here (P3 "Measured at P3 step 8"). P3.5's head already reads below it, 13.05 against 13.54 ms, but over 7 clean pairs of 8, so the line is not yet met by its own rule.

**Unblocks.** The Neon Void host; SCENE-SCALE.md's columnar model has a consumer for the first time.

**Risk → fallback.** Persistent ranges and the in-place patch depend on per-instance bytes being stable across frames, which P2's layout decides and T1's idempotence assertion is the only guard on. If snapping or a gradient parameter turns out to depend on something that changes every frame, ranges thrash and the phase delivers nothing. Fallback: keep dirty-range upload for the subtrees that are provably stable (`TileGroup`, text runs) and re-record the rest, which is Makepad's granularity and still far better than today. The assertion that catches it early is in P1, not here.

### P6 — Modules and hardening

**Goal.** Everything that is optional, measured by what it costs; and the paths that make a failure survivable.

**Par.** The remaining taken items across all four references, each behind a compile-time switch, so a game build pays for none of them (guardrail 6).

**Lands.** Each item is independently shippable and carries its own wasm measurement.

- **Shaper module** (candidate `kb_text_shape`): GSUB features, ligatures, complex scripts, shaping breaks as an input. The largest wasm item; measured alone.
  **Bridge built 2026-10-07** (`src/void2d/shaper.{h,c,ms}`, test `src/test/shaperBridgeCheck.ms`;
  layout calls it since 2026-10-08, below). `kb_text_shape` v2.28e is fetched by `setup.sh` into `deps/kb` at
  the pinned commit (zlib, one 1,840,545 B header; `deps/` is not tracked, like sokol and stb).
  **NEW MECHANISM A, the first compile-time module: proven.** `shaper.ms` has `when (voidShaper)`
  with the real bridge and an `else` stub that stops by name (`tests/aborts/shaperOff.ms`). The
  `import ... from "./shaper.h"` and its companion `shaper.c` sit inside the `when`: a probe built
  with and without `-d:voidShaper` on msc 0.3.2 gave an executable with no `kbts_` string and no
  `shaper.c` object in the build cache when off (0 and 0), and both when on. The C side is one
  file that holds the implementation (`KB_TEXT_SHAPE_STATIC`), takes the face bytes from
  `glyph.c` (`void2dGlyphFaceData`), keeps one parsed font and one shape context per face
  (a synthetic face shares its base's bytes, so it shares both), and hands glyphs back through
  `void2dShapeGlyph` as nine ints (id, advance and offset in font units, the pushed codepoint's
  index, codepoint, run direction, run number), copied during `void2dShapeEnd` because kb reuses
  its run memory. The index returned is the caller's own: the context API always returns a
  codepoint index in `UserIdOrCodepointIndex`, so the bridge pushes a user id per codepoint and
  maps it back through `kbts_ShapeGetShapeCodepoint`. A pass needs no `kbts_ShapePopFont`: it is
  broken upstream (`kb_text_shape.h:25529` takes `&Context->FontBlockSentinel.Prev` where every
  other use takes the pointer, and ubsan stops on the first pop), so a context never changes its
  font. kb states "NO SECURITY GUARANTEE, DO NOT use it on untrusted font files": the module is
  for host-supplied fonts, the trust stb_truetype already gets, and a build that loads
  user-uploaded fonts is the case to watch.

  **The full oracle, 2026-10-07** (`tests/oracle/shape.rows`, 75 rows, `docs/TESTING.md` "T3"):
  against HarfBuzz 14.5.0 the bridge agrees on every field in 55 rows and on glyph count, ids,
  advances, offsets and run direction in 72. The one real difference is `o` U+0302 U+0323 in
  Inter (HarfBuzz composes, kb keeps a base and a placed mark). Three rows added after review differ by design, not by defect: an explicit `ltr` on Arabic and
  Latin mixed with Arabic differ because kb treats the direction as the paragraph's and runs BiDi
  where HarfBuzz forces one run, and a ZWJ with no glyph takes its own cluster in kb and its
  neighbour's in HarfBuzz. The other 16 are the cluster
  convention: kb returns each glyph's own codepoint index, HarfBuzz gives a mark or a reordered
  vowel its base's cluster, so layout that groups a glyph with its base derives the grouping from
  void2d's own graphemes (`assignFaces`) rather than from kb's index. Arabic comes back in visual
  order with the run marked right to left, as HarfBuzz does. A variable face (Noto Sans Thai, `fvar`
  kept) shapes at its default instance in kb as in HarfBuzz and stb_truetype, which the Thai rows
  measure. kb reads some `HVAR` tables through unaligned `u16` loads, which clang's alignment
  sanitizer, on in `msc`'s debug builds, stops on; `shaper.c` turns that one check off around the
  header (`#pragma clang attribute push`, no other file affected), the loads being legal on every
  target void builds for.

  **Layout integration built 2026-10-08, behind `-d:voidShaper`** (`textLayout.ms`
  `shapeText`; tests `src/test/shapedLayoutCheck.ms`). The shaper is told what `assignFaces`
  decided: consecutive non-control codepoints with one face, one scale and one `FontId` go to kb
  as one pass (kb's own fallback and segmentation are unused); a control character or a face kb
  refuses (`shaperTryBegin`) keeps the cmap-and-kern path. A run boundary or a shaping break
  between two codepoints of a pass is a `kbts_ShapeManualBreak`, so no substitution reaches over
  it and a colour change never makes a two-tone ligature. A pass whose run kb reports right to
  left stops by name (`right-to-left text at UTF-16 index N needs BiDi`); BiDi is a separate
  item. Features are the font's `features` list, any four-character tag (`BadFeatureTag`
  refuses the rest); kb takes the *earliest* pushed value of a tag (measured on the fixture:
  `liga 0` then `liga 1` gives two glyphs, `liga 1` then `liga 0` one), so the author's list is
  pushed first, and when `letterSpacing != 0` the optional ligatures `liga clig dlig hlig calt`
  are pushed off after it, which the author can override. That letter-spacing rule is CSS Text 3's
  and no reference in `docs/` states it (CSS read from memory, not re-read).

  **The slot model survives the shaper; three additions.** `LaidGlyph` stays one slot per
  codepoint, so wrap, hit-testing, selection, `splitAt` and `forceCells` read the slots they read
  before. A pass's glyphs are cut into shaping clusters where every earlier source index is below
  every later one; a cluster of `m` codepoints and `n` glyphs fills its slots as follows. `n == 1`
  over several graphemes (a ligature, Inter's `->`): the first slot holds the glyph, the rest are
  `NO_GLYPH`, and the glyph's advance is divided evenly among the graphemes (Makepad's rule per
  MAKEPAD.md:68, `layouter.rs:1150-1367`, not read upstream), which makes `xForIndex`, `indexAt`
  and the selection rows exact at grapheme boundaries with no cluster-aware code. Otherwise glyph
  `j` goes to slot `j` (a reordered Indic cluster included) and a slot past the last glyph is
  `NO_GLYPH` with no advance. **NEW MECHANISM D, the extra slot:** when `n > m` (`ccmp`
  decomposition, a split vowel; the fixture's `eacute` is `e` and `acutecomb`) the surplus glyphs
  get slots after the cluster's last codepoint that repeat its value, index and bytes, so
  `values`, `breaks` and `unitsTo` stay aligned and a line's end is still its last codepoint's.
  The spec said to refuse the font feature by name unless the fixture proved the slot needed; it
  does, and a refusal would stop an app on `é` in any font that decomposes it. **NEW MECHANISM B,
  confirmed:** `LaidGlyph.offsetX` and `offsetY` carry the GPOS offset in layout units, y down;
  `placeLabel` adds them to the pen before the quarter-pixel variant and the baseline snap
  (pixel-exact), and to the SDF quad (`sdfPlacedGlyph`), and `render.ms` needs no change because
  `PlacedGlyph` already carries the final x and y. A zero offset adds `0.0`, so every flagless
  placement is the same float. **NEW RULE C, built:** `LaidGlyph.shapeStart` is false for every
  slot inside a cluster; `wrapText` clears the UAX #14 opportunity before such a slot (Inter's
  `->` is one glyph and UAX #14 offers a break inside it), `splitAt` moves a cut inside a cluster
  back to the cluster's start (GPUI's `split_at` does not re-shape, GPUI.md:49), and
  truncation keeps a ligature whole. **E, a runtime switch:** `setTextShaping(false)` lays text
  out by the cmap path in a module build, so a test can compare the two paths in one binary;
  `setTextShaping(true)` without the module stops by name, as `setSdfRegime` does.

  Where the shaper's layout differs from the cmap path, on purpose: a pair kern lands in the
  *previous* glyph's advance (kb, HarfBuzz) and not in the next glyph's x, so a slot's advance
  differs and every x agrees; kerning crosses a default-ignorable codepoint as HarfBuzz's does
  (`A` ZWJ `V` kerns), where the cmap path breaks the pair; the joiner keeps a slot with
  `NO_GLYPH` and no advance, kb's zero-width space glyph is dropped; synthetic bold adds
  `emboldenUnits` to every shaped advance that is not zero (`void2dGlyphEmbolden`), so a ligature
  of two codepoints is emboldened once where the cmap path emboldens two glyphs. Measured, 65
  of the 75 oracle rows (the left-to-right rows kb and HarfBuzz agree on, Devanagari, Thai and
  Khmer included) are laid out at the layout level with the same glyph ids, pen positions and
  mark offsets, 1,635 values (`shapedLayoutCheck.ms`); flagless layout is unchanged, 348 / 330 /
  323 / 346 tests in `textLayoutCheck`, `labelTextCheck`, `snapCheck`, `fontCheck`, and the
  allocation script finds no copy or fresh array on the frame, rebuild and measure paths.
  Goldens with the module on (2026-10-08, BUILD `99a851d7`): the 78 rows that need no module
  stayed byte-identical flagless; with the flag four rows moved, `text/code13Dpi100/125/150` and
  `text/filteredDpi125`, each in the one `=` of `let x: i32 = 42`: Inter's default `calt` puts
  its contextual `=` (glyph 1520 to 1533) between spaces, with the same advance; the shaped line
  is 165.604 px wide as before, no glyph moved, so line breaks and Neon's measured widths for
  this line do not change. A string with a ligature or a kerning pair stb's `kern` reader did
  not carry does change width under the module. New row `text/ligature`: `-> != == => www`
  ligated, then with `calt 0`, then split by colour runs so no ligature crosses a colour change.
- **SDF text** for the transformed regime: one ~32 px/em distance field per glyph, derivative-scaled ramp, luma bias (MAKEPAD.md:112) — so zoom and animation cost nothing, and void3d gets world-space text through the same glyph layer.
  **Built 2026-10-07, behind `-d:voidSdfText`, first four slices** (field, generator, atlas,
  placement; the shader ramp and draw path followed, see "Shader and draw path" below; captures
  and void3d are not built).
  `textSdf.ms` is the T0 reference: field byte `191 - 31.875 * outward texels` (edge at 191/255,
  radius 8, pad 4, 32 px/em, as `stbtt_GetGlyphSDF` takes them and Makepad's
  `layouter.rs:249-255` encodes them) and Makepad's linear ramp
  (`draw_text.rs:620-641`) without its luma bias; weight stays the coverage layer's
  `correctCoverage`. `glyph.c` `void2dGlyphSdfRasterize` is `stbtt_GetGlyphSDF`'s loop
  (`stb_truetype.h:4575`) run over `glyphShape`'s vertices so synthetic bold and italic faces
  are seen; it is byte-identical to `stbtt_GetGlyphSDF` on 94 ASCII glyphs of Inter and 40 CJK
  glyphs of the Noto subset (`src/test/glyphSdfCheck.ms`), and a cubic (CFF) outline is refused
  by name (`AtlasError.SdfCubicOutline`) because stb's loop has no cubic case; `placeLabel` then
  draws that glyph from the coverage atlas at the matrix's device size and re-places the label as
  the matrix changes (`coverageInSdf`), the rest of the label staying on the field. A failed
  rasterization returns a code that `acquireSdf` maps to its own `AtlasError`
  (`SdfBadHandle`, `SdfWrongPageKind`, `SdfOutsidePage`, `SdfBoxMismatch`, `SdfNoMemory`), so no
  tile is recorded for it. SDF pages share `maxPages` with coverage pages and have no reserve:
  coverage pages filling the budget make `acquireSdf` answer `Full`. The atlas keeps
  SDF tiles on their own R8 page kind under key `(face, glyph, kind)`, no size and no variant:
  `acquireSdf`, 64 acquisitions are one tile and one generation, and SDF and coverage pages
  reclaim apart. `placeLabel` takes a third regime, `TextRegime.Sdf`, whose placement is the
  tile box in local units at `size / 32`, so `placementCurrent` ignores the matrix and the scale
  (a zero matrix is placed too, so a label that pops in from scale 0 is there when it grows; the
  DPI `scale` is not used, so the draw slice must draw SDF glyphs through the world matrix alone,
  as the Bitmap regime does):
  a 64-step zoom and a 64-step turn acquire nothing after the first frame.
  Measured, `msc test` (C, debug), 20 glyphs (16 Inter, 4 CJK), the field sampled bilinearly and
  ramped at device pixel centres against true coverage (exact-size `stbtt_MakeGlyphBitmapSubpixel`
  at no rotation, a 4x4 supersample of coverage at 4x size under rotation), over pixels where
  either is non-zero (`src/test/sdfOracleCheck.ms`):

  | zoom (16 px at 1) | mean abs error, rotations 0 / 17 / 45 / 90 | 99th percentile | ink ratio |
  |---|---|---|---|
  | 0.5 | 0.056 / 0.051 / 0.059 / 0.047 | 0.21 - 0.26 | 1.02 - 1.04 |
  | 1 | 0.053 / 0.036 / 0.043 / 0.035 | 0.17 - 0.27 | 0.96 - 0.98 |
  | 2 | 0.037 / 0.023 / 0.026 / 0.018 | 0.15 - 0.28 | 0.985 - 0.993 |
  | 4 | 0.027 / 0.022 / 0.023 / 0.020 | 0.31 - 0.33 | 0.986 - 0.988 |

  The error falls with zoom, the 99th percentile rises from about 0.27 to 0.33 (sharp corners
  rounded by about half a texel), and total ink stays within 4 percent of coverage. On that
  evidence no size ladder and no luma bias are built; the 4x corner softening is the number
  the T5 look beside Zed judges. Generation cost, `msc test` C debug build, not the optimised
  scratch figure the spec quotes: 0.84 ms per Latin glyph and 3.7 ms per CJK glyph
  (`void2dGlyphSdfGenerations` counts them for the budget; no budget is built).
  **Decisions to read before S5.** `setSdfRegime(true)` is the switch that makes `regimeOf` choose
  Sdf (translation and DPI only stay pixel-exact: `a == d == 1`, `b == c == 0`); it is off by
  default because `batcher.c` `glyphPageViewMode` still aborts by name on an SDF page, and the
  shader slice turns it on at setup. A zoom that passes exactly 1.0 is pixel-exact for that
  frame and re-places on the coverage atlas, as the rule says. The design scale of a
  `ScaleMode` is still in the world matrix, so under the Sdf regime a LetterBox, Zoom or Stretch
  scene's text is SDF; folding it into the DPI-like `scale` needs the scene view matrix split
  in `scene.ms` `paint` and is not done. NEW MECHANISM: the runtime regime switch
  (a rollout guard, removed when the shader lands) and `void2dGlyphSdfStbDiff`, a verification
  entry that stays in `glyph.c` under `VOID2D_SDF_TEXT` and is called from tests only; the
  generator itself is the P6 spec's own "SDF generation from void2d's own outline".
  **Shader and draw path, built 2026-10-07 (S5, S7); no pixel of it has been captured.**
  `shader2d.glsl` block `textSdf` is `textSdf.ms` `sdfCoverage` (edge 191/255, radius 8 texels,
  linear ramp, no luma bias) and `sdfTexelsPerPixel`, the mean of the lengths of `dFdx(uv)` and
  `dFdy(uv)` times the page's `textureSize`; gamma and contrast run after it through
  `applyContrastAndGamma`, one weight rule for both regimes. Both programs take the branch: the
  UI program's glyph mode when the instance's `params[0]` is `SDF_GLYPH_FLAG` (a lane no glyph
  used, so the 108 B stride is unchanged), the Vertex program's `fs` when `model1.z` is 2
  (`glyphPageViewMode` answers 2 for an SDF page view). The derivatives are taken at the top of
  `main`, before the clip `discard`. `emitLabel` sets a linear sampler for a whole Sdf label,
  whatever the node's `smooth`, because the field is meaningless sampled nearest, and
  `emitGlyph` flags a glyph by its page's kind, so a cubic-outline glyph drawn from the coverage
  atlas inside an SDF label keeps its coverage ramp. `setup2d` calls `setSdfRegime(true)` under
  `-d:voidSdfText`; the switch stays as the headless tests' way to compare the two regimes.
  NEW MECHANISM, each with its reference: derivative-scaled coverage in `shader2d.glsl`, which
  had no `dFdx` before (Makepad `draw_text.rs:620-641`; GPUI has none, its text is device-space);
  `GOLDEN_DEFINES` in `scripts/golden.sh`, which builds the golden runner with
  `-d:voidSdfText` so the SDF scenes capture the SDF regime. Goldens that move under that
  build: `prim/cardWithLabel` (its rotated label) and `demo/frame001`, `frame030`, `frame090`
  and `frame200`. Measured 2026-10-08 on BUILD `99a851d7`: the flagless golden run kept all 83
  existing rows byte-identical; with the flag only those five moved. `cardWithLabel` moved in
  its rotated label alone (452 px) and draws 2 (the SDF page is its own run). In the demo every
  label moved (4 701 to 5 595 px), not only "hello void2d": `present2d` fits the 980x720 scene
  into 800x600 with `cam.zoom` 0.816, a uniform zoom, which the regime rule sends to SDF; each
  frame draws 31 (30 before). No other scene has a label under a matrix beyond translation and
  DPI. New rows
  `text/sdfRotated`, `sdfZoom4`, `sdfScaleDown` and `sdfColorEffect`
  (`tests/golden/table.ms` `sdfLabelCases`, shared by the builders and by
  `tests/oracle/textSdfCheck.ms`); `text/sdfColorEffect` is judged by an invariant in
  `tests/golden/invariants.ms` (a never-matching colour key on the Vertex program equals the UI
  program's plain label within one level; measured worst 1). Oracle on the D3D11 capture
  (2026-10-08, BUILD `99a851d7`): mae 0.026-0.072, p99 at most 0.24, ink 0.980-0.995 against
  the bounds 0.075 / 0.40 / 0.94-1.07; the worst row is zoom 0.5. Control: dropping the
  derivative scale (`texels + 0.5`) fails it at rotated 13 px (mae 0.135) and zoom 0.5 (0.152).
  Owed: WebGL2 for the same rows (Yoga web link).

  program's plain label within one level). Owed: the D3D11 capture of the four rows and of the
  five that move, the oracle's first run (its bounds are the T0 table's, provisional until the
  capture is measured) and its control, WebGL2 for the same rows.
  **Budget rows and module weight, built 2026-10-08 (S8).** `tests/bench/benchTextSdf.ms` is
  the text bench with `-d:voidSdfText`: the 40-line code block is zoomed 0.5x to 4x, then turned
  through a full circle, then settles at 1x turned by 0.5 rad, because an untransformed block
  draws in the coverage regime and its steady frames would count nothing of the SDF cache; `baseline.json` `sdfBounds` holds `textSdf` to at
  most 1 SDF page of 1 MiB, at most 40 SDF generations over the sweeps (the code line has 40
  distinct glyphs, one generation each), 0 generations and 0 coverage rasterizations in the
  measured frames, and at most 40 coverage rasterizations over the sweeps (the zoom sweep of the
  coverage regime is 3 907). A run that draws no SDF glyph fails. The bounds are the claims, not
  measurements: the bench has not run (`tests/PENDING.md sdf:bench-bounds`). Weight, as objects
  from `sh scripts/wasmModuleDelta.sh` (clang 23.1.0 -O2, code plus data, before any link):
  `glyph.c` built with `-DVOID2D_SDF_TEXT` against without it is +8,016 B as wasm32 and +11,684 B
  as x86-64, recorded in `tests/bench/wasm.json`; the spec's scratch figure for stb's SDF code
  alone, linked with `emcc -Oz`, was +11.3 KB. The shader's one extra branch per backend text is
  not measured. With the module off no default-layer object names a `void2dGlyphSdf` symbol
  (the same script, with the module-on object as the control). The linked wasm per backend is
  owed: `sh scripts/experiment-modulesWeb.sh sdf` builds `tests/experiments/modulesWeb.ms`, which
  links no `node.ms` and so no Yoga, off and on (`tests/PENDING.md wasm:budget`); the Yoga web
  blocker (`~/metascript/.inbox/yoga/2026-10-03-yogah-has-no-web-branch-voids-wasm-cannot-link-sync.md`)
  still stops the whole-demo number. Not run here: `benchTextSdf.exe` (the native gate),
  `scripts/experiment-modulesWeb.sh` (emsdk), the Profiler variant of the bench.
- **Shaper wasm weight, built 2026-10-08 (slice 8).** `shaper.c` with the vendored
  `kb_text_shape.h` is one object of 518,961 B as wasm32 and 534,608 B as x86-64 (code plus data
  at -O2, `scripts/wasmModuleDelta.sh`, recorded as `shaper` in `tests/bench/wasm.json`); the
  spec's standalone proxy, linked with `wasm-ld --gc-sections` at -Os, was 481,916 B raw and
  75,820 B gzipped, against the demo's 1.5 MB, so the shaper is the largest module by far. Module
  off: no default-layer object names a `void2dShape` or `kbts_` symbol, with `shaper.c` as the
  control. Whether `kb_text_shape.h` lets its segmentation and line-break tables be compiled out
  (void has UAX #14 and #29) is not verified. The per-backend linked number is owed to
  `sh scripts/experiment-modulesWeb.sh shaper` on a box with emsdk 5.0.5; HarfBuzz, the fallback,
  was not measured.
- **Colour emoji**, a compile-time module, decided at P3's review. stb_truetype reads no colour table, so the module reads them itself: CBDT/CBLC and sbix bitmap strikes decoded by `stb_image`, already a void dependency (`src/assets/image.c`), and COLRv0 as layers of stb outlines, each tinted by its palette entry. The module builds the RGBA page kind P3 decided but did not build (P3 "Atlas page kinds"): the page format, its view and a colour draw path at a whole-pixel origin with no gamma correction, as GPUI does (GPUI.md:51). Bitmap strikes are pre-shrunk into 1.25× size buckets, so a zoom does not churn the atlas (MAKEPAD.md:114). Explicit-versus-fallback presentation comes with it (GHOSTTY.md:24), VS15/VS16 over P4's grapheme segmentation. Deferred faces, which let a family answer coverage before it loads, land in the default glyph layer rather than in the module, because the lazy CJK families need them too.
  **Built (`-d:voidColourEmoji`, CBDT/CBLC, sbix and COLR v0), 2026-10-08:** the RGBA page kind is real
  (`glyph.c` `void2dGlyphPageCreate` four bytes a texel, `void2dGlyphPageBlitRgba`,
  `void2dGlyphPageTexelRgba`; `batcher.c` `SG_PIXELFORMAT_RGBA8` and the byte-exact upload;
  `glyphAtlas.ms` `acquireBlank` and per-kind `residentBytes`), and a colour-only face loads.
  Draw path (`labelText.ms` `placeLabel`, `render.ms` `emitLabel`/`emitGlyph`): a glyph whose face
  has a colour strike or layers at the device size (`colourTileBox` reports Present) is a colour
  glyph, decided per glyph by the strike data, so a face with outlines and colour draws its
  outline-only glyphs as text. Its tile is keyed `(face, glyph, device size)` with variant 0 and
  placed at a whole device pixel: x is the nearest device pixel of the pen position plus the
  tile's bearing, y the snapped baseline plus the bearing, so a label moved by a fraction of a
  pixel reuses the tile. It records as an `InstanceMode.Image` instance with the premultiplied
  flag in `params1.y` (the shader already has the path; `shader2d.glsl` and every generated header
  are untouched) and a white fill that carries only the node's alpha, as GPUI's polychrome sprite
  takes opacity and no tint. On the vertex program (a label under a colour effect) the quad takes
  the premultiplied source flag, and `glyphPageViewMode` answers 0, an ordinary texture, for an
  RGBA page. A label with colour glyphs emits its text glyphs first and its colour tiles second,
  so text and emoji alternating in one label cost two runs instead of one per switch; z order
  changes only where an emoji tile overlaps a text glyph. NEW MECHANISM (flagged, needs approval):
  that two-pass order, which none of GPUI, Makepad and Ghostty has (they batch per primitive
  kind). A tile whose fill `colourRasterize` refuses goes back through `GlyphAtlas.discard` and
  the label reports `ColourRefused` by name. Measured headless (`src/test/labelTextColourCheck.ms`,
  334 tests): placement at DPI 1.0, 1.25 and 1.5, the instance fields, the vertex-program quad and
  the discard. Not measured: the golden `text/colourEmoji` capture (owed, D3D11, `tests/PENDING.md colour:capture-d3d11`), and the run
  count of an alternating label, which needs real views (a headless view is 0, so both pages
  record under one view).
  Transformed regime (`labelText.ms` `translationOnly`, `glyphAtlas.ms` `colourBucket`): a label
  whose matrix is more than a translation (a zoom, a rotation, a skew; DPI is not part of it) takes
  its colour tile from a size bucket instead of the exact size. A bucket is a rung of the integer
  ladder 1, 2, 3, 4, 5, 7, 9, 12, 15, 19, 24, 30, 38, 48, 60, 75, 94 and so on, each rung the
  ceiling of 1.25 times the one before, the first at or above the requested size, so a tile is
  never enlarged and is shrunk by at most 20 percent; the ladder is monotone and idempotent
  (T0 over sizes 0.37 to 1480). The tile is drawn through the affine with the smooth sampler,
  whenever the matrix is more than a translation, pixel exact or not, scaled by requested over
  bucket size (in device pixels when the regime is pixel exact, in local units otherwise); a
  headless test records the sampler of a zoomed label (scene smoothing off) and of an unscaled
  one. The sampler is per node: `emitNode` sets it again at the next node, so the label's
  switch does not leak. A bucket whose tile the page refuses (the tile is about 1.25 times its
  size wide and a page is 1023 texels) falls back to the exact size, which draws where it fits
  (T0 at zoom 46, font 16: bucket 888 refused, exact 736 drawn); a glyph whose exact tile is
  also refused is reported as before. A label with a colour glyph in the SDF regime re-places on a zoom, as a label
  with a cubic-outline glyph does, because the tile depends on the matrix where the SDF tile does
  not. NEW MECHANISM (flagged, needs approval): the 1.25x integer ladder. MAKEPAD.md:114 gives the
  ratio second hand ("emoji strikes pre-shrunk into 1.25x size buckets"); Makepad's own source
  was not read, so the rung rounding (integer, ceiling) is this tree's. Measured headless: a
  64-step sweep from 0.5x to 4x of a 16 px label of four emoji rasterizes at most 44 tiles (ten
  rungs and the identity size, four glyphs), stays in two colour pages, and a second sweep and a
  return to identity rasterize nothing. T4: `tests/bench/benchTextEmoji.ms`, the text scene with an
  emoji line every eighth line built with `-d:voidColourEmoji`, reports `colourPages`,
  `colourBytes`, `sweepColourRasterizations` and `colourRasterizationsSteady`; `check.ms` holds
  them to the `colourBounds` in `baseline.json` (2 pages, 8 MiB, 40 rasterizations, 0 steady) as
  bounds, not as measured values, because the bench has not been run (owed, `tests/PENDING.md colour:bench-bounds`). `glyphPages` and
  `glyphBytes` now count the coverage pages only, so they keep their meaning beside an RGBA page.
  Device loss and occlusion: `forgetContextResources` already marks every page dirty whatever its
  kind and the page mirror is four bytes a texel, so an RGBA page re-uploads whole with no new code;
  `src/test/glyphColourAtlasCheck.ms` pins the CPU half (after a loss an uploaded page takes an
  upload again, with the same mirror and size, and a `MarkDirty` that skipped RGBA pages fails
  it). The GPU half is two gate stages that build `tests/integration/deviceLoss.ms` and
  `sceneOcclusion.ms` with `-d:voidColourEmoji`, each with an emoji label beside the text one,
  and require the colour page to exist (owed, native: neither stage has run, `tests/PENDING.md colour:native-gate`).
  Module off (guardrail 6), measured 2026-10-08 with `sh scripts/wasmModuleDelta.sh` (clang 23.1.0,
  -O2, objects, code plus data bytes, before any link or garbage collection): with the module off
  no default-layer object (`glyph.c`, `grapheme.c`, `batcher.c`, `sfnt.c`) names a `void2dColour`
  symbol, while `glyph.c` built with the module does (the control), and the only `stb_image`
  implementations are the module's own PNG-only copy and `assets/image.c`. The default layer now
  against the commit before the colour item's first default-layer slice (`54bdd52`, the parent of
  `691586c`; every default-layer commit since is the colour item's) is +1,567 B as wasm32 objects
  and +1,909 B as x86-64 objects, +1,540 B and +27 B of the wasm32 figure in `glyph.c` and
  `batcher.c`. The gate also checks the module-off executable for a `void2dColour` symbol
  (owed, native). The module is `colourFace.c` 42,189 B as a wasm32 object (36,046 B
  code, 6,143 B data, the PNG decoder among them) and 43,625 B as an x86-64 object, plus 3,273 B
  (wasm32) of hooks in `glyph.c`; the spec's estimate for the module's C was 25 to 39 KB with the
  decoder shared. These are object sizes: the linked, garbage-collected wasm of the demo with each
  module off and on needs the web build, which cannot link Yoga (`tests/PENDING.md wasm:budget`),
  so no wasm budget is gated and the gate says so. `tests/bench/wasm.json` records the numbers, and
  the script fails on growth past ten percent. The gate also builds `mainSokol2d.ms` both ways
  and requires the colour build to be the larger executable (owed, native).
  Sequences: with `-d:voidShaper` a ZWJ sequence the face ligates draws as one colour glyph
  (`tests/fonts/colrLigature.ttf`, a COLR v0 face whose `ccmp` turns heart, ZWJ and grin into one
  glyph, `src/test/labelTextColourCheck.ms`; without the shaper the parts draw), and on Segoe UI
  Emoji, local only and not vendored, the shaper composes a skin-tone modifier and a keycap to one
  colour glyph, leaves the family sequence as three people because that font holds no ligature for
  it (fontTools), and draws a flag as two regional-indicator glyphs with no colour because Windows
  ships no flag art. Not verified: Noto Color Emoji's own `ccmp` (lookup types 4, 2, 6, 4, 5, 1),
  because the 10 MB face is not vendored and the subset dropped its layout features.
  Status at closure, from the commands in this section. Verified, headless: placement, instance
  fields, buckets and the zoom-sweep bound, the discard path and the page re-arm, the module-off
  symbols and the object bytes; each with single `msc test` files in the lane-b worktree, the whole
  suite (`src/test/index.ms`) not run there. Not verified, and why: the `text/colourEmoji` D3D11
  capture and the twice-run determinism at DPI 1.0, 1.25 and 1.5 (golden capture forbidden in that
  worktree); the draw count of an alternating label (a headless view is 0); the device-loss and
  occlusion stages and the `benchTextEmoji` rows (native runs); WebGL2 and WebGPU for the new scene
  and the linked wasm bytes (the web build cannot link Yoga, `tests/PENDING.md wasm:budget`); Metal
  and Android (no hardware); sbix on a real Apple face (proprietary, `tests/PENDING.md
  font-sbix-apple`); the halo check of Image mode on an integer-aligned quad, which the capture at
  DPI 1.0, 1.25 and 1.5 is to show.
  NEW MECHANISM (flagged, needs approval): `colourEmoji/colourFace.c`, an in-tree CBLC/CBDT
  parser (index formats 1 to 3, image formats 17, 18 and 19, PNG only), no reference has one
  because GPUI, Makepad and Ghostty all call FreeType or the OS (Ghostty
  `face/freetype.zig:333-352`, `:616-665`); the OpenType CBDT/CBLC text is not read, so the
  oracle is fontTools (`tests/oracle/colour.py`, 84 CBDT tiles). `cbdtFormats.ttf` holds one
  strike each of index 2 with image 19, index 3 with image 18, index 3 with image 17 and index 1
  with image 18, so every claimed format runs and a mutation of any of them fails a test. Every read is bounds-checked and a
  refusal names the field. Two divergences from the spec: the hook is a direct
  `#ifdef VOID2D_COLOUR_EMOJI` call from `glyph.c`, the idiom `VOID2D_SDF_TEXT` already uses,
  not a `void2dGlyphSetColourReader` pointer seam; and the colour-only `stbtt_fontinfo` is
  filled by hand with `numGlyphs = 0`, so every stb outline call answers empty, while the
  cmap is read by a checked format 4 and 12 lookup instead of stb's, which trusts offsets.
  The strike is the smallest `ppemY` at or above the size, else the largest; the PNG is
  decoded by a PNG-only static `stb_image` (24,695 B of wasm measured), premultiplied
  `(c * a + 127) / 255`, and resized by an own integer area average, because
  `stb_image_resize2` costs 112,928 B of wasm for one entry point (measured). sbix is read
  the same way (`png ` and `dupe`; any other graphic type refuses that strike by name and the
  glyph draws from another strike when one has it): the origin offset puts the bitmap's lower
  left at `(originOffsetX, originOffsetY)`, and a `dupe` takes the target glyph's record
  including its origin, chained at most 8 deep. The origin and `dupe` rules are the Apple
  sbix text as fontTools writes it and are not checked against FreeType, which was not read.
  COLR v0 with CPAL palette 0 draws as layers: `glyph.c` rasterizes each layer glyph with stb
  at the exact size (no subpixel shift), `colourFace.c` composites them premultiplied
  source-over in integer, with the tile box the union of the layer boxes. A COLR v1 face with
  no v0 records is refused when it loads (it stays a text face), and a glyph with a layer on
  palette index 0xFFFF, which needs the text colour, is refused by name. The oracle sizes put
  every layer edge on a pixel, because the Python reference cannot reproduce stb's partial
  coverage. `colrUnion.ttf` has one layer reaching past the first on each of the four sides, so
  each edge of the union box is pinned. Decisions at the review of slices 5 to 6c: a face with
  outlines and a damaged or unsupported colour table loads as a text face and names the table on
  stderr (the outlines are a complete face, and refusing the whole font would cost its text),
  while a colour-only face has nothing else and fails to load; a CBLC strike whose bit depth is
  not 32 is skipped by name and the face fails only when no strike is left; a size over 16,384 px
  or not finite, and a box over 4096 x 4096 texels, is refused by name for a bitmap strike as for
  a layer glyph; a bitmap strike is enlarged by pixel replication when the size is over its
  ppem, which the area average does at a scale over 1, and the largest strike is the one chosen
  there; a COLR v1 face that also holds v0 base records draws those v0 layers, as a v0-only
  renderer would; the cmap choice skips the variation-selector record (platform 0, encoding 5).
  The reason string and the box of `void2dGlyphColourBox` are static, one thread like
  `void2dGlyphBox`. A tile that `acquireBlank` recorded and whose fill was refused is given back
  with `GlyphAtlas.discard`, so the key is not cached with no pixels behind it. The truncation
  sweep is test code, `src/test/colourSweep.c`, and is not compiled into the module. Smoke, local only: `C:/Windows/Fonts/seguiemj.ttf` U+1F300 to U+1FAFF at 32 px
  gives 1,191 colour glyphs, 0 refused, 9,439 layers, 1,114 inked at the tile centre.
- Variable-font axes and stem darkening **only if** the T5 capture beside Zed asks for them. The hinting rasterizer is decided out (P3 "Resolved at P3 step 8"). Deferred by name below, with the condition that reopens it.
- **SVG → R8 mask → tinted sprite**, the icon path, with a single-header C rasterizer.
  **Rasterizer taken and measured 2026-10-07 (V0): nanosvg** (`memononen/nanosvg` at
  `239e102`, zlib, `nanosvg.h` 92,258 B + `nanosvgrast.h` 40,870 B, two headers). `setup.sh`
  fetches it into `deps/nanosvg` at that pin, as it does `kb`; `deps/` is not tracked, so the
  headers cannot carry a patch. Measured against resvg 0.48.1 (`resvg-py` 0.5.0), alpha channel
  only, 15 hand-written icons first (round-cap strokes, evenodd rings, a nested rotate and scale,
  dashes, a miter join, fill opacity), then the real sets. At nanosvg's defaults the mean absolute
  error at 24 px is 1.79 of 255 per icon, 6.19 at worst (a gear outline), and 111 pixels in all
  differ by more than 32. `NSVG__SUBSAMPLES` 15 and 17, the divisors of 255 above 5, do not help
  (1.88 and 1.92), so the vertical subsample count is not the error. The error is the flattening
  tolerance: `tessTol` 0.25 draws about 3% less ink on curved strokes (a circle of radius 8:
  195.7 against 201.06 pixels of coverage; the two round caps of a 4 wide stroke: 10.3 against
  12.6). Lowering it to 0.05 gives 1.39 and 46 pixels past 32 at 24 px, and 0.72 and 29 at 48 px
  (25 at 0.02, 0.01: no gain), so the module sets `tessTol` to 0.05 on the rasterizer it
  creates (the struct is visible because the implementation is in the same file). The worst
  single pixel left is a dashed outline (124 at 24 px): a dash edge placed a fraction of a pixel
  differently.
  **Module alone for the web (V0, re-measured with the real module in V1):** `emcc` 5.0.5
  `-Os`, `svgMask.c` with nanosvg in it: 64,507 B object, 100,023 B linked against 20,746 B for
  a function using only `malloc`, `memset`, `strtod`, `sqrtf` and `strcmp`, so the module adds
  79,277 B of wasm (39,842 B gzipped; `snprintf` for the refusal text is part of it). The full web
  build still cannot link (Yoga has no web branch), so this is the module-alone figure the spec
  allows.
  **Built 2026-10-07 (V1): `svgMask.{h,c,ms}`, test `src/test/svgMaskCheck.ms`, behind
  `-d:voidSvg`.** Same seam as the shaper: `svgMask.ms` has `when (voidSvg)` around the import of
  `svgMask.h` and its companion `.c`, and an `else` that stops by name
  (`tests/aborts/svgMaskOff.ms`). A build without the flag has no `linearGradient` and no
  `css selector` string in its executable (0 and 0; 1 and 1 with the flag), and
  `tests/aborts/svgMaskStaleHandle.ms` pins the stop on a freed handle and
  `tests/aborts/svgMaskReusedHandle.ms` on a freed handle whose slot a later parse took: a handle
  carries the slot in its low 16 bits and a generation in the high 15, bumped at every free, so
  it names one parse for ever (a slot whose generation runs out is retired; 65,535 slots).
  `svgMaskParse(string)` copies the source (nanosvg parses in place) and returns a handle with the size the author
  gave, or an `SvgMaskRefusal {error, what}`; `svgMaskRasterize(source, w, h)` returns the alpha
  plane of exactly w by h (1 to 8192 a side, GPUI's cap) with the image fitted whole and centred
  (the smaller of the two scales, so a wide icon in a square keeps its aspect);
  `svgMaskFree` releases the handle. `svgMaskParsed()` and `svgMaskReleased()` count the images
  nanosvg made and deleted, so a leak or a wrong free shows as `parsed != released + live`. The
  rasterizer and the slot table live for the process and are never freed; the statics (including
  the refusal text) are not thread safe, so one thread may use the module.
  **The allowlist scan** (nanosvg drops without a word what it does not know) refuses by name,
  before nanosvg runs: an element outside `svg g path rect circle ellipse line polyline polygon
  defs linearGradient radialGradient stop style title desc metadata` (`element <use>`), a second
  `<svg>`, an attribute or `style` declaration that is `clip-path clip mask filter marker*
  visibility vector-effect mix-blend-mode isolation shape-rendering transform-origin
  transform-box`, any `inherit`, a `fill`, `stroke` or `stop-color` that carries alpha or that
  nanosvg would read as grey (`rgba(`, `hsl(`, `transparent`, an 8 or 4 digit hex), an opacity
  in percent, any `opacity` on a `<g>` or in a `<style>` rule (nanosvg multiplies it into each
  shape, so overlapping shapes of one group composite twice where a browser composes the group
  once; on a single shape with both fill and stroke it has the same flaw and is not refused),
  a colour name nanosvg has no entry for (it would draw grey), a `fill` or `stroke` `url(#id)`
  that names no gradient in the document, CSS property names matched without case, a cap, join or fill rule outside nanosvg's
  vocabulary, and in a `<style>` element any selector that is not a list of `.class` names, or an `@` rule. Run over 9,016 icons (Lucide
  1.52.0: 2,130; Heroicons 2.2.0 24 px outline and solid: 648 and the 16 px solid: 316; Tabler
  3.49.0 outline and filled: 6,238) the scan (before the opacity, colour-name and
  `url(#id)` refusals, which were not rerun over those sets) refuses none, so the allowlist
  cost those sets nothing. `paint-order` is not refused: nanosvg honours it (`nanosvgrast.h:1405`).
  **Two things nanosvg draws wrongly that the module corrects, found by running those sets
  against resvg:** a stroked subpath with no length is dropped, though a browser draws the cap
  as a dot, and Lucide and Heroicons both draw their dots that way (`<line>` with equal ends,
  `h.01`, a closed loop `h.008v.008H8.25v-.008Z`): 13 of 2,130 Lucide icons and 22 of 324
  Heroicons outline icons had a pixel off by more than 128 of 255. After parsing, the module
  replaces every stroked subpath whose extent is at most 5% of its stroke width by a filled
  disk (round cap, or round join on a closed loop) or square (square cap) of the stroke's colour
  and opacity, in its own shape so the rest of the original shape is untouched. A butt cap there
  is left alone. A tiny path it cannot make faithful is refused by name: a gradient stroke, a
  dash array, a closed loop without round joins. After the correction, at 24 px against resvg, no
  Lucide or Heroicons icon is off by more than 128 (41 of 2,130 Lucide and 8 of 324 Heroicons
  outline have a pixel past 64), and 3 of 5,184 Tabler outline icons are (64 past 64; the
  skateboard wheel below is one); the median of the per-icon mean error is 1.59 (Lucide), 2.92
  (Heroicons outline), 1.64 (Heroicons solid), 1.69 (Tabler outline), 0.85 (Tabler filled). A dot comes out about 10% lighter than resvg's
  (2.82 against 3.25 pixels of coverage for a 2 wide dot). Known gaps: a lone `M x y z` is
  dropped by nanosvg before any path exists, so the module cannot see it; a disk of radius 0.5
  stroked 2 wide (a Tabler skateboard wheel) draws a hole resvg does not.
  **Oracle, 2026-10-07 (V2):** `tests/oracle/svg.rows` (38 rows over 29 icons written for it),
  `python tests/oracle/svg.py regen` (`resvg-py`) into `tests/oracle/svg.json`,
  `src/test/svgOracleCheck.ms`: 31 of 38 within a mean alpha error of 3.5 and a worst pixel of 70
  (of 255); the seven others are `svg:` rows in `tests/PENDING.md` by name (four refusals, group
  opacity, a gear, a dash edge). docs/TESTING.md "T3".
  **Built 2026-10-08 (V3 to V6): the icon path.** `scene.icon(id, w, h, color)` is a
  `DrawKind.Icon` node (the Underline and Selection kinds are its precedent) that draws a
  registered SVG as a tinted R8 mask, GPUI's `paint_svg` (`window.rs:4809-4866`): the icon is
  rasterized at twice the device pixels it covers, `2 * ceil(device)` per side
  (`svg_renderer.rs:81`, `SMOOTH_SVG_SCALE_FACTOR`), and the quad covers `ceil(device)` so the
  linear sampler averages 2x2 texels per pixel. `icon.ms` owns the registry
  (`registerIcon(source)` answers an `IconId` or the module's `SvgMaskRefusal`; ids are not
  reused and a registration is permanent, since nothing in a scene frees the parsed icon;
  a build without `-d:voidSvg` stops by name at the first call,
  `tests/aborts/iconOff.ms`) and each node's retained placement, which re-acquires its tile when
  the raster size changes and gives it back when the node leaves the tree.
  - **The Mask page kind is real.** `PageKind.Mask` is built under `VOID2D_SVG` (the
    `svgMaskSwitch.ms` import, as `textSdfSwitch.ms` does for Sdf), an R8 page with its own
    blit `void2dGlyphPageBlitMask` that stops by name on a page of another kind or a tile past
    the page edge, and `glyphPageViewMode` answers 1.0 for it: the same shader path as a
    coverage page, so the contrast and gamma of `textGamma.ms` apply, as GPUI's mono sprite
    applies text's (`gpui_wgpu/src/shaders.wgsl:1247-1258`). A mask tile's key is the icon id in
    the face field, the mask height in the glyph field and the width in the size field, so two
    sizes are two tiles (`maskKey`); the kind lane keeps a mask and a glyph with the same
    numbers apart. `GlyphAtlas.reserveMask(key, w, h)` takes the tile before anything is drawn,
    `fillMask(tile, alpha)` blits it and `discard` gives it back when the raster fails, so an
    atlas with no room costs no rasterization (`iconRasterizations()` counts them);
    `acquireMask(key, w, h, alpha)` is the three in one; `retainMask(key)` is the hit path.
  - **Regime.** A uniform scale or a translation draws pixel-exact: the quad sits on whole
    device pixels, centred in the box when the rounded-up size differs from the true one. Any
    other transform rasterizes at the geometric mean of its axes, as labels do, and draws the quad
    through the node's affine. Icons always sample with `Smooth.On` (a nearest sampler would
    drop the 2x supersample); `Smooth.Off` on an icon node is not honoured, and the sampler goes
    back to the scene's after each icon (the SDF Label leaves its linear sampler set, which
    only a scene with smoothing off can see). The quad covers `ceil(device)` pixels, so an icon
    of 24.2 px draws up to one device pixel larger than its box, centred in it. A mask larger than a
    page, or an atlas with no room, draws nothing, is counted in `iconRefusals()`, reported once
    per cause (`iconRefusalReports()`) and retried the next frame as a refused label is.
  - **Evidence.** T0 `src/test/iconCheck.ms` (11 tests: the registry, `maskSide`, a shared tile
    costing no second rasterization, two sizes as two tiles, the zero gutter, reclaim, the
    page-size refusal, key packing, the three atlas refusals), `src/test/iconOffCheck.ms` (the
    module off), `src/test/nodeCheck.ms` (4), T1 snapshot `icon` and five tile-bookkeeping tests in
    `tests/displayList/snapshot.ms`, aborts `iconUnregistered`, `iconNegativeSize` and `iconOff`;
    each new test was shown red by a local mutation (floor for ceil, no retain, a blit one texel
    wide, a nearest sampler, a skipped release, swapped width and height). T2 `icon/tinted` and
    `icon/tintedDpi150` are in the table with counters from the recorded stream (3 draws, no
    target) and **no PNG yet: the capture is owed**, as is the device-loss run with an icon in it
    (`tests/integration/deviceLoss.ms`, now built with `-d:voidSvg` by the gate).
  - **Weight, native, measured 2026-10-08** (`msc build src/examples/mainSokol2d.ms --release`,
    D3D11 exe, bytes): 1,515,520 before the icon path; 1,525,248 after it without the flag
    (+9,728, the node kind and the Mask page kind); 1,612,800 with `-d:voidSvg` (+87,552 more,
    nanosvg and the allowlist). Wasm is not measurable here (the full web build cannot link
    Yoga, `~/metascript/.inbox/yoga/2026-10-03-yogah-has-no-web-branch-voids-wasm-cannot-link-sync.md`);
    the module-alone figure stays the V0 `emcc -Os -c` one above (64,507 B object). No shared
    wasm budget gate exists in this tree, so none was added.
  - **Spec corrections.** The spec asked a colour effect on an Icon to stop by name "like the
    Label case"; a Label stops on no effect, the effect row applies to its Glyph instances, and
    an Icon takes it the same way (`withEffect` runs after the Glyph coverage). The spec's
    `registerIcon(bytes)` is a source string, and its `IconError` is `SvgMaskError`. The spec's
    `displayList.ms` edit is not needed: the sampler is already a run key.
  - **Mechanisms.** No NEW MECHANISM beyond those flagged in the spec and decided in the
    review: the mask kind reuses the page-kind lane and the `Sdf` precedent of a kind-specific
    key; `DrawKind.Icon` reuses the node-kind table and `emitGlyph`; the shader is untouched.
    Reference: GPUI `AtlasKey` (`platform.rs:1382-1386`) for the key kind.
- Procedural sprite glyphs — box drawing, blocks, braille, powerline — for a terminal widget.
  **Integer geometry built 2026-10-08.** `spriteGlyph.c` ports Ghostty's `block.zig`, `braille.zig`
  and the straight, dashed and double lines of `box.zig` (`sprite/Face.zig` renders on a canvas
  padded by `W/4` and `H/4`, `draw/common.zig` `Fraction.min/max` rounds the two edges of a
  fraction complementarily). It draws integer rectangles straight into an 8-bit canvas, so it
  needs no rasterizer and no anti-aliasing. `src/test/spriteOracleCheck.ms` compares the result
  with Ghostty's 36 reference PNGs (`tests/oracle/ghostty/`, 78,166 bytes, MIT): 1636 of 1636
  cells equal. The sprite table is a sorted range table with a dense id per codepoint
  (`void2dSpriteTableFault` is the compile-time overlap check of `Face.zig` as a test).
  **Sprite face built 2026-10-08.** Sprites are in the default layer, not a module: Ghostty's
  `CodepointResolver` asks the sprite face before every font, a terminal needs them in every
  build, and the cost is one C file (no vendored code). `void2dGlyphFaceSprite(base)` makes a
  face that copies its base's tables for metrics only (never its embolden, skew or colour tables)
  and answers `void2dGlyphIndex` from the range table, `void2dGlyphAdvance` with the widest ASCII
  advance of the base, `void2dGlyphKern` with 0, `void2dGlyphFaceData` with NULL (so the shaper
  skips it) and `void2dGlyphBox`/`void2dGlyphRasterize` from the drawn cell, trimmed to its ink.
  The tile is an ordinary Coverage tile keyed `(sprite face, dense id, size, variant 0)`; the
  Mask page kind stays the SVG icon's. The cell is Ghostty's `Metrics.calc` over the base face at
  the device size (`glyph.c` `spriteCell`): width the rounded widest ASCII advance, height the
  rounded line height, the baseline centred in it, line thickness the underline thickness
  rounded up, at least 1. `font.ms` `codepointFaceFor` returns the sprite face before the
  coverage probe, so a sprite codepoint costs no probe and no fallback load, in any presentation
  mode. `placeLabel` places a sprite on `snapBaseline` of its pen x with variant 0 instead of
  `quantizeX`, because a quarter-pixel shift would put a seam in a join. In the SDF regime a
  sprite reports "no outline" like a cubic glyph and takes the coverage fallback.
  Not done: `getBounds` measures a sprite's ink at the local font size, where the tile is
  drawn at the device size, so bounds can differ from the drawn ink by a pixel; and a host
  that wants seamless rows sets `forceWidth` to the cell width over the device scale and
  `lineSpacing` so the row pitch is the cell height (`spriteCellFor`, internal until Terminator
  asks for a public cell-metrics API, void-manager decision 7).
  **Anti-aliased sprites built 2026-10-08.** Diagonals U+2571-2573, arcs U+256D-2570, powerline
  U+E0B0-E0BF, E0D2 and E0D4 and the corner triangles U+25E2-25E5, 25F8-25FA and 25FF are drawn
  by `spriteGlyph.c` from `box.zig`, `powerline.zig` and `geometric_shapes.zig`; sextants
  U+1FB00-1FB3B, octants U+1CD00-1CDE5 (the table generated from Ghostty's `octants.txt`) and
  the block, shade and checkerboard sprites U+1FB70-1FB97 are integer rectangles like the rest
  of S3. The smooth mosaics, edge triangles and the box branch glyphs of Ghostty
  (`1FB3C-1FB6F`, `1FB98` on, `F5D0-F60D`) are not ported; a codepoint of theirs keeps
  coming from the font. 771 sprites in all, 738 byte-equal to Ghostty's reference at four cell
  sizes, 33 within the budget `tests/PENDING.md` lists per family.
  **NEW MECHANISM, local to `spriteGlyph.c`.** The spec asked for a flatten-offset stroker
  feeding `stbtt_Rasterize`. `stbtt_Rasterize` is `STBTT_STATIC` in `glyph.c`'s translation unit
  and takes int16 vertices, so a second copy would put the font rasterizer into the sprite
  object; the sprites carry their own exact-area accumulator instead (the signed-area scheme of
  font-rs, about 60 lines, the same coverage maths as stb's), and a stroker that offsets a
  flattened polyline by half the width on each side with miter joins up to ratio 10 (z2d's
  default) and butt caps. A closed outline is the polygon minus its inset, which is how
  `innerStrokePath` reads. Neither reaches the font path or the page code. What it can regress:
  a polyline that doubles back on itself would cancel its own area, so `drawArc` stops the path
  where Ghostty's overshooting `lineTo` would reverse it (measured: the reference ink ends at
  the same half pixel). The reference antialiases with z2d at 4 by 4 samples (its values are
  multiples of 16 less one), so the graded sprites differ by up to 33 of 255 and are judged
  against a budget, not byte-equal.
  **Gamma on masks.** Glyph mode applies `applyContrastAndGamma` to every coverage, and it maps
  0 to 0 and 1 to 1 exactly (the shader's `a = c (k+1) / (c k + 1)` and the `a (1-a)` correction
  vanish at both ends; `src/test/textGammaCheck.ms` "empty and full coverage stay empty and full" pins the T0 copy), so full blocks, box lines
  and braille dots draw the fill colour exactly and join without a seam. Half tones are not
  exact: the three shade blocks (0x40, 0x80, 0xC0) and every anti-aliased edge are shifted like
  text edges, by the contrast of the fill colour. A per-instance "no correction" flag would
  touch the 108-byte UI layout and is not added; the golden `text/spriteGlyphs` shows the
  shades.
  **Seam proof and golden, 2026-10-08.** `labelTextCheck.ms` places three rows of seven U+2588
  through a Label with `forceWidth` the cell width over the scale and a line spacing that makes
  the pitch the cell height, at DPI 1.0, 1.25 and 1.5: every tile is the whole cell, its right
  edge is its neighbour's left edge and its bottom edge the next row's top. It was red first:
  GPUI's `force_width` leaves a base within a pixel of its cell where the shaper put it, and a
  sprite advance (the base face's widest ASCII advance, unrounded) drifts from the integer cell,
  so cells 1 to 4 of a row rounded to the wrong pixel and opened a seam. `forceCells` now puts a
  sprite on the grid whatever the distance, which is the only change to the shared layout code.
  Three golden rows are built, `text/spriteGlyphsDpi100`, `text/spriteGlyphs` (DPI 1.25) and
  `text/spriteGlyphsDpi150`, each ten labels of a terminal grid; headless, the three place 204
  glyphs with none refused. Predicted counters, one draw and no target each, are in
  `tests/golden/table.ms` and are confirmed or corrected by the first capture.
  **Owed, not run:** `sh scripts/golden.sh --update text/spriteGlyphs` (the PNGs, three rows),
  then `sh scripts/golden.sh` for the counters; a look at the half-tone shades and edges, which
  the contrast and gamma of Glyph mode move; the web column of the three rows.
- Animated image frames keyed by frame index.
- `Graphics` antialiasing by a vertex-shader fringe: the edge normal per fringe vertex, extruded by `1px / scale`. No MSAA intermediate, no baked fringe (guardrail 4). `sample_count` exposed as a knob on the mobile bridges instead of hard-coded 1 (guardrail 5) — the one place this phase touches void3d, since the swapchain sample count must match its pipelines.
  **Built 2026-10-07.** The fringe takes Makepad's GPU-expand encoding
  (`libs/svg/src/tessellate.rs` `emit_fill_fringe`, `:1003-1060`): every contour vertex is stored
  on the edge with the outward normals of the two edges that meet there, and the fringe is a
  zero-area quad per edge until it is drawn. Makepad never wires the expansion (`fill_gpu` has no
  caller and its vertex shader moves nothing; `svg/render.rs:610` bakes the fringe instead because
  coincident fringe vertices broke Metal rasterization). void2d expands where it already
  transforms a mesh, `draw.ms` `drawMeshRange`: each edge line moves by half a device pixel through
  the world affine (`t / |A^-T n|`) and the render scale, so the body ends half a pixel inside the
  edge and coverage ramps to zero half a pixel outside it under any scale, shear, rotation or DPI,
  and nothing coincident reaches the GPU. The mesh keeps an edge column beside its vertices
  (`EDGE_FLOATS`): two normals, the shift, a stroke's half-width and the uv gradient, so a
  textured, gradient or pattern fill keeps its uv on the moved vertex. A stroke narrower than a
  device pixel collapses its body to the centre line and scales coverage by `2w / (w + 0.5)`
  instead of inverting. A full-turn ring is two loops, the hole wound against the rim; a
  full-turn pie is a circle; a pie of no angle draws nothing. `setAntialias(false)` builds the
  following fills without a fringe. A fringed Graphics' render and filter bounds grow by the
  half pixel in local units, which is why the filter goldens moved as a whole.
  Measured, D3D11, msc v0.3.2 BUILD `244ef48c`: `prim/aaGraphics` (the `prim/aaRotatedBox`
  geometry as a Graphics) judged by `tests/oracle/captureCheck.ms`: edges 0.0467 of 0.06, miter
  corners 0.2459 of 0.26; antialias off reads 0.5 on both. A sharp corner takes the nearer edge's
  ramp, as in NanoVG, Makepad and Skia's `GrAAConvexTessellator::createOuterRing`; only
  exact-area rasterizers (Vello, Pathfinder, Rive) do better. Decided 2026-10-07: accepted as
  Skia does; a convex-corner patch would be a new mechanism and is not built. 22 goldens regenerated; axis-aligned fills on whole pixels, `prim/gradientLinear`
  and `prim/ditherBand`, stayed byte-identical. A 1 px stroke centred on a pixel boundary is now
  two half-covered pixels (true area, as GPUI's paths and Canvas draw it), a 0.5 px stroke shows
  at its coverage instead of vanishing, and `fillSlashRect` stripes flip a few pixels where a
  stripe edge falls exactly on a pixel centre (the pattern itself has no antialiasing).
  CPU cost, release, 128 circles of radius 30 rotated every frame at DPI 1.5, recording only:
  0.12 ms and 8 064 vertices with antialias off, 0.64 ms and 25 728 vertices with it on. A
  static or scrolled Graphics replays and pays nothing. That does not justify moving the mesh
  transform to the vertex shader yet.
  `sample_count`: `setViewSampleCount(n)` (`src/sokol/gpu.ms`, `voidViewsSetSampleCount`) sets
  the views driver's count once, before the first view, for every view and for the environment
  the pipelines are made against; 1, 2, 4 and 8 are taken, anything else or a late call stops by
  name. D3D11 renders into a multisampled texture and resolves into the swapchain buffer; Android
  asks EGL for a config with that many samples; iOS gives sokol a memoryless (simulator: private)
  multisampled texture per view, remade on resize. `tests/integration/viewSamples.ms` draws the
  forward preset and void2d in one screen pass into a host view, debug build with sokol's
  validation: 0 / 80 / 160 / 160 partly covered pixels on a 45-degree edge at 1 / 2 / 4 / 8
  samples. The Android bridge compiles under NDK 28 and links into gate3d's arm64 `libVoidAndroid.so`;
  the iOS bridge was not built here, and neither ran on a device. The macOS embed bridge (`bridgeEmbed.m`) still uses 1.
- Device loss: drop every GPU object, re-arm every dirty flag, redraw, with a **fault-injection switch** (MAKEPAD.md:104) — which is also how the path is tested. void3d already has the Android form of this (`voidEmbedLoseContext`); this generalises it and covers the atlas and the instance buffer.
  **Built 2026-10-05.** The switch is `loseContext()` (`src/gpu/door.ms`): the Windows window and
  views hosts and the Android bridge drop every sokol object at the start of the next frame
  (`sg_shutdown`, `sg_setup` on the same device) and count a new `contextGeneration()`, so sokol
  hands old ids to new objects. It proves the owners and the re-arm, not platform recovery: a real
  D3D11 device removal, WebGL `webglcontextlost` and WebGPU device loss are not detected, and the
  Apple and web bridges stop by name. Android's real EGL loss was already wired.
  Textures follow Heaps (`h3d/mat/Texture.hx:56,166-168,232-235`), the person's choice A:
  `src/gpu/texture.ms` `Texture` holds image, view and generation; `asView` calls its `realloc`
  hook when the generation is stale, `Texture.fromPixels(..., keep)` installs one that re-uploads
  the kept RGBA8 copy, `isLost` lets a holder upload before binding, and a lost texture without a
  hook, or an adopted one (`Texture.adopt`, the caller's handles, never destroyed or remade),
  stops by name. A texture's image is immutable: `upload` on one that holds a live image stops,
  since a retained list may still name its view. `Tile` holds a
  `TextureSource` (a `Texture`, a `RenderTarget`, or white) instead of a raw view id, so a tile
  resolves its view when drawn: `tile(texture, w, h)`, `targetTile(target, w, h)`, `whiteTile(w, h)`.
  `Texture.detach()` is the inverse of `adopt`: the caller takes the handles, nothing is
  destroyed, and the texture is closed; void3d uses it to defer a freed texture's destruction.
  `setTiles`/`appendTiles` take `TileCell[]` as `anim` takes `Tile[]`: a cell now carries a
  reference, and a read-only view's element cannot be stored (PARALOCK E24).
  void2d re-arms on a generation change: `batcher.c` forgets its buffers, samplers, white view,
  glyph page images, retained list buffers and pipelines without destroying them and makes the
  static ones again; every glyph page re-uploads from its CPU copy; a scene painted in an older
  generation repaints fully (`paintedGeneration`). Pipelines and filter targets already adopted.
  Measured on BUILD `5c4246fb`, D3D11: `tests/integration/deviceLoss.ms` (rect, kept-pixel sprite,
  hook sprite, label, blurred rect; four decoy textures claim the recycled ids after the loss)
  was red without the re-arm, 3675 pixels differing on the frame after the loss, and is green
  with it: two losses, the frame after each byte-identical to the one before, the hook called
  once per loss. `tests/integration/deviceLoss3d.ms` drives void3d's `texturedFrame` through a
  real switch instead of its simulated one: forward, pixel-art and outlined presets keep their
  texel checks. void3d adopts the owner in its own row: each slot's `GpuTexture.image/view` and
  `TextureData.pixels` become one `Texture`, `uploadTexture` becomes `Texture.fromPixels`,
  `rebuildTextures` keeps only the sampler re-arm, and `gpu3dMakeImage` gives way to the door's
  `makeImage`.
- Warm-up of pipelines, device and the font database off the first-frame path; release of GPU resources when occluded; a synchronous draw during live resize; discard of a late frame at the wrong size.
  **Built and measured 2026-10-07.** Occlusion follows Ghostty's
  `renderer/generic.zig` `setVisible` / `releaseGpuResources` (`:1153-1192`): release
  surface-owned buffers and targets, retain caller images, rebuild on the next paint.
  `src/void2d/scene.ms` `Scene2D.releaseGpu` reuses the existing list/target disposal;
  shared glyph pages and pipelines stay resident rather than being released per scene.
  On D3D11, `tests/integration/sceneOcclusion.ms` passed eight release/repaint cycles:
  list buffers dropped, no filter targets remained, the texture and glyph pages survived,
  and every repaint was byte-identical. Repeated release was safe; release between
  prepare/drawScreen and release after close each stopped by name.
  `tests/integration/twoViews.ms` passed synchronous `viewResize` → `viewFrame` with
  captured pixels at 360×240, DPI 1.25. The standalone Win32 sokol_app host intentionally
  keeps stretched frames during modal resize: its `WM_TIMER` resize code is disabled
  (`deps/sokol/sokol_app.h:10112-10132`, upstream's memory-growth warning); no vendored
  patch was made, and an interactive modal-resize run was not performed here.
  Ghostty's `renderer/metal/IOSurfaceLayer.zig` `setSurfaceCallback` (`:105-119`)
  discards an asynchronously completed frame whose size is obsolete. Void has no async
  completion queue: `DrawContext2D.drawScreen` stops on a mismatched prepared size
  instead of silently losing the frame. `preparedScenes.ms`, `VOID_PREPARED_MISUSE=size`,
  stopped with `drawScreen 120x60 does not match prepared 100x60 at DPI 1`.

  **Warm-up measurements are contended, not a baseline.** Source tree
  `8c4df212c54e61300ddbdcd098221e5f752a24d5`, msc v0.3.2 binary/support BUILD
  `244ef48c`, release D3D11, Ryzen 9 9950X, 1280×720, sample count 1, high DPI off.
  The native run overlapped nim-audit and void3d jobs; these are CPU wall-clock call
  durations, not GPU completion times or an isolated performance comparison.
  `MSC_NO_GLOBAL_CACHE=1 sh scripts/gate.sh` reported first paint UI 52.98 / text 2.63 /
  scroll 7.20 ms after pipeline preparation. A throwaway copy of `bench2d.ms`, using
  the same three scenes, also called `resolveFont` for Inter, weight 400, normal style,
  no features/fallbacks/size adjustment, after `preparePipelines([BlendMode.Alpha])`.
  Three fresh processes per scene measured first preparation UI 32.75–43.60 /
  text 2.33–2.93 / scroll 6.19–6.75 ms; the following screen pass/draw/end cost
  0.038–0.058 ms and commit 0.0001–0.0005 ms. Pipeline warm-up itself took
  226.04–250.57 ms, font resolution 0.198–0.387 ms, before the first frame.
  Preparation still rasterized 40 / 63 / 51 glyphs and uploaded 5,280,120 / 298,080 /
  1,427,112 stream bytes respectively; font resolution does not pre-rasterize labels.
  The first-frame work remaining is in preparation, not shader compilation during draw.
  Quiet-box first-frame measurements remain unproved, as do Metal/web warm-up costs.
  Both native gates passed on that source tree: gate.sh 1196 + 299 + 318 tests,
  golden 82/82, eight existing skips; gate3d.sh 311 PASS, three existing skips.
- **The guardrail-9 backends this box can run**, which P3 did not reach: a desktop GLES3 build of the golden runner (a GL variant of `src/sokol/sokolWin.c` and `glsl430` shaders; `tests/capture/capture.c` already has the `glReadPixels` path, which WebGL2 exercises), and WebGPU's `copyTextureToBuffer` + `mapAsync` readback in a headed browser, since headless Chrome hands WebGPU no adapter here. Metal macOS, Metal iOS and GLES3 Android run on the human's hardware.
- The mesh path's pixel-centre ties: bias mesh geometry by −1/64 px in device space, the fix `tests/PENDING.md conformance:webgl2-pixel-centre` proposes, which keeps D3D11's tie results and gives GL the same.
- The P2 rows this phase owns: the independent non-uniform-SDF bound (`sdf-non-uniform-bound`) and the repository-wide line-length pass (`style:line-length`). Styled-box colour effects (`ui-box-color-effect`) closed at P6: built 2026-10-03 at `b76fee5`, `04484fd` and `4f5c8b7`, and its `tests/PENDING.md` row removed in `fa4426f`.
- The frame profiler: histograms of dirty-to-present, draw time and input latency, plus the draw-call, instance and upload-byte counters GPUI lacks, drawn outside invalidation.

  **Built 2026-10-08** (pure core `f601ed1`, clock and marks `2fb0c3d`, counters `10b387a`,
  invalidation and input stamps `3adcb9f`; overlay `6db39ca` and `762be1e`; golden rows
  `f036ec8`; gate and bench `268a5d8`). Compiled in only with `-d:voidProfiler`; collection
  is always on once compiled in, the overlay is a runtime mode (Hidden, Minimal, Full) that
  `profilerOverlaySetMode` and `profilerOverlayCycle` set and that touches no Scene2D state.
  - **Overlay.** `src/void2d/profilerOverlay.ms` after GPUI `debug_overlay.rs:1-3, 36-47,
    98-160`: a 5x7 bitmap font (`profilerFont.ms`, 41 glyphs) drawn as plain Box
    `UiInstance`s with each row's lit cells merged into one run, on a `DrawContext2D` of its
    own, so it needs no font, glyph page, Scene2D or Yoga. `presentAt` prepares it after the
    scene and before the screen pass and draws it inside the pass (`profilerPrepare`,
    `profilerDraw`; a host that does not use `presentAt` calls the two). Hidden runs nothing
    at all, not even a bracket. The readout is rebuilt every 15 recorded frames, so a still
    scene keeps a still overlay list and uploads it once. Full is 1 336 instances in one
    draw at 384 px, Minimal 80 (the snapshot).
  - **Where it diverges from GPUI.** GPUI's font has 13 letters and skips a character it does
    not know; the counter lines need 14 more glyphs (B D G H I J K P Q V W Y Z and `/`),
    drawn here in the same style, and a character with no glyph stops by name
    (`tests/aborts/overlayNoGlyph.ms`). GPUI scales its 2 px cell by the float scale factor;
    here the cell is rounded to whole device pixels, so every edge lands on a device pixel at
    DPI 1.25 and 1.5. GPUI draws no histogram; Full draws the draw-time and the
    dirty-to-present bucket histograms (Makepad's nine fixed edges, ten buckets, `frame_trace.rs:34-62`) as bars, three
    cells wide per bucket, empty buckets as a dim baseline. While shown, the overlay adds one
    draw and one bracket to the frame's counters; the bench gates run with it hidden.
  - **Scope.** The mode, the readout and the counters are process-wide, as GPUI's overlay is:
    every `presentAt` shows the same overlay, so with two views or windows each one draws it
    and each adds its own draw and bracket to the shared counters. The host owns the key that
    calls `profilerOverlayCycle` (or `profilerOverlaySetMode`); nothing in void2d binds one. A
    framebuffer narrower than the panel pins the panel to the left edge and clips its right.
  - **Tested.** T0 `src/test/profilerOverlayCheck.ms` (font, run merging, layout, bar
    heights, cadence, mode cycle, cell rounding, device-integral edges, the host scene
    staying clean); T1 `tests/displayList/profilerOverlay.txt` (Full at DPI 1.0 and Minimal at
    1.5); T2 rows `ui/profilerOverlayFull` and `ui/profilerOverlayMinimal`; the integration
    `tests/integration/frameProfiler.ms` turns the overlay on and off, reads the panel at the
    right edge, and checks that a new readout reaches the screen; `recordingHolds` is a pure
    function so T0 pins each axis of the recording reuse key. The golden runner is built with `voidProfiler`, so the existing scenes also prove
    "module on, overlay hidden is pixel-identical".
  - **Owed, not run.** The two golden captures and the PNG commit; `sh scripts/gate.sh`
    (frame profiler stage, module-on bench counters equal to the baseline);
    `AB_SUFFIX_B=Profiler sh scripts/bench-ab.sh . . 6 Ui Sprites` for the overhead with the
    overlay hidden; `sh scripts/experiment-profilerWeb.sh` for the wasm delta per backend
    (`tests/experiments/profilerWeb.ms`, which links no `node.ms`); none of these is a
    measurement yet, so no overhead or size figure is claimed.
- **Per-backend shader headers.** Every `.glsl.h` carries the text of every backend (WGSL, Metal, HLSL, GLSL ES) into every binary: void3d measured 243,778 B of shader data for the four premultiplied programs alone in `libVoidAndroid.so` at `764060b` (llvm-nm), most of it other backends' text, and wasm pays the same. `scripts/regen-shaders.sh` cannot pass `--ifdef` because `batcher.c`, `bridge.c`, `bridgeEmbed.m` and void3d's `gpu3d.c` include the headers without the platform's `SOKOL_<backend>`. The fix gives every includer that define, regenerates with `--ifdef`, and stops a build that forgets it with `#error`, because `--ifdef` otherwise compiles the program away silently. Proof: per-platform nm before and after (Android, wgpu wasm, D3D11) and goldens unchanged. Moved here by the human on 2026-10-05.

  **Built 2026-10-05** (`5777cec`, `9ad34b8`): `src/sokol/backend.h` picks the backend once
  (an explicit `-D` wins; else Windows D3D11, Apple Metal, Android and emscripten GLES3) and
  refuses two backends and no backend (and refused `SOKOL_GLCORE` until 2026-10-08, see below). `sokolWin.c`,
  `sokolWeb.c`, `bridgeAndroid.c`, `batcher.c`, `gpu3d.c` and the gpu-registration fixture include
  it; `sokol.m` and `bridgeIos.m` keep their `#define SOKOL_METAL`, which is what the header
  derives on Apple, and were not built here. `scripts/regen-shaders.sh` passes `--ifdef` and
  writes a guard into every header that refuses an includer which skipped `backend.h`. Measured
  on BUILD `5c4246fb`: Android `libVoidAndroid.so` 3,866,136 → 3,392,752 B (`.rodata` 580,816 →
  183,664; only glsl300es text left, llvm-nm); release D3D11 `mainSokol2d` 1,790,464 →
  1,649,664 B and void3d `cameraRigCapture` 1,441,280 → 1,036,800 B. Clang `-fsyntax-only`
  compiles the headers under D3D11, Metal, GLES3 and WGPU, and stops by name on a forgotten
  `backend.h`, two backends and GLCORE. Gates on `c9b1e8f`: gate.sh GREEN, golden 82/82 unchanged; gate3d.sh GREEN, 303 PASS, its shader-freshness stage now `scripts/regen-shaders.sh --check`, so the gate and the script cannot regenerate differently. Not measured: wasm (the web build
  cannot link Yoga) and Metal (no Mac here). Metal still carries its three variants in every
  Apple binary, because sokol-shdc puts macOS, iOS and simulator under one `SOKOL_METAL`.

  **Built 2026-10-08 (GL core 4.3 desktop, item 6; the mesh bias is not built).** `shader2d` alone carries `glsl430` (`LANGS` in `scripts/regen-shaders.sh`); void3d's headers are unchanged. `backend.h` no longer refuses `SOKOL_GLCORE`: `src/void2d/shaderBackends.h` and `src/void3d/shaderBackends.h` (included by `batcher.c`, `gpu3d.c` and the gpu-registration fixture) stop a build whose backend the module's generated headers lack, each naming the header and the backend, so a GLCORE build with void3d still stops by name. `-d:voidGlCore` selects the window-only driver in `src/sokol/gpu.ms` (`sokolWin.c`, `bridge.c`, `bridgeWeb.c`, `-lopengl32`) and the void3d-free scene list in `tests/golden/scenes.ms`; `capture.c` reads the frame as backend 4, directory `gl430`; `sh scripts/golden.sh --backend gl` builds, captures and judges it against the D3D11 goldens under the cross-backend bound and refuses `--update`. Measured here: `clang -fsyntax-only` of `batcher.c` under D3D11, Metal, GLES3, WGPU and GLCORE, and of `gpu3d.c` and the fixture under GLCORE, which stops by name; the preprocessed `batcher.c` under D3D11, GLES3, WGPU and Metal is byte-identical before and after, so those binaries cannot have changed; `msc check -d:voidGlCore tests/golden/runner.ms` type-checks 104 modules against 122 without the flag, and a planted type error shows `when (windows && voidGlCore)` selects exactly one of the two driver blocks. Not measured, owed: the GL build, the first capture (`harness/solid` first) and the comparator run on the NVIDIA driver.

  Mechanisms, each an extension of an existing idiom: `shaderBackends.h` is `backend.h`'s guard moved to the module that owns the generated headers (`scripts/regen-shaders.sh` `guard`); `-d:voidGlCore` is the `when (flag)` module switch of `voidShaper` and its siblings, used for a driver instead of a module; `sceneExclusion` in `tests/golden/table.ms` is **NEW MECHANISM**, small: a named absence per backend, printed as `EXCLUDED <scene> <reason>` by the runner and the comparator and left out of that backend's denominator, so a row that cannot run is never missing and never a silent skip. It can regress: a row added to the exclusion list drops out of that backend's pass rate; `src/test/sceneExclusionCheck.ms` holds the list to the two void3d scenes. The surface is GL core 4.3 because `deps/sokol/sokol_app.h:2378` lists only D3D11, GLCORE, WGPU, Vulkan and NOAPI for Win32, and its GL default is 4.3 off Apple (`:3564-3570`); an Apple GLCORE build would need `glsl410` and `shaderBackends.h` stops it by name. The `-1/64` mesh bias stays unbuilt until this run shows the pixel-centre difference (void manager decision 3, 2026-10-08).

**Defects closed.** None remaining; "Known defects" is empty by the end of P5.

**Exit.**

- The editor scene shows `calt` ligatures; the shaper's pass rate against the HarfBuzz oracle is printed and its PENDING list is explicit.
- Text at 4× zoom and under rotation is crisp through the SDF regime, and the atlas does not grow with the zoom level.
- Every module's wasm delta is recorded per backend and gated against a committed budget; a build with all modules off is measured too, and is the number guardrail 6 is about.
- The fault-injection switch loses the device mid-frame and the next frame is correct.
- `sample_count > 1` works on the iOS and Android bridges without breaking void3d's pipelines.
- Guardrail 9 prints a pass rate for GL core 4.3 desktop (glsl430) and WebGPU instead of a SKIP. **Status 2026-10-08:** the GL surface is built (`-d:voidGlCore`, `sh scripts/golden.sh --backend gl`, gate section 7) and its first run is owed; it reads GL core 4.3 and not GLES3 because sokol_app's Win32 list has no GLES3.
- The colour-emoji line (TESTING.md `text/`) draws in colour through the module, presentation selectors pick text or emoji per grapheme, and a build with the module off pays none of it. **Status 2026-10-08:** built and measured headless; the `text/colourEmoji` capture and the native gate stages are owed (see "Colour emoji" under Built); the module-off proof is by symbol on objects.
- A deferred CJK or emoji family answers coverage without loading, with the module on or off.
- WebGL2 and GL core 4.3 desktop (glsl430) show no structural failure, and every `tests/PENDING.md` row owned by P6 is closed or re-owned by name.
- Metal macOS, Metal iOS and GLES3 Android have their readbacks written, and each reports a pass rate from a run on the human's hardware or stays a SKIP that names the missing run.

**Closes** (`tests/PENDING.md`, checked by the gate): `style:line-length`, `golden-missing:image/animatedFrames`, `sdf-non-uniform-bound`, `backend:gles3-desktop`, `backend:metal-macos`, `backend:metal-ios`, `backend:gles3-android`, `backend:webgpu`, `conformance:webgl2-pixel-centre`, `shape:inter-mark-pair`, `shape-cluster:devanagari-0`, `shape-cluster:devanagari-1`, `shape-cluster:devanagari-2`, `shape-cluster:devanagari-3`, `shape-cluster:devanagari-4`, `shape-cluster:devanagari-5`, `shape-cluster:devanagari-6`, `shape-cluster:thai-variable-0`, `shape-cluster:thai-variable-2`, `shape-cluster:thai-variable-3`, `shape-cluster:thai-variable-4`, `shape-cluster:thai-variable-kern-off`, `shape-cluster:khmer-0`, `shape-cluster:khmer-1`, `shape-cluster:khmer-2`, `shape-cluster:khmer-3`, `macos:voidRunConfigured`, `macos:view-api`.


**Closes** (`tests/PENDING.md`, checked by the gate): `golden-missing:text/ligature`, `golden-missing:image/animatedFrames`, `style:line-length`, `sdf-non-uniform-bound`, `backend:gles3-desktop`, `backend:webgpu`, `conformance:webgl2-pixel-centre`, `shape:inter-mark-pair`, `shape-cluster:devanagari-0`, `shape-cluster:devanagari-1`, `shape-cluster:devanagari-2`, `shape-cluster:devanagari-3`, `shape-cluster:devanagari-4`, `shape-cluster:devanagari-5`, `shape-cluster:devanagari-6`, `shape-cluster:thai-variable-0`, `shape-cluster:thai-variable-2`, `shape-cluster:thai-variable-3`, `shape-cluster:thai-variable-4`, `shape-cluster:thai-variable-kern-off`, `shape-cluster:khmer-0`, `shape-cluster:khmer-1`, `shape-cluster:khmer-2`, `shape-cluster:khmer-3`.

**Closes** (`tests/PENDING.md`, checked by the gate): `golden-missing:text/ligature`, `golden-missing:image/animatedFrames`, `style:line-length`, `sdf-non-uniform-bound`, `backend:gl-core-desktop`, `backend:webgpu`, `conformance:webgl2-pixel-centre`, `shape:inter-mark-pair`, `shape-cluster:devanagari-0`, `shape-cluster:devanagari-1`, `shape-cluster:devanagari-2`, `shape-cluster:devanagari-3`, `shape-cluster:devanagari-4`, `shape-cluster:devanagari-5`, `shape-cluster:devanagari-6`, `shape-cluster:thai-variable-0`, `shape-cluster:thai-variable-2`, `shape-cluster:thai-variable-3`, `shape-cluster:thai-variable-4`, `shape-cluster:thai-variable-kern-off`, `shape-cluster:khmer-0`, `shape-cluster:khmer-1`, `shape-cluster:khmer-2`, `shape-cluster:khmer-3`.

**Re-owned to the human on 2026-10-08, each naming the run that is missing** (decision of the void manager; the Exit line above allows a SKIP that names it): `backend:metal-macos`, `backend:metal-ios`, `backend:gles3-android`, `macos:voidRunConfigured` and `macos:view-api` need a Mac, an iPhone or an Android device that the box owning this code does not have. Each row in `tests/PENDING.md` states the run that closes it, and `scripts/gate.sh` section 7 keeps printing a SKIP for the three backends until that run reports a pass rate.

**Deferred out of P6, each by name** (the builder's reading of void manager decisions 7 and 9 of 2026-10-07, which no tracked file records and the manager has not confirmed). None of these is a `tests/PENDING.md` row, because none is a known defect: each is work P6 does not do, with the reason and the condition that reopens it.

- **void3d `TEXT_SDF` program (SDF spec slice S10).** A billboard program that samples the SDF page with the ramp of `textSdf` in `shader2d.glsl`. Not built because it adds a program to void3d (id 8 of 16 in the 4-bit field of `src/void3d/gpu3d.c`; the door's layout registry is full at eight layouts, so it would reuse BILLBOARD with a shared `position` and a per-glyph `anchor`), it needs the renderer integration of a new program (M33 and M35a as built, not read by the spec), and the void2d SDF it would reuse has no capture yet (`text/sdfRotated`, `sdfZoom4`, `sdfScaleDown` are owed). Reopens when the D3D11 captures of the SDF rows are committed and read through `tests/oracle/textSdfCheck.ms`, and the human confirms the SDF billboard over M41's route (a void2d label rendered into a target and drawn on a billboard, VOID3D.md M41) for a void3d consumer that needs world text.
- **void3d glyph-layer import and its device loss (slices S9 and S11).** `src/void3d/label3d.ms` owning a `LabelText` through `allocateLabelText` and `shapeLabel`, an exported glyph-page upload callable outside void2d's replay, and a world label that survives `loseContext()` while sharing a page with a 2D label. Not built because it is the first import of `src/void2d` by void3d, a layering edge that `CLAUDE.md` (src/sokol to void2d to examples, one way) does not cover and that the human owns, and because without the `TEXT_SDF` program it has no draw to test. Reopens with S10, on the same two conditions plus the human's call on the layering edge (import in place, or move the glyph files to `src/text/` when a third consumer appears).
- **Flat world text.** Text laid on a surface in the world rather than facing the camera. The spec for world text starts with billboards and goes to a text mesh only "if a use case demands it" (VOID3D.md "Deferred from void2d: 3D text + SDF"); no consumer needs a surface-aligned label, and the same SDF tiles would serve it with a different vertex orientation. Reopens when a void3d scene needs a label fixed to a surface and S10 has shipped.
- **Variable-font axes and stem darkening.** `stb_truetype` reads the default instance only and has no `fvar`/`gvar` and no darkening; Ghostty takes axes for style matching and darkens on CoreText only (GHOSTTY.md:29, :45, :110). Taking either means a second rasterizer or a stb patch (`deps/` is not tracked), and the FreeType route was decided out at P3 step 8. Reopens only if the T5 capture beside Zed shows a weight or shape gap that an axis or a darkening pass would close; it is then raised as **NEW MECHANISM** with the rasterizer question reopened, not folded into a fix.
- **`cellMetrics(font, sizePx, dpi)` as void2d public API.** Integer device cell width, height, ascent and box thickness (Ghostty's `Metrics.calc`), so Terminator can set `forceWidth` from the owner of the glyph layer. Not built because it is new public surface in a repo with no consumer for it inside, Terminator is another repository that gets a note in `~/metascript/.inbox/terminator/` from its own session rather than a change from here, and void2d has no cell-metric owner to extend. Reopens when Terminator's session sends the request to `~/metascript/.inbox/void/` and the human approves the API.

**Tests.** T3: the full HarfBuzz shaping oracle, cases as data rows, snapshot committed, CI never needing `hb-shape`. T4: the wasm budget per module — the only gate that makes guardrail 6 real. T2: ligature, emoji, zoom and rotation scenes. Device loss is tested by its own switch, which is why the switch is a deliverable and not a debug aid.

**Measure.** wasm bytes per backend for: no modules, shaper, SDF text, emoji, SVG, sprite glyphs. Atlas bytes across a zoom sweep with the SDF regime on. Frame-profiler overhead when the overlay is off.

**Unblocks.** Nothing depends on P6; that is what makes it the place for everything optional.

**Risk → fallback.** The shaper is a third-party C library that has to build for five targets including wasm, and none of the three references shares it — GPUI uses the OS or cosmic-text, Makepad uses rustybuzz, Ghostty uses HarfBuzz or CoreText. If `kb_text_shape` does not build or does not cover enough, the fallback is HarfBuzz itself, which builds everywhere and costs more wasm, with the cost measured and stated rather than avoided. Without either, P4's surface still works: cmap, GPOS kerning, NFC input and fallback by coverage, with no ligatures — which is the state P4 ships in, so nothing regresses.

### P7 — BiDi and RTL runs

**Goal.** Right-to-left and mixed-direction text laid out and drawn, after the shaper's layout
integration (P6 "Layout integration built 2026-10-08"), which refuses a right-to-left run by
name (void-manager decision 5, 2026-10-07: "BiDi is its own later item, never silently LTR").

**Par.** GPUI takes paragraph direction and run order from its platform text systems; Void
does it itself as a portable module: UAX #9 run levels over P4's segmentation, each level run
shaped in its direction by `kb_text_shape`, reordered per line for drawing, and caret and
selection over visual order. Not started; the mechanism is chosen against its references when
the phase opens.

**Closes** (`tests/PENDING.md`, checked by the gate): `shape:arabic-ltr-explicit`, `shape-cluster:arabic-ltr-explicit`, `shape:missing-mixed-direction`, `shape-cluster:missing-mixed-direction`.

### The budget, at every phase

Checked and recorded per phase, from `tests/bench/`: draw calls, instances and uploaded bytes at 10 000 Box + 10 000 Label; frame time of the sprite-only scene, which must not regress (guardrail 8); CPU time of a fully static 100 000-node frame and of the scrolling 200-line text view from P5 on; atlas pages and bytes after a zoom sweep; wasm size per backend and per module. Counters gate; milliseconds are reported with a warn threshold and never fail a commit — the reasoning is in [TESTING.md](TESTING.md) "T4".

## Unify with void3d (2026-09-30)

The human approved independent unify work while P5 review B1 was compiler-blocked (closed 2026-10-05).
The dependency baseline is main `9f41458` (void3d M18–M22 and the spike deletion, landed and
pushed); integration is not a P5 SHIP or land. The first integration onto M18–M20 at `f625aaa`
is kept by `backup/void2d-before-unify-20260930`; the rebase onto `9f41458`, approved by the
human before D1, by `backup/void2d-before-m22-rebase-20260930`. After that rebase,
`sh scripts/gate.sh --web` on source tree `fa3f2c5b9aed9cb181f15ed0ec0e43af499cf42a`, BUILD
`35601908`, is GREEN with eight explicit skips: 1090 tests plus 299 isolated, D3D11 76/76
unchanged plus three invariants, WebGL2 54 identical / 18 bounded / the same four known-red,
every mixed/context/prepared/replay consumer and six lifecycle refusals, 107 frame functions /
232 callees, 16 PENDING with zero mismatch; web builds 2 282 599 / 2 054 751 B, as before it.
M22 registers five layouts and eleven programs of the door's eight and sixteen.
Live P5 implementation citations were paired by subject; measurement records retain their
original source trees rather than pretending the rebased whole-repo tree was benchmarked.

Earlier phase snippets record the API at that phase; current source names and constructor
ownership are the D3/D4 entry below, not compatibility aliases.

**D3/D4 names and construction:** `node.ms` owns `Scene2D`, `NodeId2D` and `NO_NODE_2D`;
`types.ms` owns `Bounds2D`; `scene.ms` supplies `Scene2D.create`. There is no old-name alias
or forwarding factory. The source names, not import aliases, separate 2D from `Scene3D` /
`NodeId3D` / `Bounds3D`. This follows the shared contract in VOID3D.md "Shared with void2d"
and avoids the already-carded same-source-name alias ambiguity.

Every in-repo retained caller moved with the constructor. `tests/integration/bothLayers.ms`
builds and runs the actual 2D and 3D constructors together and dispatches their tree operations
to their own layer. Existing snapshot/golden geometry did not change. The two Scene factory
default/field-forwarding tests were removed, not re-pinned under the new names.

**Measured after the naming cutover:** `sh scripts/gate.sh --web`, BUILD `35601908`, GREEN:
1058 tests plus 299 isolated, D3D11 76/76 unchanged plus three invariants, WebGL2 54
byte-identical / 18 within the existing bound / four listed structural failures (72/76).
The same four known-red names remain; no golden or tolerance was widened.
WebGPU / WebGL2 builds are 2 109 977 / 1 882 102 B; GL demo liveness passes, headless
WebGPU remains the no-adapter skip. Allocation still holds 103 frame functions plus
232 callees, and the record has 16 PENDING rows with zero mismatch.

**Frame ownership built:** `displayList.ms` `DrawContext2D` now owns streams, emitter state
and frame scratch; Scene2D owns a context/twin pair sharing GPU-owner identity. There is no
DisplayList alias. The selector remains private behind `useContext` / `currentContext`,
the original stream API's idiom, rather than exposing a mutable module global.

CPU state alone was insufficient: preparing another context overwrites native source bindings.
`batcher.c` `void2dRememberContext` / `void2dActivateContext` retain the actual buffer handles,
append offsets, counts, readiness and frame stamp per context. Replay restores those sources,
while the MS context restores its DPI and scope values; activation uploads nothing and opens
no pass. The existing same-frame stale-copy latch remains intact.

Real D3D11 `tests/integration/drawContexts.ms` interleaves A/B recording, prepares both and
the default append context, then replays A/B/default at two DPIs across two frames. Captured
red/green/blue interior pixels hold; an expired context after commit stops with its id/frame.
The native gate is GREEN: 1058 tests plus 299 isolated, D3D11 76/76 unchanged, the same-frame
replay and context consumers, three invariants, 103 frame functions/232 callees, 16 PENDING.
This context pass did not run web; the preceding naming pass's WebGL2 measurement remains above.

One attempted optimisation exported the mutable selector for direct cross-module field access.
That unnecessary exposure was reversed: a compiler-only public global alias destroys the
still-live original reference on C, while private-global and JS controls retain it.
Card `2026-09-30-exported-global-reference-alias-not-retained` owns that failure; no manual
retain, extra ownership holder or crash suppression was added. The private-selector contract
provides the same selection capability and its real default-context replay is proven.

**D2 frame halves built:** `scene.ms` and `draw.ms` `prepare` / `drawScreen` use void3d's
existing prepare/consume frame stamp, with one caller owning the screen pass and commit.
`presentAt` composes those halves for the one-layer caller. Dirty flags are cleared at prepare,
not screen draw: a node write between them belongs to the next frame instead of disappearing.
`tests/integration/preparedScenes.ms` proves filtered snapshots, independent DPI and that
transition with captured pixels; `mixedFrame.ms` uses the immediate context halves beside 3D.
The gate also exercises missing prepare, double prepare, absent/nested pass, consumed and
expired frame errors. This reuses the existing frame mechanism, not a new scheduler.

**Measured on source tree `0410fb1d58b8295e5a12560c69544107bc943858` (D2, before this
record update):** `sh scripts/gate.sh --web`, BUILD `35601908`, GREEN with eight explicit skips:
1058 tests plus 299 isolated; D3D11 76/76 unchanged and three invariants; WebGL2 54 identical,
18 within the existing bound, the same four structural known-red (72/76), no new red.
Mixed layers, raw context interleave/default append and prepared retained consumers pass,
as do all six lifecycle-error processes. Allocation covers 107 frame functions and
232 callees; the record remains 16 PENDING with zero mismatch.
WebGPU / WebGL2 builds are 2 282 599 / 2 054 751 B, up 172 622 / 172 649 B from the naming
baseline above. That delta includes both the context move and frame halves, not D2 alone;
no module budget exists until P6. GL demo liveness passes; WebGPU remains the no-adapter skip.

**D1 capacity seam, measured before the cutover:** void3d registers four vertex layouts; void2d's current
vertex, sprite, UI and blur input shapes add four distinct layouts. The door admits eight.
Both built-in layers fit exactly, but leave no slot for a foreign layout; the existing
foreign-consumer fixture registers four. A CPU-only registry control on BUILD `35601908`
registered the four 3D layouts, reserved four more (base 4), then one more: it stopped with
`gpu door: the vertex layout registry is full (8); a wider pipeline key is a design change`,
exit 9. The extra descriptors were zeroed: this measured registry width, not migrated 2D GPUs.
At source tree `59cb0902720cdf31db112125e46c5a6cc6ac21b4`, `src/gpu/pipeline.ms` `PipelineKey`
still packs exactly 64 bits, including three layout bits. Simply raising the registry limit
would alias ids in that encoding. No limit has been raised, no foreign fixture suppressed and
no shader padded or rewritten to hide the seam.
The implementation direction below was settled after reading the references, not inferred
from that count-only control.

### D1 direction agreed for the fresh session (2026-09-30)

The human asked for Heaps/Bevy research, then explicitly added Sokol and Browser WebGPU, and
closed the discussion with “chốt được rồi thì và mình sẽ làm theo hướng đã chốt trong session
mới nha”. Implement the full value-identity direction in the next session; not a second-word
patch by default and not a new raw-WebGPU layer. Built: "D1 as built" below.

**Decision:** reuse the existing descriptor/equality cache and GPU door; remove the global
program/layout bit budget from pipeline identity. Resource ids must retain their complete
meaning, while finite render-state flags may remain packed. Key the supported semantics of
the Sokol pipeline, not only the immutable fields of a raw WebGPU pipeline. Resolve defaults
consistently within the GPU environment and keep GPU handles scoped to the owning device
lifetime. Registration metadata and shader lookup storage must move with the identity;
changing only the key leaves the old 8/16 arrays as a separate ceiling.

This is the approved representation/registration cutover raised as **NEW MECHANISM**, reusing
reference identity/equality rather than inventing a scheduler or descriptor-specialization
framework. Keep real resource limits and named errors. It is not approval for P6, device-loss
recovery, arbitrary new shader features, a Sokol fork change, land or push.

**Why this instead of two packed words:**

- Heaps at `b9aa6dcbb2307b03c1f435e87bdb036060100984`: `h2d/RenderContext.hx` `RenderContext`
  uses h3d's engine; `h3d/impl/DX12Driver.hx` `CompiledShader.pipelines` / `flushPipeline`
  scope the cache to a shader. `h3d/impl/PipelineCache.hx` `PipelineBuilder.lookup` hashes a
  variable-length byte signature and compares its full size/content on a hit. Its scratch is
  64 **bytes**, not a global 64-bit identity. `hxd/BufferFormat.hx` `uid` / `resolveMapping`
  and `GlDriver.hx` `selectShader` / `selectBuffer` keep shader and input-format identities.
- Bevy at `157e1ce6bc66fadca9f57260c18a16d743c11ed5`: `bevy_render` `pipeline_specializer.rs`
  `SpecializedMeshPipelines` keys on `(MeshVertexBufferLayoutRef, S::Key)` with full equality;
  compatible resulting vertex layouts have a second reuse path. `bevy_sprite_render`
  `mesh2d/mesh.rs` and `bevy_pbr` `render/mesh.rs` pass layout separately from their u64 variant
  flags. `pipeline_cache.rs` `queue_render_pipeline` stores descriptors under unique ids and
  explicitly does not auto-deduplicate. One device does not require one universal packed key.
- Vendored Sokol `2e75443dbd4940b5aa8d76a8e479f8e4b270b9a3`: `sokol_gfx.h`
  `sg_pipeline_desc`, `_sg_pipeline_desc_defaults`, `_sg_pipeline_common_init` and
  `_sg_wgpu_create_pipeline` are the actual object contract. Resource layouts are derived from
  the shader; `_sg_wgpu_apply_pipeline` also applies pipeline-carried blend constant and stencil
  reference. If Void exposes them, they belong to Sokol identity even though WebGPU applies
  them dynamically. Views, textures and uniform contents stay draw bindings, not pipeline keys.
- Browser path: `scripts/build-web.sh` and `src/sokol/sokolWeb.c` select SOKOL_WGPU with
  emdawnwebgpu. Its `library_webgpu.js` `wgpuDeviceCreateRenderPipeline` forwards to Browser
  `GPUDevice.createRenderPipeline`; it is not a native wgpu renderer. Emdawn's package README
  describes that bridge at
  https://dawn.googlesource.com/dawn/+/01940842b667a7812d0e4ca0ef4367fbec294241/src/emdawnwebgpu/pkg/README.md.
  Sokol's pinned path is synchronous and already owns bind-group caching; do not duplicate it.

**Measured controls, not a shipped cache or FPS claim:** on installed BUILD `35601908` and
the source tree above, a standalone native value-identity experiment distinguished 800
program/layout/index combinations, reused identical keys and distinguished state/target
changes; the backend-neutral control passed on C and JS. The prototypes were a value key of
int32 program/layout, boolean indexed and uint32 state/targets, or two uint64 words; each entry
adds one uint32 pipeline. C key/entry sizes were old 8/16 B, two-word 16/24 B and named-field
20/24 B. Named fields did not cost more entry storage than the two-word prototype on this ABI;
equality work and browser timing were not benchmarked.

A real D3D11 Sokol object-creation control resolved implicit/explicit vertex inputs to stride
32 and offsets 8/16. Equivalent descriptors still created distinct valid handles 65537/65538,
confirming that `sg_make_pipeline` does not memoize them. Screen 4x/BGRA/depth and offscreen
1x/RGBA/no-depth pipelines both created successfully. Configured pools were 32 shaders and
64 pipelines: metadata growth is not permission for unlimited live GPU objects. Create used
variants and expose/control preparation deliberately rather than blindly precreating a Cartesian
product; this is not a promised async pipeline compiler.

Commands from the worktree were `MSC_NO_GLOBAL_CACHE=1 msc build
out/tmp/refCacheResearch/keyProbe.ms --release --output=out/refKeyProbe.exe` plus that
executable; `msc build out/tmp/refCacheResearch/valueOnly.ms --target=js
--output=out/refValueProbe.js` plus Node; and `MSC_NO_GLOBAL_CACHE=1 msc build
out/tmp/sokolResearch/main.ms --output=out/sokolIdentity.exe` plus that debug C executable.
Temporary sources/outputs were removed; these are isolated research observations, not permanent
regression pins. Heaps/Bevy tracing was not an engine runtime benchmark. HashLink was unavailable;
a Haxe interpreter attempt could not compile the HashLink-specific `Single` type. A Node attempt
importing native GPU modules failed on a C-header constant; only the separate value-only JS
result is claimed. No Browser WebGPU pipeline execution/pixels were proved.

**Relaunch receipt:** after this documentation-only decision record, `sh scripts/gate.sh`
on the unchanged renderer source is GREEN: 1058 + 299 tests, D3D11 76/76 plus three invariants,
all mixed/context/prepared/replay consumers and six lifecycle refusals pass, 107 frame functions /
232 callees, 16 PENDING with zero mismatch, eight explicit skips and no new red.
This close-out did not rerun web; the D2 source-tree `--web` evidence above remains the web baseline.

**Implementation boundary:** finish this identity/storage cutover, migrate void2d
programs/pipelines/targets and shared BlendMode through the door without aliases, then prove
foreign registration order/boundaries and real mixed layers. Preserve the completed frame halves,
retained coherence and capability; do not hide compiler cards, collapse distinct vertex inputs
to fit a count, or treat the prototype key's five fields as the entire WebGPU API.

### D1 as built (2026-09-30)

Built on main `9f41458` (M22), after the human approved that rebase. P5's independent
Scene-lifetime blocker remains parked, and P6 is not started.

**Identity.** `pipeline.ms` `PipelineKey` is {program, layout, index type, `RenderState.bits`,
`TargetLayout.formatBits`}, compared by equality in the existing cache. Program and layout ids
keep their int32 meaning; the two bit words stay packed because they are lossless finite
encodings, and a sample count now has twelve bits. T0 pins the three aliases the 64-bit word had:
layout 8 beside layout 0, program 16 beside a colour-format bit, sample count 16 beside the
culling bit. A control applying the old masks turns those tests red.

**Storage and limits.** The door registries grow and refuse only int32 id exhaustion or an
allocation failure, by name; `PipelineCache` shader and block tables grow with the program id,
after the id is checked against the door's `programCount`. The limits left are sokol's pools,
32 shaders and 64 pipelines as configured here. A refused shader, pipeline, target image or view
stops and names what was refused, where it used to hand back 0 or a failed id and draw nothing.
Lookup stays a linear scan, now with 20-byte key equality where it compared one word: a cache
holds dozens of entries. Heaps hashes the signature first (`h3d/impl/PipelineCache.hx`
`PipelineBuilder.lookup`); that is the step if a measured cache grows. Neither was timed.

**Measured on the way: three shared blend modes were broken on D3D11.** Through the door,
`AlphaMultiply`, `Erase` and `Screen` failed `CreateBlendState()` (probe on BUILD `35601908`):
D3D11 refuses a *_COLOR factor on the alpha channel. door.c now spells alpha-channel factors as
Heaps' DirectXDriver does (`h3d/impl/DirectXDriver.hx` `BLEND_ALPHA`, `:1493-1509`, used at
`:766-767`); for the alpha component both spellings are the same number, so no backend's pixels
change. `tests/integration/doorBlendModes.ms`, a gate consumer, makes all twelve modes; without
the table it stops naming AlphaMultiply's key.

**void2d through the door.** batcher.c registers four programs and their layouts (vertex,
sprite, UI, blur). Recording marks each (program, target, blend) slot it uses; `flushTargets`
resolves new slots through a 2D `PipelineCache` and hands the handles to the replay, which stops
on a slot it was not given. Nothing is created eagerly: the 4 × 2 × 12 slots exceed the pipeline
pool, so a process holds only what it recorded. Goldens stayed byte-identical through the move.
The 2D cache follows the owner model void3d already has: when `contextGeneration` changes it
forgets its handles and re-resolves every slot it hands the replay. The rest of a 2D context-loss
rebuild (buffers, glyph pages, samplers) remains P6's.

**Preparation is the host's, and it is measured.** Creating a program's first pipeline compiles
its shader, which the pipelines after it do not pay. On D3D11, release, BUILD `35601908`, shared
box: vertex about 69 ms (the first compile in the process), UI about 124 ms, sprite 6 ms, blur
4 ms, three runs each; one more pipeline about 0.01 ms. Before D1 all four compiled in
`setup2d`; now a frame pays for the first program it records. `preparePipelines(modes)` makes
the three drawing programs' screen and offscreen pipelines for each mode, plus the blur, when the
host calls it. Measured without it, the gate's first-paint reports moved from ui 37 / text 3 /
scroll 7 ms to 179 / 126 / 164 ms; the bench and the demo now prepare at setup, as a host should,
and the Neon host note says so. WebGPU's first-use cost is not measured (no adapter here).

**Shared BlendMode.** 2D takes `gpu/state.ms` `BlendMode`. Its content is premultiplied, so
`draw.ms` `premultipliedBlend` applies h3d's `setBlendMode` and turns every `SourceAlpha` source
factor, colour and alpha, into `One`; `Erase` becomes destination-out, (Zero,
OneMinusSourceAlpha), because h3d's per-channel (Zero, OneMinusSourceColor) leaves colour above
alpha. `Alpha`, `Add`, `Screen` and `None` keep their names and factors. The old 2D `Multiply`
was h3d's `AlphaMultiply` and is spelled so now. New to 2D: `AlphaAdd` (the same as `Alpha` on
premultiplied content), `SoftAdd`, `Erase`, `Subtract` (destination minus source, alpha
included), `Max`, and the two arithmetic modes `Multiply` (src × dst) and `Min`, where a
transparent source writes transparent black, as h3d's do on opaque sources. T0 holds the five old
modes to batcher.c's former factor table and evaluates every mode's equation on premultiplied
operands: a transparent source leaves the destination under the compositing modes, Multiply and
Min write transparent black, and every mode but Subtract stays premultiplied; without the Erase
rule that last test fails. HEAPS.md "Do not copy from h2d" records the divergence.
T1 snapshots print blend ordinals, so they moved: Alpha 0 → 1 on 25 rows, Add 1 → 2 on one, and
nothing else changed.

**Targets.** The filter pool, `beginTarget` and `filter.ms` take the door's `RenderTarget`;
`beginTarget` stops on a target that is not an allocated Rgba8 one or a scale that is not
positive, and `blurPass` stops outside a target; `tests/aborts` holds each stop and an
unregistered program id. The replay opens and ends target passes through `doorBeginColorPass`
/ `doorEndPass`, which stops on a view that is not live, so the door's pass state holds during
2D replay. A sampled view counts as a render target when sokol reports its image as a colour
attachment (`sg_query_view_image`, `sg_query_image_usage`) rather than by membership in a
table, so a void3d target drawn by void2d is now flipped on GL and read as premultiplied; no
current scene samples one. The bridge's sixteen-slot render targets are deleted.

**Harness finding.** Lazy shader creation moved D3D compiler warnings into the first frame.
sokol_log truncates a line at 512 bytes and drops its newline (`deps/sokol/sokol_log.h`
`_slog_func`), so a verdict printed after it joined that line and anchored greps missed it; the
eager setup had closed the line by accident. golden.sh, gate.sh's two-view pass and gate3d's four
anchored mixed-frame and both-layers checks read stdout apart from stderr.

**Registration.** mixedFrame's foreign consumer gets program 5 / layout 3 registering first and
20 / 12 after both layers (void3d 11 / 5, void2d 4 / 4, fixture 5 / 3 more), both past the old
16 / 8; gate3d draws the same lit frame through it in both orders.

**Measured on source tree `75d8022122190f65535078576e483e601c98e6a9` (`c745179`, before this
record update):** `sh scripts/gate.sh --web`, BUILD `35601908`, GREEN with eight explicit
skips: 1096 tests plus 299 isolated, D3D11 76/76 unchanged plus three invariants, WebGL2 54
identical / 18 bounded / the same four known-red, every consumer and abort, 107 frame
functions / 239 callees, 16 PENDING with zero mismatch. Web builds are 2 351 747 / 2 123 985 B,
69 148 / 69 234 B above the rebased baseline; no module budget exists until P6. `sh
scripts/gate3d.sh` on the same tree is GREEN with its device skip. REVIEWS.md "Unify D1" has
the review.

**Not proved, not built.** Browser WebGPU pipeline creation, pixels and first-use cost (headless
Chrome has no adapter here). The screen layout's identity and the WebGL2 golden of a void3d
target are closed in "D1 follow-ups" below; how an app declares premultiplied content, in
"Door closure".

**Ownership seam to keep visible:** the workspace coordinator reported a real D3D11 host-view
audit on the pre-integration source: mutating a caller's `Paint2D.colorMatrix: float32[]`, or
that reference inside a `paint()` result, changes stored paint while `isDirty` stays false;
calling `setPaint` again with that same array still skips as equal. This is ordinary shared-field
aliasing, not a compiler failure. That audit captured dirty-state values, not pixels, and this
lane has not independently reproduced or implemented a separate fix. Frame-context ownership
must not treat a copied value wrapper as a deep-frozen snapshot of its reference fields.
Closed by "Door closure" E: the matrix is a `Mat4` value in a scene side table, measured red before.

### D1 follow-ups (2026-10-01)

The human approved closing the review's carried items after the D1 land.

**Screen pipelines key on the environment's formats (F5).** `pipelineFor` resolves a layout that
names `Default` or a zero sample count against sokol's environment defaults (`target.ms`
`TargetLayout.resolved`) before it keys and describes the pipeline, which is the D1 direction's
"resolve defaults consistently within the GPU environment". A key holds concrete formats, so
`SWAPCHAIN_LAYOUT` and the environment spelled out are one pipeline. The door's `PixelFormat`
gained `Bgra8` and `DepthStencil`, the formats the environments here default to, and stops on an
environment format it does not name, or on a resolution before the device exists
(`tests/aborts/screenLayoutWithoutDevice.ms`). `pipelineFor` checks the program id before it
asks the device anything, so `unregisteredProgram` still stops on the id. On D3D11, the window at sample count 1, `SWAPCHAIN_LAYOUT`
keys as `colors=Bgra8 depth=Depth sampleCount=1`. `tests/integration/doorBlendModes.ms` asserts
that the explicit spelling reuses the Alpha screen pipeline; with the resolution removed it stops
on a second pipeline (control, BUILD `5791eadd`). T0 pins the resolution and that two
environments differing only in sample count key apart.

The aliasing F5 named, two swapchains of different formats or sample counts sharing one
pipeline, is refused rather than keyed: `bridge.c` `voidBeginPass` stops on a swapchain the
environment does not describe and names both. Heaps keys its one back buffer the same way, one
signature for the screen (`h3d/impl/PipelineCache.hx` `setRenderTarget` with a null texture).
GPUI and Bevy key per surface or view instead; Void needs that only for a host that drives
swapchains of different layouts from one device, and none does. Every driver's environment equals
every swapchain it hands out (the D3D11 and Android views at one sample and no depth, the sokol_app
window through sglue), so no consumer can trip the stop on this box. The macOS embed bridge
builds its own pass (`bridgeEmbed.m` `voidBeginPass`) from the same three constants as its
environment and has no stop; it is not built here.

**Measured on the F5 source, BUILD `5791eadd`, shared box:** `sh scripts/gate.sh --web` GREEN
with eight explicit skips: 1099 tests plus 299 isolated, D3D11 76/76 unchanged, WebGL2 54
identical / 18 bounded / the same four known-red, 107 frame functions / 239 callees, 16 PENDING.
Web builds are 2 357 767 / 2 129 952 B, 6 020 / 5 967 B above D1's. `sh scripts/gate3d.sh` GREEN
with its device skip.

**A void3d target drawn by void2d, on WebGL2.** Golden `mixed/void3dTarget`
(`tests/golden/mixedScenes.ms`): void3d's forward renderer draws two boxes into its own colour
target once, at build, and void2d draws that target as a sprite. It is the first golden that
runs void3d on WebGL2. The WebGL2 capture is byte-identical to the D3D11 golden. With the GL row
flip removed from the sprite path in `batcher.c` (control), the row fails on WebGL2, as do the
four other rows that sample a target through a sprite. So `sampledTarget` reads a void3d target
upright on GL, as finding 5 argued from `blit.ms`.

### Door closure (2026-10-01)

Approved by the human on 2026-10-01 together with the per-draw premultiplied declaration ("ừ đồng
ý cả 2"). The before-proof is void-unify's real-D3D11 boundary audit
(`~/metascript/void/out/tmp/unifyAcceptanceD0/evidence.zip`, pinned at `d0f81e6`); re-run on
`e22b1fc` from this worktree (`out/tmp/doorAudit/run`) it reproduced every BUG line; the two
cross-store owner lines (a `MaterialId` or `TextureId` of one void3d store accepted by another)
are void3d's, closed by its store identity (M24), not here. Each finding
is one fix commit with its own red-before measurement; its pins are in `tests/aborts3d` (gate3d's
abort stage) unless named otherwise.

- **A, one owner of pass state.** `door.c` holds the pass state and stops, naming the call, on a
  begin while a pass is open, an end with none, a `commit` with a pass open, and a pass or
  pipeline descriptor shorter than its layout. `door.ms` only forwards, so a C consumer of
  `door.h` meets the same stops. `commit` moved to `gpu/door`; `sokol/gpu` lost `beginPass`,
  `endPass` and `commit` and the bridge lost `voidEndPass`, so nothing reaches sokol's pass state
  around the door. Red before: a nested C screen pass and an end with none hit sokol's unnamed
  asserts (debug builds only), the short descriptors returned silently, and the audit's legacy
  begin and end left the door reporting None and Screen. Pins: `doorForeignScreenPassTwice`,
  `doorForeignEndPassNone`, `doorShortPassDescriptor`, `doorShortPipelineDescriptor`,
  `doorCommitInsidePass`.
- **B, four color attachments.** `beginPass` and `layoutOf` stop on a fifth; before, the fifth was
  dropped and its target kept its old pixels (the audit read blue where red was cleared). The
  limit stays sokol's four, which WebGL2 also guarantees. Pins: `doorFiveColorPass`,
  `doorFiveColorLayout`.
- **C, handles tied to their GPU context.** `RenderTarget`, `Sampler`, `ColorAttachment` and
  `DepthAttachment` carry the `contextGeneration()` they were made in, the `GpuTexture.generation`
  idiom, since sokol ids repeat after `sg_setup`. Current target ownership is `target.ms`
  `RenderTarget`, `resize`, terminal `close` and `isClosed` (the reference-owner entry below);
  Sampler remains a value whose `released()` returns empty handles for the caller to assign.
  Both retire only their current context's objects. The borrows `asColor`, `asDepth`,
  `asTexture` and `asHandle` reject another context, a destroyed image or a destroyed view.
  A closed target rejects mutations and borrows; `isClosed` remains its status query. An open
  unallocated target can still lend
  an attachment of view 0, because void3d's `setLook` borrows before the first resize;
  `beginPass` rejects that empty attachment, one from another context and, in `door.c`,
  a dead view. The pipeline cache adopts the current context
  itself (`pipeline.ms`
  `adoptContext`), and `releasePipelines` destroys only its own context's objects; releasing and
  closing stay two calls, and forgetting is the cache's own (F). void2d's `beginTarget` checks
  the owner's closed state and GPU generation (`requireCurrent`): T1 records without a device,
  and the replay's `doorBeginColorPass` rejects a dead view. The filter pool and presets
  resize stale targets in place; the target owns epoch adoption and retains its reference
  identity. No device here loses its context, so
  that path is read, not run. Red before: the audit's same-size resize after a release returned
  the destroyed view. Pins:
  `targetResizedAfterClose`, `targetTextureAfterClose`, `targetClosedTwice`,
  `targetOtherContext`, `targetViewDestroyed`, `samplerHandleAfterRelease`,
  `attachmentAfterRelease`, `attachmentOtherContext`, `attachmentWithoutView`, `depthWithoutView`,
  `targetTextureUnallocated`, `samplerHandleEmpty`, and T0
  `pipelineCheck` "releasing a cache of another GPU context drops its handles without destroying
  them", and `tests/aborts/targetOtherContext2d`.
- **D, view ids with a generation.** `views.c` hands out `(generation << 5) | (slot + 1)`: opaque,
  positive, 0 invalid, sixteen slots. An id kept past its view's destroy stops by name ("was
  destroyed"). A slot whose generation reaches `VOID_VIEW_LAST_GENERATION` is retired, as
  `void3d/slots.ms` retires a row, and `voidViewCreate` stops once all sixteen are in use or
  retired. The last generation is a compile-time override, so the fixture retires all sixteen in
  sixteen pairs; a build with the override does not reach the object cache of a plain build
  (`out/tmp/viewCache/receipt.txt`: a plain build right after it reuses slot 0 at generation 2). Red
  before: the stale id 1
  resized the view made after it; with the limit at 1 a seventeenth view was made. Pins:
  `viewIdAfterRecreate`, `viewSlotsRetired`.
- **E, the color matrix as a value in a side table.** A node's matrix is a `Mat4` (h2d's
  `h3d.Matrix`) in the scene's `colorMatrices` rows; `Paint2D` holds only `colorMatrixRow`, -1
  for none, and the immediate `setEffect` / `setGradientEffect` take a `Mat4`, identity meaning
  none, written into the effect row in field order (`effect.ms`). `setColorMatrix` claims,
  rewrites or frees the row and marks the node; `colorMatrix()` reads a copy; `setPaint` stops
  on a paint that would move the row. The first cut held the `Mat4` inline in `Paint2D`, which
  the design pass measured against guardrail 2: from the emitted field list `Paint2D` is about
  80 B before the closure (a `float32[]` is an 8 B reference), about 128 B with the matrix
  inline and about 68 B with the row, against SCENE-SCALE's 60 B per node; the matrix is read
  only when emitting, which is box style's side-table case. Red before
  (`out/tmp/paintMatrix/receipt.txt`, the probe built from the source before the fix): writing
  the read copy changed the stored matrix (`m[0]` 2) and `setPaint` marked nothing. Pins: T0
  `nodeCheck` "a color matrix read from a node is a value" and "lives in a side row", and
  `tests/aborts/paintMovesColorMatrix`. An app reads the matrix with `colorMatrix()`; a
  `float32[]` literal becomes a `Mat4`; `colorMatrixGrayscale` and `colorMatrixAlphaOnly` keep
  their names.
- **F, the pipeline cache as a reference owner (2026-10-02).** `pipeline.ms` `PipelineCache` is
  an `interface` with `closed` beside `generation`, taken by value by every call, the door's and
  void3d's `gpu3d.ms` `pipelineFor` alike, so `let c = context.pipelines` or a struct holding the
  cache names the one cache. As a struct, every copy shared the handles but not the state. The
  consumer below, run on the struct (`out/tmp/cacheOwner/structRed.receipt.txt`, `7f8507b` plus
  the struct-era copy of the consumer) showed the hazard in numbers: a generation written through
  the context read 1 through the holder instead of 8; after a release through the context the
  holder still held 2 shaders and 4 pipelines that were destroyed; a rebuild through the holder
  made 2 shaders and 4 pipelines, and the context, still stale, made them again (A held 4 shaders
  and 8 pipelines alive for the 2 and 4 it wanted); 2 shaders and 4 pipelines outlived the final
  release.
  - `releasePipelines` stays a reset: it destroys the current context's objects or forgets a
    stale context's, and the cache rebuilds on its next `pipelineFor`. `closePipelines` is
    terminal: it releases, empties its tables and sets `closed`. Both stop while the door has
    a pass open, before they change anything: a pipeline destroyed inside a pass leaves that
    pass's later draws on a dead id, and before the defect pass `pipelinesReleasedInsidePass`
    ran to its end with the pipeline it had made destroyed. Every later call (`pipelineFor`,
    `shaderFor`, `releasePipelines`, `closePipelines`) stops naming itself; `contains` and
    `declaresBlock` answer false, because a closed cache holds nothing, the answer
    `declaresBlock` already gives for a program whose shader was never made; `isClosed` lets a
    parent skip a closed cache. Close is a separate call because release is what context loss
    and void2d's own cache reuse: a cache closed by its owner must make a later call through a
    forgotten alias fail loud, where a reset would rebuild objects nobody releases. void3d's M25
    `DrawContext.close` calls `closePipelines` once (acked by void3d).
  - `forgetPipelines`, which drops handles without destroying them, is the cache's own: only
    `adoptContext` (on a stale epoch) and `releasePipelines` call it. Exported, it was a way to
    leak every live object of a current epoch, and once both hand-stamped epochs were gone
    nothing outside called it (design pass).
  - void3d's `renderer.ms` `beginFrame` and void2d's `draw.ms` `resolvePipelines` no longer
    stamp the cache's epoch by hand; the cache adopts a new context at its next call
    (`adoptContext`), as C already said, and void2d only compares the epoch to reset its
    resolved slots. The door counts `liveShaders` and `livePipelines` from
    `sg_query_stats().total` (`sokol_gfx.h:4640-4647`), as it counts buffers, images, views and
    samplers.
  - Unparked by void3d's M24 (`DrawContext` an interface taken by value, on main at `2c9060c`),
    which removed the one site the C backend could not compile; the compiler card
    `.inbox/compiler/2026-10-01-ref-struct-interface-field-c-member-access.md` stays open for the
    shape itself.
  - Acceptance is `tests/integration/pipelineCacheOwner.ms` (`gate.sh`, D3D11 readback): cache A
    held through a void3d `DrawContext` field and a struct holder, cache B a second context's
    drawing a lit box every frame. (a) a generation written through one alias reads back through
    the other; (b) a release through one destroys A's 2 shaders and 4 pipelines exactly, the
    other destroys nothing; (c) only after that release is A's epoch marked stale and rebuilt
    through the holder, and the context reads the same handles and makes nothing; (e) a close
    through the context destroys A's objects and the holder reads it closed; (d) B's picture is
    byte-identical in every frame and, after B is closed, shaders and pipelines are back at their
    count before either cache and the rest at their count after B's first frame. The stale epoch
    is written by hand: no device here loses its context, so (c) proves adoption, not device
    loss. Red on the struct for (a), (b), (c) and (d); (e) needs `closePipelines`, so its red is
    the controls.
  - Pins: aborts3d `pipelinesClosedThroughAlias`, `pipelinesShaderAfterClose`,
    `pipelinesClosedTwice`, `pipelinesReleasedAfterClose`, `pipelinesClosedInsidePass` and
    `pipelinesReleasedInsidePass` (the three that never draw open no device), and T0
    `pipelineCheck` "closing a cache of another GPU context empties it and answers false
    after". Each check, removed alone, turned its pin red, and the file was restored by hash
    (`out/tmp/cacheOwner/controls.txt`, `reviewRed.txt`, `controls.followup.txt`). Four are red
    by message only, because another check still stops the call: without `pipelineFor`'s check
    `shaderFor`'s stops it, without the second-close check release's does, without release's
    own check the then-exported `forgetPipelines`'s did, and without `shaderFor`'s check a
    device-free call reaches the unregistered-program stop.
  - Measured on tree `e9b879b1ceff` (tip `950f274`), BUILD `5791eadd`, shared box: `sh
    scripts/gate3d.sh` GREEN, 130 stages, its device SKIP, 73 aborts with the six above;
    `sh scripts/gate.sh --web` GREEN with its 8 loud skips: 1128 + 299 tests, the consumer's
    stage, D3D11 78/78, WebGL2 56 identical / 18 bounded / the same four known-red, 107 frame
    functions / 245 callees, 16 PENDING, web 2 345 812 / 2 118 001 B (1 068 / 1 072 B over
    `7cf741d`, M24 included). Logs: `out/tmp/cacheOwnerGate/`.
- **Premultiplied, declared per draw.** A `Tile` says whether its texels are premultiplied
  (`alphaPremultiplied`, set by `.premultiplied()`, false by default, as Heaps' texture flag
  `h3d/mat/Data.hx:110` and Bevy's alpha modes default to straight). Every draw that takes a raw
  view takes the bit; it rides `CMD_SAMPLER` above the sampler index (`SOURCE_PREMULTIPLIED`),
  splits the run when it changes, and the replay reads it. The replay no longer asks sokol
  whether content is premultiplied, only whether a view is a render target, for the GL row flip.
  void2d's own target blits and the app's target sprites declare it (`render.ms`, `filter.ms`,
  the demo, `mixed/void3dTarget`); Neon holds the per-image fact. A colour effect and the UI
  program read the bit too, since G below. Control: without the declarations `filter/blur`,
  `filter/afterTintedSibling` and `filter/maskAtDpi150` fail on D3D11; `mixed/void3dTarget`
  passes either way, because its target is opaque, so `mixed/void3dTranslucentTarget` clears
  the same target translucent over a 2D stripe and draws it through the instanced sprite
  program: without its declaration it fails on D3D11, with it it passes. Pins: that golden and
  T1 snapshot "a premultiplied tile carries its bit into the command and splits the run". Why this
  shape: h2d already decides per
  draw (HEAPS.md "Do not copy from h2d"); GPUI normalises at the source, which is W here, since
  void2d composites its own premultiplied targets every frame and a conversion pass per target
  would buy nothing; the bit rides `CMD_SAMPLER` because all 32 command floats are taken and the
  sampler field already carries the source-read state through runs, target saves and replay.

  ```ts
  // before: Void guessed premultiplied from how the image was made
  s.add(s.sprite(tile(forward.colorTarget.asTexture(), 256, 256)));
  // after: the app declares it; an uploaded straight image says nothing
  s.add(s.sprite(tile(forward.colorTarget.asTexture(), 256, 256).premultiplied()));
  ```
- **G, a premultiplied source through a colour effect or an image style (2026-10-03).**
  After the per-draw declaration, a premultiplied source that also took a colour matrix,
  `colorAdd` or `colorKey` was still read as straight. The replay set the shader's premultiplied
  input only for an identity effect, so:
  - the effect's output was premultiplied a second time, and each translucent texel darkened by
    its own alpha;
  - a key cleared alpha but kept rgb, and the premultiplied blend then added that rgb to the
    destination.

  The UI program had no premultiplied input, so an image style on such a tile stopped.

  GPUI is the model. It unpremultiplies a premultiplied source once, at upload
  (`gpui/src/color.rs:26-34`, called from `svg_renderer.rs:213` and the macOS
  `text_system.rs:524`). It applies grayscale to straight colour
  (`gpui_wgpu/src/shaders.wgsl:1306-1309`) and premultiplies only at output (`blend_color`,
  `:391-395`). void2d composites targets it renders every frame, so it cannot convert at upload
  (the W above) and converts at the sample instead:
  - For a premultiplied source with any effect, the replay sets `sourceParams.x` in the effect
    block (`batcher.c`, where `noEffect` now covers the key).
  - The fragment then divides rgb by alpha before the key and the matrix, and from there the draw
    takes the straight path.
  - A premultiplied draw with no effect keeps its pass-through, so no other golden moved.
  - The UI image mode needs no division, because grayscale, tint and coverage are linear in rgb.
    `params1.y` marks a premultiplied tile per instance, beside grayscale in `params1.x`, and the
    fragment skips the final premultiply.

  h2d's own colour effects run on premultiplied texels (HEAPS.md "Do not copy from h2d").

  **Acceptance** is a pair invariant in `tests/golden/invariants.ms`: the same 64² alpha ramp,
  uploaded straight and premultiplied, must draw within ±1.
  - `image/premultipliedEffect` row 1 draws it through grayscale and a `colorAdd`.
  - Row 2 uses four colour bands at alpha ≥ 128 and keys out one of them.
  - `image/premultipliedStyle` draws it through a grayscale image style with corner radii.

  **Red before**, on `2be9cf5` plus the scene (`out/tmp/premultEffect/red.txt`):
  - row 1 was off in 11 896 channel values, max delta 48 (113 against 65 at alpha 0.5);
  - row 2 was off in 3 072, the whole keyed band, max delta 200;
  - the style scene stopped at `premultipliedStyledImage`.

  After the fix, both scenes pass at max delta 1.

  **Limit, not measured.** The colour recovered by the division is only as exact as 8-bit
  premultiplied data allows: rgb / a carries an error of up to half a level divided by a. A key
  is tested on that colour, so it matches the straight copy exactly only where alpha is high,
  which is why the key row stays at alpha ≥ 128; near-transparent fringes can key differently.
  A target with additive content holds rgb above its alpha, which no straight colour can
  express: the division gives a component above 1, so a key never matches it. Where alpha is
  above zero, a matrix with no offset whose alpha row reads only alpha, grayscale for one, still
  gives the colour it would give on the premultiplied texel directly. A texel with zero alpha and
  some colour, which only additive content leaves behind, loses that colour under any effect,
  because the division has nothing to divide by.

  **Controls**, each restored by hash (`controlAC.txt`, `controlB.txt`):
  - without the division, both rows go red (11 896 / 48 and 11 424 / 154);
  - with the key left out of `noEffect`, only row 2 goes red (3 072 / 200);
  - without the UI branch, the style scene goes red (11 757 / 49): the double premultiply the
    stop was there to prevent.

  **Pins:** the two goldens and their invariant, and the T1 test "an image style carries its
  tile's premultiplied bit into its instance", which goes red when `params1.y` is dropped
  (`controlParams1.log`). `tests/aborts/premultipliedStyledImage` went with the stop. The bit
  rides the instance, beside grayscale, because the UI program reads per-image state per
  instance, as GPUI's sprite carries `grayscale` and `opacity` (`shaders.wgsl:1290-1310`). A
  per-draw lane would split a UI run at every change for a fact the instance already holds.

  ```ts
  // a translucent 3D preview, greyed while inactive: before, its edges darkened by their alpha
  const preview = s.sprite(tile(forward.colorTarget.asTexture(), 256, 256).premultiplied());
  preview.setColorMatrix(colorMatrixGrayscale(1.0));

  // the same target as a rounded, greyed thumbnail: before, an image style on it stopped
  const thumb = s.sprite(tile(forward.colorTarget.asTexture(), 256, 256).premultiplied());
  thumb.setImageStyle(imageStyle(uniformRadii(8.0), true, ObjectFit.Cover));
  ```

  An image style and a colour effect on one node compose, through the UI program's effect (I
  below).
- **A colour effect across a target (2026-10-03, found by G's golden run).** `beginTarget` reset
  `curEffect` and `endTarget` restored it, but neither touched `curHasEffect`, nor the matrix,
  add and key that `setEffect` compares against. That left two failures:
  - After a target, the parent recorded with its old effect row while believing it had none, so
    its next `setEffect` to the identity returned early.
  - Inside a target, a `setEffect` equal to the parent's was taken for a repeat and dropped.

  `filter/afterTintedSibling` had recorded the first. Its filter composite drew with the previous
  sibling's grayscale, so the yellow subject blurred grey: 5 388 inked pixels, none yellow. Until
  G, the double premultiply also darkened it.

  Both brackets now set the whole effect state, through `draw.ms` `clearEffect` and
  `restoreEffect`. `restoreEffect` reads the row the way `resumePaint` already did, and since the
  design pass `resumePaint` and `reopenLast` call it too. Whether an effect is set is no longer a
  field of its own: it is `curEffect != NO_EFFECT`, in the context and in `PaintIndex`. What is
  left cached, the matrix, add and key `setEffect` compares against, is written only where the
  row is.

  The defect pass found a second fault beside it. A target nested past the eight save slots was
  recorded into its parent, as P1 chose, but its `endTarget` popped the real target around it, so
  every bracket outside ended one level early. `c7a1ff2` paired the brackets. Red before: the T1
  test "a target nested past the save slots ends its own bracket, not the one around it" read
  depth 0 where 1 is right. H then removed the limit itself.

  **Red before:** the T1 tests "a colour effect drawn before a target does not reach the draw
  after it" and "a colour effect inside a target is recorded when the draw before the target had
  it" failed at their effect asserts.

  **Re-recording the golden.** A check that does not read its hash came first
  (`out/tmp/premultEffect/yellow.txt`): 4 156 yellow pixels and none grey, against none yellow
  and 5 388 grey before. At (100, 70) the capture reads 233, 191, 85, against 234, 192, 84 for the
  subject composited once over DARK at coverage 0.91. A tree with this fix and without G captures
  the same bytes, so the fix stands as its own commit.

  **Measured on the final tree**, after the design pass's fixes, BUILD `5791eadd`, D3D11 only:
  every golden is 80 / 80, the pair invariants pass on the committed goldens
  (`out/tmp/premultEffect/invariants.committed.txt`), and T0/T1 run 1132 of 1132. WebGL2 and the
  gates ran after void3d's M25 land: the last receipt in this section.
- **H, three paths that logged or stayed silent (2026-10-03).** The coordinator decided them by
  "fail loud" and the references. Each has a red-before pin and its own commit.
  - **An `endTarget` with no target open stops by name** (`draw.ms` `stopOnEndWithoutTarget`).
    Heaps' `popTarget` throws "popTarget() with no matching pushTarget()" (`h3d/Engine.hx:366-369`),
    and the door's own end-with-none stop (A) already does the same. The pin
    `tests/aborts/endTargetWithoutBegin` ran to its end before the fix.
  - **An image style on a node with a colour matrix, `colorAdd` or `colorKey`**: H first made it
    stop by name (`86b96f1`), on a reading that no reference draws both on one draw. That reading
    was wrong. h2d's `Graphics` fills a rounded rect with a tile (`h2d/Graphics.hx:489`
    `beginTileFill`, `:612` `drawRoundedRect`), and a `Graphics` is a `Drawable` whose colour
    effects apply to every draw. So I composes it. The pin `tests/aborts/styledImageWithEffect`
    logged and dropped the image before H, and is the proof that it is no longer dropped. Its
    scenario lives on as a T1 test.
  - **A target nested past eight grows the save slots** instead of recording into its parent.
    Heaps' target stack is unbounded and recycles its nodes (`h3d/Engine.hx:332-345`). The arrays
    grow one level the first time a frame nests that deep, and keep it, which is the streams' rule
    ("Frame shape"). So a frame that nests no deeper than one before it allocates nothing, and the
    allocation stage reads the growth as stream growth, not a fresh array.
    - The C replay keeps eight levels for its size stack, because target blocks are flat by
      construction, and it stops by name if one ever nests.
    - The cross-language layout check no longer compares a limit the recorder does not have.
    - T1 "nine nested targets each record their own block" read depth 8 and 17 target commands
      before the fix, and 9 and 19 after.

  **Measured** on BUILD `5791eadd`, D3D11 only: every golden is 80 / 80, T0/T1 run 1133 of 1133,
  and both abort pins stop with their message (`out/tmp/failLoud/`). The gates ran with the rest
  after M25: the last receipt in this section.
- **I, a colour effect on every UI kind, and filter targets past sixteen (2026-10-03).** The
  coordinator decided both from h2d.
  - **Colour effects compose.** h2d's `Text` and `Graphics` extend `Drawable`
    (`h2d/Text.hx:60`, `h2d/Graphics.hx:163`), whose `colorMatrix` and `colorAdd` are shaders on
    every draw of the object (`h2d/Drawable.hx:60-72`, `:121-130`). So text and shapes take the
    effect in Heaps, and a box style, an underline, a selection, a label's runs, selection and
    caret, and an image style now do too.
    - The mechanism is the existing effect row and the command's `CMD_EFFECT` lane, which the UI
      program's commands now carry (`displayList.ms` `recordUiDraw`).
    - The replay fills the UI program's fragment block with the row's matrix, add and key
      (`batcher.c` `drawUiRun`). That block is `ui_fx`, the former `ui_text`, so a UI draw still
      applies two blocks.
    - The fragment's `withEffect` reads each output's straight colour, applies the key, the
      matrix and the add, and premultiplies again. This is the colour pipeline's order, in float
      and before the blend, so no 8-bit rounding enters it.
    - A pixel outside every shape stays empty, as h2d draws no geometry there.
    - A plain rect or label under an effect keeps the colour pipeline, as before, so no other
      golden moved.
  - **Red before:** each kind has a T1 test that went red on `e79759c`:
    - the box, underline and selection tests read no UI instance;
    - the label test read no selection span;
    - the image style test stopped at H's stop.

    The golden `prim/effectOnUi` draws every kind plain and under a grayscale matrix on a grey
    ground. `tests/golden/invariants.ms` holds each grey pixel to its twin's luma within 2 levels,
    the rounding of two stacked blends; the worst measured is 1.44. Control: with the replay
    leaving the effect off, 16 050 channel values miss, worst 135.
  - **The filter target pool grows past sixteen**, as h2d's `pushFilter` appends a filter stack
    entry when it runs out (`h2d/RenderContext.hx:316-322`) and takes its targets from
    `allocTarget` (`:208`).
    - A target is made only when no free one of its size is left, and it stays pooled, so a frame
      that needs no more than any before it allocates none.
    - sokol's own pool still bounds it, and running out stops by name (`stopOnRefusedTarget`).
    - The golden `filter/manyTargets` draws eighteen group-opacity filters. Before the fix, nodes
      16 and 17 drew unfiltered and differed from node 0 in 2 172 channel values each, and the
      counters read 16 targets.
    - After the fix, all eighteen are byte-identical. The first one's overlap reads 48, 107, 137,
      against 48, 107, 136 for one composite at alpha 0.5, a check that does not read the hash.

  ```ts
  // a disabled card: before, its rounded border and fill were dropped with one log line
  card.setBoxStyle(BoxStyle.create(uniformRadii(6.0), uniformBorders(1.0), border));
  card.setColorMatrix(colorMatrixGrayscale(1.0));
  // a read-only editor line: before, its runs, selection and caret vanished under the effect
  code.setTextRuns(runs).setColorMatrix(colorMatrixGrayscale(0.6));
  ```

  **Measured** on BUILD `5791eadd`, D3D11 only: every golden is 82 / 82, every pair invariant
  passes on the committed goldens, and T0/T1 run 1135 of 1135 (`out/tmp/failLoud/`).

**Measured on the tip `7cf741d`, BUILD `5791eadd`, shared box:** `sh scripts/gate.sh --web` ran
every code stage green: 1118 tests plus 299 isolated, D3D11 78/78, WebGL2 56 identical / 18
bounded / the same four known-red, 107 frame functions / 245 callees, 16 PENDING; web builds
2 344 744 / 2 116 929 B, 13 023 B under the D1 follow-ups' on both backends. Its one red was the
record stage: TESTING.md's WebGL2 row did not yet count the new golden. The row was corrected in
the docs commit and checked again against the same run (the gate's own claim string, and
`tests/record/check.ms`: 0 off). `sh scripts/gate3d.sh` on the same tip is GREEN with its device
skip. Logs: `out/tmp/closureGate2/`.

**Measured on `9703390`, tree `3e114386f394`, BUILD `5791eadd`, shared box — the run G, H and I
were owed once M25 landed:** `sh scripts/gate.sh --web` ran every code stage green: 1145 tests
plus 299 isolated, D3D11 82/82, WebGL2 60 identical / 18 bounded / the same four known-red, 107
frame functions / 245 callees, 16 PENDING; web builds 2 359 062 / 2 131 238 B. Its one red was
the record stage: TESTING.md's WebGL2 row did not yet count the four new goldens. The row was
corrected in a docs commit (`a8b80fb`, no code) and checked against the same run (the gate's own
claim string, and `tests/record/check.ms`: 0 off). `sh scripts/gate3d.sh` ran after that docs
commit on the same code and is GREEN, 240 stages with its device SKIP, 182 aborts. The land's
no-op rebase re-ran `gate.sh --web` on `cffb689` and is GREEN with 0 FAIL and the row PASS, every
number the same (`out/tmp/finalGate/gate.land.log`). Logs: `out/tmp/finalGate/`.

- **J, two remaining native boundary gaps (resumed after the 0.3.0 migration).** The published
  `src/sokol/bridge.h` no longer advertises begin/commit; `door.c` alone declares its internal
  platform calls. Their implementations stay in `bridge.c` and `bridgeEmbed.m`, preserving the
  environment-format check, present and void2d's commit hook. This is a public-header boundary,
  not an unforgeable linker fence against C code that invents private `extern` declarations.
  Heaps' Engine owns sequencing and the existing GPU door is Void's same owner; no second pass
  state or runtime wrapper is introduced.

  **Red before:** both real C consumers naming the bridge entries compiled against the
  `2bd0601` header. After removal they are rejected as undeclared identifiers, while a consumer
  using `doorBeginScreenPass`/`doorEndPass`/`doorCommit` compiles. `tests/compile/bridgePass.c`
  and `scripts/checkBridgePass.sh` enforce that boundary in `gate.sh`, not by reading source text.

  **Short bindings descriptors now stop by name** in `src/void3d/gpu3d.c` `gpu3dApplyBindings`,
  before any word is read or bindings are changed, with the same diagnostic shape as door A.
  The public Span consumer in `tests/aborts3d/gpu3dShortBindingsDescriptor.ms` returned normally
  before the fix; after it, the process terminates with `applyBindings descriptor holds 8 of
  9 words`. The minimum-length contract and valid binding path stay unchanged.
  `gpu3d.c` is void3d's file; the coordinator explicitly granted it to this mechanical slice.

- **RenderTarget reference owner, NEON item 2 prerequisite.** A material-side holder needs
  one target identity through resize, not a value copy of handles that have been destroyed.
  This reuses F and void3d M25's owner model; `target.ms` owns the API and state transitions.
  Heaps' [Texture.resize](https://github.com/HeapsIO/heaps/blob/b9aa6dcbb2307b03c1f435e87bdb036060100984/h3d/mat/Texture.hx#L237-L253)
  and three's [RenderTarget.setSize](https://github.com/mrdoob/three.js/blob/master/src/core/RenderTarget.js)
  keep the object and replace its GPU storage. **W:** same-size resize follows three's no-op
  and the existing Void behaviour, not Heaps' unconditional disposal: it avoids unnecessary
  allocation and preserves valid contents. **W:** close is terminal, as M25's is, instead of
  Heaps' reallocation-capable dispose; no alias resurrects an owner its parent already closed.

  **Measured on source tree `3b8c7e0c2d840ae656b6180d8b15ec1f5d244a16`, BUILD `4573591e`,
  msc 0.3.0, D3D11:** the old native value consumer resized its owner to 32x24 while its holder
  still read 16x16 and a dead image (exit 1). The reference consumer reads 32x24 and the same
  live image through both aliases (exit 0). `tests/integration/targetOwner.ms` proves five
  real sampled frames, old image/view retirement, same-size reuse, exact closure of one image
  and two views, independent-owner survival and older-epoch same-size adoption.
  `targetPresetEpoch.ms` proves both presets keep all six target owners, reallocate their
  storage and refresh their pass attachments. These generation-write controls leave the old
  ids alive, then clean them up explicitly: they are not actual device loss.
  Closed-empty resize, terminal color/depth borrows, immediate drawing through a closed owner,
  zero-size refusal and real GPU pool refusal each terminate nonzero with their named error;
  both gates run every case. The shared mutable NO_TARGET sentinel and unreachable empty
  filter-result branches are gone. `sceneTarget.ms` still passes nine native frames.
  Logs: `out/tmp/targetOwner/`; final full-chain results are in the review.

- **Optional View paint, NEON item 8 (`dabfdbc`, `e5602f5`).** A Group becomes a drawing node
   in place: `setBackground` / `setBoxStyle` promote, `clearBackground` demotes and frees the
   box style, any other kind stops by name, and the frame blanks a transparent fill with no
   border and no shadow. **Dispositions:** W — same-size promotion is Void's one-row model, not
   Heaps' lazy ScaleGrid child (`Flow.hx:1115`), so layout needs no sync; W — promotion starts
   and clearing resets a transparent fill, where Heaps' `Texture.resize`-era dispose allows
   realloc; N — scheduling stays the caller's, as RN's `formsView` is a derived trait, not a
   redraw policy. Pins: T0 promotion identity/colour/reuse and blank cull; native
   `tests/integration/viewPaint.ms` pixels, zero-draw and kind-stop. The 2×-X phantom that
   started this was the OS minimum client width, not placement: the consumer now refuses a
   short framebuffer by name.

  Source and native consumer proof do not certify WebGL2/GLES3 or genuine context loss.
  Raw texture-view ids still change with storage; checked material rebinding is void3d's M27
  (`addTargetTexture`, VOID3D.md "M27 as built"), which reads the owner's view at each bind. Full-chain gate and design verdict are recorded
  in `REVIEWS.md`; this is not a P5/P6 completion or a land receipt.

- **The open pass's attachment views (`b2570ef`, written by void3d's M27 under the
  coordinator's handover with the human's word, 2026-10-05).** `door.c` records the colour and
  depth views of the offscreen pass it begins, on both paths (`doorBeginPass` and
  `doorBeginColorPass`), and clears them at `endPass`; `passAttachesView` and
  `RenderTarget.isAttachedToOpenPass` answer whether a target's attachment view is being written,
  only for a target of the current context (a stale id may name a new object). void3d stops a
  material sampling that target by name; void2d's own sprites take raw views and are not checked.
  Pins: `tests/integration/targetTexture.ms` opens a pass on each path and checks the answer
  before and after `endPass`; with the stop removed, debug sokol panics
  (`VALIDATE_ABND_TEXTURE_BINDING_VS_COLOR_ATTACHMENT`) and a release build draws on, wrong.

A second compiler card came out of E: `.inbox/compiler/2026-10-01-index-on-a-struct-passes-the-
checker.md`, a struct indexed like an array passes `msc check` and reads garbage; it surfaced when
`m[0]` survived the move to `Mat4` in `effectCheck.ms`.

## Open

- **Public reference-owner fields remain writable**: both a pipeline cache and a RenderTarget
  expose their state. `closed = false` can reopen an owner; dropping a cache's live tables or
  replacing a target's handles bypasses its lifecycle. This inherits F/M25's public-field
  limitation; the standing readonly-field compiler card is
  `2026-09-27-readonly-interface-field-unresolved-type.md`, alongside PENDING3D
  `store-serial-writable`. That compiler card was not revalidated by this slice.
  The API contract assumes state changes through the owning module, not forged owner fields;
  this is not an opaque or unforgeable owner boundary.
- **WebGPU uniform budget**: two uniform blocks per draw cost 512 B of the per-frame uniform buffer on WebGPU and Metal. Measure at P1 and fold what does not change per draw into fewer blocks if it bites.
- Reference facts were read from source, not benchmarked. Instance sizes and the one-draw-call claim are from planned layouts, not measured — P2's exit is where they become numbers.
- Non-uniform scale on SDF boxes and `erf` shadows is approximated by one antialiasing width, `1 / sqrt(sx * sy)` in local units (`aaWidthForAffine`, the vertex shader's `uiVs`). For a box edge the true device ramp has slope `sx` or `sy`, so the worst coverage error along an edge is `0.5 * (1 - sqrt(min(sx, sy) / max(sx, sy)))`: 0.146 at 2:1, 0.211 at 3:1, 0.25 at 4:1, always under 0.5, zero when uniform. Corners exceed that prediction by up to about 0.03 (below). Measured in T0 on the pixels of `prim/aaNonUniformBox` against the supersampled oracle (`devicePixelCoverage`, independent of `sdf.ms`): edges 0.1405 / 0.1950 / 0.1950 / 0.2271 for 2:1, 3:1, 1:3 and 4:1 rotated 20 degrees against predicted 0.1464 / 0.2113 / 0.2113 / 0.25, corners 0.148 / 0.207 / 0.207 / 0.277; the exact per-axis slope reads at most 0.027 on a dense sweep of the same geometry, so the oracle is not the cause. The blurred `erf` shadow is evaluated entirely in local space and is exact under any scale; only the hard-edge fill, the border and a hard shadow use the width. Scene2D's `trs2d` cannot shear and Neon never sets `scaleX`, so no consumer sees the larger errors. Makepad's `antialias(p)` (`draw/src/shader/sdf.rs:166-168`, read) is one isotropic width too, so bounding it is on-reference; the exact per-edge slope (`1 / |A^-T n|`, or `fwidth`) is NEW MECHANISM relative to both references and is not built. The T3 capture `prim/aaNonUniformBox` judges each box inside [predicted - 0.05, predicted + 0.02] on its edges; only the 4:1 box lies outside the error of an arithmetic-mean width, so it is the one that convicts the shader, and the 2:1 and 3:1 boxes confirm the bound without separating the two formulas. The capture is owed: the scene and `runAffineFill` in `tests/oracle/captureCheck.ms` exist, the PNG does not (`tests/PENDING.md sdf-non-uniform-bound`).
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
