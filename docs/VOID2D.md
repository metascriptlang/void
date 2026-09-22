# void2d — Unified 2D / UI Render Layer

Void's 2D layer: draw the **same pixels on every platform** (Metal / D3D11 / GL / WebGPU / WebGL2) through one MetaScript codebase. This is the layer that makes Neon's UI rendering "special" — instead of binding to per-OS native widgets, an opted-in app can render its UI through Void and get identical output everywhere.

**This doc is the entry point.** It holds the conclusions. The evidence lives in four reference docs, each read from source with `file:line` citations:

| Doc | Role |
|---|---|
| [HEAPS.md](HEAPS.md) | **The model.** Heaps `h2d`: the interface and semantics void2d keeps. |
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
- **Atlas**: coverage pages and colour pages, 1024², a new page when full (G); 1 px gutter; a CPU mirror per page, dirty pages uploaded once per frame (sokol replaces whole images); ref-counted tiles; **a repack never moves a live tile** (Gh). Four single-channel planes per RGBA page (M) is weighed at P3.
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
3. **Fractional DPI is the norm**, since `devicePixelRatio` is routinely 1.25 or 1.5. The truncation defect in `scene.ms:89` therefore hurts the web target hardest.
4. **No OS text system at all.** GPUI's web path is cosmic-text plus a canvas fallback for emoji, which is a third set of pixels beside its macOS and Windows output. Void owns one rasterizer everywhere; this is guardrail 9 and the reason the glyph layer cannot be deferred.
5. **wasm size is a shipping constraint, not a nicety** — hence guardrail 6 and the per-module measurement in the budget.
6. Frames are driven by `requestAnimationFrame`, re-armed only when something is dirty (`gpui_web/src/window.rs:918`). That is the host's job, and it is the same "dirty → draw, else nothing" contract as the desktop hosts.

### Instance sizes

Today a quad is 6 vertices × 8 floats = **192 B**, re-transformed on the CPU every frame, with no AA of its own. With per-instance attributes (`SG_VERTEXSTEP_PER_INSTANCE`, core in GLES3/WebGL2):

| Instance | Payload | Size |
|---|---|---|
| Sprite pipeline | affine 4 + origin/size 4 + uv 4 + colour 4 (float) | **64 B, measured** |
| UI pipeline (single stride for all modes) | affine 4, origin/size 4, uv-or-radii 4, border widths 4, mode/params 4, gradient/shadow params 4 (all `FLOAT4`), three colours as `UBYTE4N` | **108 B, measured** |

**Measured 2026-09-21, not estimated.** Both numbers now come from `sizeof` on the structs in
`batcher.c` that the vertex layout is built from, checked against the offsets
`src/void2d/instance.ms` declares — at setup by `void2dInstanceLayoutCheck`, and with no GPU at
all by `src/test/instanceLayoutCheck.ms`. Moving one offset on one side turns that file red.

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

- ~~**Atlas-full drops a *different* set of glyphs on every run**~~ — **closed in P1, as a holding fix**; P3 still removes the class with fontstash. There was no `FONS_ATLAS_FULL` handler, so when the fixed 512² atlas filled, fontstash asked once, retried once and dropped the glyph — and *which* glyphs were dropped varied between runs of the same binary: three distinct outputs in ten, worst pair 28 740 of 80 000 pixels (35.9%) at max delta 207. The handler now doubles the atlas, height first because the packer fills row by row, up to a 2048 cap chosen as the smallest guaranteed maximum texture size across the backends this ships on; `fonsExpandAtlas` preserves the glyphs already placed and lets the retry succeed. **Re-measured: ten runs, one output**, and `regress/atlasFull` is a golden with no tolerance. The second half, `fons_resize` leaking the old image and view, is closed too and was made a number first: one capture of that one scene resized twice and left **3 atlas images alive, 0 freed**, against sokol's 128-slot pools. They cannot be destroyed on the spot — commands already recorded in that frame carry the old view id and the replay has not run — so they are retired and freed at the top of the next frame, the same frame-linear discipline the filter targets use. After the fix the same run reads **3 made, 2 freed, 1 alive**, and `void2dAtlasImagesAlive()` exposes it. A guarded `malloc` went in beside it: the mirror allocation was unchecked and `memset` followed it immediately.
- ~~**At most ~126 Labels/Graphics render**~~ — **closed in P1** (`747127f`). Each Label and Graphics owned an `sg_buffer` against sokol's default pool of 128. One growing vertex buffer replaced them: `ui.buffersAlive` is **2** at 10 000 labels and constant in the node count, `ui.retainedNodes` is 10 000, and the golden `regress/nodeCap` now shows all 200 labels instead of 0–125. The `buffersRefused` counter was deleted with the defect — nothing is refused any more.
- ~~**Node filters do not work at all, and take the whole frame with them.**~~ — **closed in P1.** `drawFiltered` opened a render-target pass inside the swapchain pass; a debug build tripped `Assertion failed: !_sg.cur_pass.valid` and a release build presented only the clear colour. The second half of that was worse than recorded: the nested `begin2d` called `resetList()`, so it did not merely fail to draw the filtered node, it **erased the frame recorded so far** — which is why the siblings before and after vanished too. Both are gone: a filter now brackets a region of the display list, the block is moved out of the swapchain list when it closes, and the replay runs every target pass before the one swapchain pass. Nesting is correct by construction because targets close LIFO, so an inner target's block is appended ahead of the outer one that samples it — asserted in `displayList.ms`, not just hoped for. Five goldens on: `filter/blur`, `filter/glow`, `filter/dropShadow`, `filter/groupOpacity`, `regress/filterNestedPass`, all five re-run in a debug build with the validation layer linked.
- ~~**Filter semantics differ from h2d**~~ — **closed in P1**, all five: the node itself enters the target (`drawContent(n, ...)`, not a loop over `n.children`); alpha is applied once, because the filter takes the node's alpha over for the length of the target instead of letting `drawContent` multiply it in again; the target is object-local through a filter matrix, which is a translation the emitter subtracts as it records, so the subtree keeps its single sync instead of being walked and re-synced twice a frame; bounds are clipped to the viewport; and targets come from a frame-linear pool (`h3d/impl/TextureCache.hx`) capped at 16, so no node owns a texture any more. The kernel is guardrail 3's: downsample by 2^k, then blur at a one-texel step. The old code passed `radius / size` as the tap step, which put the outer taps at 3.23 × radius texels — at radius 5 it sampled 16 texels away, so it combed rather than blurred, and that is why the demo asked for 5 to get a 16-pixel spread. One implementation serves both the node filter and `filter.ms`'s manual helper; two would drift. **A sixth defect turned up while measuring** and is closed with them: a render target is premultiplied, so `texel * color` scaled only its alpha and left rgb at full strength — fading a filtered subtree changed its coverage and not its colour. `filter/groupOpacity` was read pixel by pixel against both models: without the filter the overlap measures (104,125,148) against a double-blend prediction of (104,124,148); with it, (48,107,137) against a single-composite prediction of (48,107,136).
- ~~**Fractional DPI puts every glyph off-grid**~~ — **closed in P1** (`747127f`). `begin2d` takes a float logical size, so `Scene.presentAt` no longer truncates a 1.25 or 1.5 ratio to an integer. The golden `regress/dpiTruncation` moved: the rule now reaches the true right edge. `text/code13Dpi125`, `text/code13Dpi150`, `snap/hairlineDpi125` and `snap/hairlineDpi150` did **not** move — glyph origins are still rounded to integers inside fontstash, which is a separate defect listed under **P3**.
- ~~**Samplers are hard-wired REPEAT**~~ — **closed in P1**, its own commit as the phase asked. Four samplers now, indexed by `smooth * 2 + tileWrap`, with **clamp as the default**: a Tile is a sub-rect of an atlas page, so REPEAT on one that does not fill its page wraps a neighbour's pixels in at the seam. `smooth` became h2d's tri-state (`Smooth.Inherit/Off/On`) resolved against a new `Scene.defaultSmooth`, which is **linear** — h2d's own default is nearest (`h2d/RenderContext.hx:52`) and HEAPS.md "Do not copy from h2d" rejects it. Six goldens moved, all at max delta ≤ 2: `regress/samplerRepeat`, `image/subFlip` and the four `demo/` frames. Two goldens were **added**, because `tileWrap` and the scene default were new surface with nothing able to fail on them: `image/tileWrap` draws the same tile at u1 = 3 with the flag off and on, so clamp stretches the edge and repeat tiles 3×3; `image/sceneSmooth` puts an inheriting sprite beside an overriding one under a scene whose default is nearest. Noted against `regress/samplerRepeat`: it is a **weak scene**. It was authored at P0 to record this defect, but the sheet's left and right edges are both near-black, so REPEAT bled in a colour almost equal to the clamped one — 448 pixels at max delta 2, invisible to a reader of the diff. Zero tolerance means it still fails on a revert, so it was kept as the defect's own site; `image/tileWrap` is the scene that actually shows the mechanism.
- ~~**Per-frame vertex cap**~~ — **closed in P1** (`747127f`). The fixed 65 536-vertex dynamic buffer grows by `max(2×)` instead, with a 192 MiB cap and a dropped frame plus an error on stderr past it. GPUI caps its native-only instance buffer at 256 MiB; Void's one allocation carries vertices plus both instance streams and must also run on wasm32, WebGL2 and mobile, so it deliberately keeps 64 MiB below that reference ceiling rather than letting one frame consume the full amount. This is a fail-loud ceiling, not a working-set target. The golden `regress/vertexCap` moved: the grid fills the canvas. Re-measured in a **debug** build, where sokol's validation layer is linked, both `regress/vertexCap` and `regress/nodeCap` capture normally — the `VALIDATION_FAILED` panic at `sokol_gfx.h:23960` is gone, so `tests/PENDING.md debug-abort:vertex-cap` was deleted.
- ~~**GPU calls are issued while the tree is walked**; a text change destroys and recreates its GPU buffer~~ — **closed in P1** (`747127f`). The walk's only output is the command, effect and vertex streams; `void2dReplay` is the single draw-issuing function and runs after the walk has ended. No node owns a GPU buffer, so a text change rewrites a `float32[]` on the node and nothing else. **The T1 assertion that holds it exists now** — `tests/displayList/snapshot.ms`, "the walk records and uploads nothing" — and the three `tests/PENDING.md` rows that stood in for it were deleted in the same commit that wrote it. What the walk still does is *create resources*: a first-of-its-size filter target and an atlas growth both reach `sg_make_image`. That is stated in the exit table rather than glossed.
- ~~**`add` and `addChild` hand back the parent, not the node that was added**~~ — **found and closed in P1**, by writing a T1 scene the way a Heaps user would. `addChild` returned `n`, and `Scene.add` is `s.root.addChild(c)`, so `s.add(node)` returned the **scene root**. `const n = s.add(x); n.alpha = 0.5;` — the h2d idiom, `new Bitmap(tile, parent)` with the handle kept — configured the root instead, in silence, and `s.add(a).addChild(b)` made `b` a sibling of `a` rather than its child. Measured before the fix with a three-step probe: a scalar written through the handle left the tree's copy unchanged, and one `addChild` through it took the root from one child to two. Nothing in the tree was ever wrong *at rest*, because every scene in this repo builds a node fully and only then adds it — which is why 45 goldens and a demo never noticed. Both functions return the child now, `src/test/nodeCheck.ms` pins it, and the T1 `order` snapshot is the evidence: the nested child moved from world x 1.00 to 21.00, because it finally inherits its parent's transform.
- ~~**A rotated Mask clips to its AABB**, and culling tests the viewport rather than the active clip~~ — **closed in P2**. The command carries the Mask's two projection intervals, each vertex produces four signed edge distances, and every fragment pipeline discards outside them; the AABB remains only as a coarse hardware scissor. T1 `rotatedClip` pins the planes, `active-clip culling drops rows` proves off-clip instances are absent, and T2 `clip/rotatedMask` pins the pixels.
- **Integer glyph origins and rounded advances** (`fontstash.h:1230-1244`, `:1314`), `kern`-only metrics, `split(" ")` wrapping (`text.ms:19`), no `textWidth`, no fallback, ≤ 16 fonts (`batcher.c:35`), the atlas expanded R8→RGBA on the CPU and fully re-uploaded on any new glyph (`batcher.c:345-360`, `:207-216`). A glyph first needed in a second render-target bracket is one frame late because sokol permits only one atlas upload per frame; `tests/PENDING.md` carries the transient. — **P3**.
- The h2d surface still missing — `parent`, `TileGroup`, `Mask.scrollX/Y`, text metrics — is listed in [HEAPS.md](HEAPS.md). `Tile.dx/dy`, `center()` / `setCenterRatio()` and uniform node pivots closed in **P2**; text metrics are **P3**, the rest **P5**.
- **Idle costs a full walk and draw**: `Scene.present` runs every frame and nothing knows whether the tree changed. — **P5**.
- **Entry points declare `function main()` and nothing calls it.** Not a platform defect: `~/metascript/docs/CODE-STYLE.md` section 9 states the rule — "Nothing calls `main()`" — so an entry that ends at `return 0; }` builds a binary which exits at once everywhere, and a wasm module with the renderer linked out. `src/examples/mainSokol2d.ms` was fixed at P0: its WebGPU wasm was 48 064 B and is now 509 672 B, its WebGL2 wasm 111 522 B and now 410 724 B. `mainSokol.ms`, `mainCampfire.ms`, `iosEntryAnim.ms` and `iosEmbedEntry.ms` were void3d's entries and were left to that arc, which fixed all four at `e4a1a05`; the `entry-main-not-called` PENDING row graduated when that reached `main` in `c2019b5` and was deleted in the commit that rebased onto it. — **closed everywhere: void2d at P0, the other four by the void3d arc.**

## Guardrails

1. **Draw order.** Painter's order stays, and the unified UI pipeline makes it batch. BoundsTree reordering is not planned: GPUI rebuilds it from empty every frame, and it is O(log n) per primitive against the 1M-node target in [SCENE-SCALE.md](SCENE-SCALE.md). The cheap form is kept: `TileGroup`, and a node flag asserting that children do not overlap. No depth buffer for 2D order. Revisit only if measurements of real Neon UI show state-change draws dominating.
2. **Node2D width.** `Node2D` carries 71 fields. Box style and text runs are read only when emitting, so they live in side tables — the side-table bar in SCENE-SCALE.md.
3. **Filters stay — and get fixed.** Render-target filters on arbitrary subtrees are h2d semantics; the `erf` shadow is a fast path beside them. The blur is corrected: downsample by 2^k then blur at a 1-texel step, or dual-Kawase.
4. **Paths: no MSAA intermediate, no baked fringe.** A pass break per path batch is a full tile store/load on mobile GPUs; a baked fringe scales with the node. Store the edge normal per fringe vertex and extrude in the vertex shader by `1px / scale`.
5. **MSAA is a knob, not a dependency.** Expose `sample_count` for iOS/Android instead of hard-coding 1. Analytic coverage is still required: the embed host owns the framebuffer and its sample count.
6. **Text is where the weight goes, so it is modular.** The glyph layer goes in by default. The shaper, a hinting rasterizer, colour emoji, the SDF text path, procedural sprite glyphs and the SVG rasterizer are compile-time modules; CJK and emoji families load on a real miss. A game build pays for none of them. Measure the wasm delta of each.
7. **No ClearType.**
8. **Pay for what you use.** Snapping, the pixel-exact text regime and the UI pipeline engage only for nodes that use them; a sprite-only scene must not regress at any step.
9. **Same pixels on every platform.** No OS text system, no per-platform text path (Makepad's slug on macOS/web, SDF on Windows), no runtime shader generation. **This is a number: 37/37 scenes byte-identical on D3D11 at P0, 48/48 at P1 and 67/67 at P2, with six other surfaces reported as SKIP with a reason** — GLES3 desktop, Metal macOS, Metal iOS, GLES3 Android, WebGPU, WebGL2. One golden set authored on D3D11, every backend compared against it, a pass rate per backend ([TESTING.md](TESTING.md) "Guardrail 9"); the full five-backend run is P3. What each missing readback costs, and what browser conformance needs beyond a driver, is written down there rather than guessed at.

## AUDIT: corpus, oracle, QC and architecture at `89a184e`

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

**Findings, in closure order:**

1. ~~**The mixed void3d → void2d frame boundary was unproved and wrong.**~~ **Closed after
   this audit.** `renderer.endFrame` now imports the bridge's shared `commit`; the duplicate
   `gpu3dCommit` declaration, wrapper and direct `sg_commit` site are gone. The permanent
   `tests/integration/mixedFrame.ms` capture draws the cube and a void2d overlay in one
   swapchain pass, commits once, starts a second frame, and requires the two fixed-state
   captures to match. Its per-frame void2d draw-count assertion is the regression guard:
   the old path left that count accumulating because `void2dFrameEnd` never ran.
2. **Guardrail 9 is still a D3D11 claim, not a platform claim.** The six other surfaces are
   explicit SKIPs. The honesty is good; the risk remains until at least one GLES3 path runs the
   same 56 images and the browser paths have a driver.
3. **The performance gate protects shape, not timing.** It correctly gates one draw, buffer
   count, instance count, upload bytes and zero dropped frames. `tests/bench/baseline.json`
   still has `taken.load` and `taken.context` as null. The observed 18.6 ms standalone /
   10.8 ms in-gate spread is evidence that those fields are necessary, not a phase-end result;
   P2 makes no new timing claim until the controlled interleaved A/B fills them.
4. ~~**The ledgers had drifted behind the executable evidence.**~~ **Corrected after this
   audit.** `tests/PENDING.md` now says its five rows are the oracles still unwired rather
   than claiming none exists; `docs/TESTING.md` records both coverage oracles, their capture
   checks and the current 56-scene D3D11 count.
5. ~~**Reserved UI modes need production reachability checks when they land.**~~ **Closed
   during P2.** T1 `gradients`, `imageStyle` and `textPrimitives` now start at retained nodes,
   pass through the production emitter and pin their effect or instance lanes; raw-mode tests
   remain only the lower-level layout and batching check.

The shared-commit defect is closed without a second renderer or a new batching mechanism.
The next P2 correctness boundary is the rotated-Mask clip: it is the still-open half of the
37° card exit row. Non-D3D11 conformance remains P3 work; the controlled timing A/B remains
a P2 phase-end measurement rather than a number minted by an incidental gate run.

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
today** (2026-09-20, at `6a997ee`). This is the table a phase is measured against now.

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
`6a997ee` and `544ea4a`, six alternating pairs each: ui **19.95** (19.69–20.30) against **19.86**
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

**(c) P2, phase-end measurement at `681fed1`** (2026-09-22). The machine read 11.77% CPU
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
- `tests/golden/d3d11/` — **37 scenes** at P0, **48** after P1 turned the filter rows on, and **67** after P2 added the instanced primitives and their boundary cases.
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

**Defects closed.** The pivot inconsistency and missing `Tile.dx/dy`; the rotated-Mask scissor AABB; culling against the viewport instead of the clip; per-vertex sRGB gradients. Not on the defect list but closed here: box-shaped UI stops depending on MSAA for its antialiasing, which today is on only for the sokol_app entry (`bridge.c:47`) and off on iOS, Android and embed — paths themselves wait for P6.
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
The 67 expectations live in table order beside the scene table; a pixel-identical draw-call
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
- `Font { family, weight, style, features, fallbacks }` from bytes; the Ghostty collection model — ordered faces per style, deferred faces, explicit-versus-fallback presentation, a codepoint→face map that caches misses, whole-grapheme selection, fallback size harmonisation, synthetic bold and italic, CJK and emoji families loaded on a real miss.
- Gamma and contrast per fragment with GPUI's function and 13-row table.
- Decoration position and thickness from `post` / `OS_2` with broken-table fallbacks.
- The text metric surface the Neon host needs: `textWidth`, `calcTextWidth`, `splitText`, per-glyph x, line boxes — the same layout the node will paint, feeding Yoga's measure callback.
- `lineSpacing` in pixels, as h2d has it, replacing today's multiplier (`text.ms:49`).

**Defects closed.** Atlas-full, as a class rather than a patch. Integer glyph origins and rounded advances (`fontstash.h:1230-1244`, `:1314`). `kern`-only metrics. `split(" ")` wrapping (`text.ms:19`). The 16-font limit (`batcher.c:35`). No `textWidth`. The R8→RGBA CPU expansion and full atlas re-upload on any new glyph (`batcher.c:345-360`, `:207-216`). Text lines centred on fractional pixels (`text.ms:7`).

**Both open decisions resolve here.**

*The rasterizer — stb_truetype only, or FreeType as well.* The decision is **not** "module or not". Guardrail 9 requires one rasterizer everywhere, so a FreeType module that is compiled out of the web build would produce different pixels in the browser and break the guardrail it is meant to serve. The real question is whether FreeType ships in **every** build including wasm. Experiment: rasterize the same code-buffer sample at 13 px / 1×, 13 px / 1.5× and 14 px / 1.25× through (a) stb_truetype unhinted with the four x-variants and the gamma table and (b) FreeType with light hinting, both through the same pipeline; capture both through the P0 harness; compare side by side with a Zed capture taken under the T5 protocol. The evidence that decides: at 1×, whether unhinted stems land on the pixel grid darkly enough that the gamma and contrast table cannot close the gap, judged on stem darkness and stem-to-grid alignment; against that, the wasm delta of FreeType in both web backends, measured, not assumed. Constraint if FreeType comes: hinting only in the pixel-exact regime, the outline shifted **before** hinting, and hinted advances never fed back into layout (GHOSTTY.md:42; the integer-advance defect is what fontstash is being removed for). Default if the evidence is ambiguous: stb_truetype only — it is what macOS and Ghostty-on-macOS ship, and it is one dependency rather than two.

*Atlas page kinds — separate R8 and RGBA pages, or four coverage planes per RGBA page.* Experiment: both allocators behind a flag, one workload — a code buffer at three sizes and two DPIs, plus UI icons and an emoji run — measuring pages allocated, bytes resident, bind-slot changes per frame (which are batch breaks, so T1 sees them), and whether the per-instance plane selector costs any instance bytes. The prediction to test: sokol replaces a **whole image** per update, so a dirty coverage page costs 1 MB on an R8 1024² page and 4 MB on an RGBA four-plane one, and the four-plane page holds 4× the glyphs but is re-uploaded whenever any of its planes is dirty — a 4× upload penalty per new glyph, on the target where "upload bandwidth is scarcer" (see "Web and WebGPU"). Four planes wins only if it removes enough bind-slot changes to pay for that. Default if the measurement is a wash: R8 + RGBA, the simpler allocator and the smaller upload.

**Exit.**

- The `text/` scenes at DPI 1.0, 1.25 and 1.5 are byte-identical across runs, and the 13 px capture is judged beside Zed under the T5 protocol, with the verdict written into this doc.
- Glyph rasterizations per frame reach 0 in a steady state; atlas bytes after a zoom sweep are bounded.
- `textWidth` and per-glyph x exist and agree with the painted layout — the same numbers feed measurement and paint.
- A missing glyph resolves through the fallback chain; a codepoint miss is cached.
- The **first five-backend conformance run** (TESTING.md guardrail 9) happens here, because text is where backends diverge most.

**Tests.** T3: fontTools for font and decoration metrics; the HarfBuzz oracle restricted to cmap and GPOS kerning with features off. T1: the four x-variants and the baseline snap asserted as exact numbers. T2: the `text/` group. T4: atlas pages and bytes gated; rasterizations per frame gated.

**Measure.** Against the baseline UI scene: draws unchanged from P2, `present` not worse. New rows: first-paint warm-up cost, atlas bytes after the zoom sweep, wasm delta of the glyph layer per backend.

**Unblocks.** P4; and the Neon host's Yoga measure callback, which is the gate on a Void-backed Neon app rendering text at all.

**Risk → fallback.** This is the largest phase and the one carrying both open decisions. If the 1× captures are not good enough with stb_truetype and FreeType's wasm cost is unacceptable, the fallback is not a second rasterizer but a narrower claim: ship the pixel-exact regime at DPI ≥ 1.25 where unhinted coverage is sufficient (GPUI ships exactly that on macOS), record 1× as a known weakness with its captures, and revisit with variable-font axes or stem darkening in P6. Do not resolve it by adding a per-platform text path — that is guardrail 9.

### P4 — Text runs and the editor surface

**Goal.** A read-only code-editor view: syntax-coloured runs, decorations, selection and a caret, correct and cheap.

**Par.** GPUI's shaped-line model — `TextRun`, a style change splitting the shaping run so a ligature is never two-tone, run backgrounds as quads painted before glyphs, underline and strikethrough as their own primitive, wrap boundaries and truncation and `x_for_index` / `index_for_x` / `force_width` / `split_at` all over shaped glyphs (GPUI.md:46-49) — with Ghostty's caret and selection discipline on top, and Makepad's selection geometry.

**Lands.**

- `TextRun { len, font, color, background, underline, strikethrough }`; a style change splits the run.
- Run backgrounds, underline, strikethrough and wavy as instances of the UI pipeline, with thickness and position from the font metrics P3 extracted, snapped.
- Wrap boundaries indexing the unwrapped glyph list, so a width change never re-shapes; the CJK break rule; hanging indent; truncation at start, middle and end; `force_width` snapping base glyphs to a monospace cell grid with combining marks left attached; `split_at` cutting a shaped line without re-shaping.
- `x_for_index` and `index_for_x` over glyph positions; line boxes — the geometry the host needs for caret, selection and IME candidate placement.
- **Caret and selection as their own instances**, never part of a text range, so a blink dirties nothing else (GHOSTTY.md:90); selection as per-row quads carrying the neighbouring rows' x and width, unioned by smooth-min in the fragment shader, so concave joins are filleted with no geometry (MAKEPAD.md:78).
- Shaping break at an index, as an input on `Text` (GHOSTTY.md:35) — the mechanism, not Ghostty's terminal defaults.

**Defects closed.** The remaining h2d text surface: the `Text` metric surface and the `Align` enum.

**Exit.**

- A 200-line × 80-column buffer with syntax colours, a selection spanning several rows and a caret renders correctly, in a small bounded number of draw calls.
- A ligature never spans two colours; a wavy underline follows the font's metric, snapped.
- Caret blink changes no text instance.
- Selection across a ragged range joins without gaps or overlapping alpha.

**Tests.** T3: the UCD conformance files for grapheme clusters and line-break opportunities, with the divergence from UAX #14 recorded as one PENDING reason — void2d follows GPUI's cheaper rule, and the pass rate against the standard is what says whether that is acceptable. T1: run splitting, wrap boundaries and decoration placement as numbers. T2: the editor scenes and the decoration group. T0: truncation and `split_at` boundary arithmetic.

**Measure.** A new bench scene — 200 lines × 80 columns with runs, a selection and a caret: draw calls, instances, `present`. It becomes the scroll case P5 is measured on.

**Unblocks.** P5's scroll measurement, and the editor claim in "The bar".

**Risk → fallback.** Without the shaper (P6) there are no ligatures, so a code font's `calt` is absent and the editor scene looks wrong to anyone who knows the font. Fallback: state it, capture it, and keep the shaping-break input in place so the shaper drops in without touching this surface. Do not pull the shaper forward — it is the single largest wasm item in guardrail 6 and it needs its own measurement.

### P5 — Retention, scroll and the host contract

**Goal.** An unchanged node costs nothing, a scroll is a snapped translation rather than a rebuild, and the host can ask whether anything changed.

**Par.** Past all three references. Makepad is the only running example of persistent instance ranges with an in-place paint-only patch (MAKEPAD.md:33, 102); none of the three has a cheap scroll — GPUI rebuilds every visible item, Makepad re-records, Ghostty re-emits rows. A retained tree is what makes the cheap form possible, and this phase is where Void's model earns its keep.

**Lands.**

- Persistent instance ranges with dirty-range upload; draw order rebuilt only on structural change; "identical bytes → skip the upload" (MAKEPAD.md:117).
- The in-place paint-only patch: hover, focus and caret blink write instance floats and never walk the tree.
- `TileGroup` — the h2d-native retained multi-quad node on one texture — and the non-overlap node flag, with Makepad's lane fallback where a draw cannot join the unified pipeline (a custom shader, a second atlas page), guarded by the flag rather than by a depth buffer.
- `Mask.scrollX/Y` applied as a list-level shift after the per-instance clip: `clamp(clamp(p, clip) + shift, viewClip)` — the formulation Makepad wrote and never used (MAKEPAD.md:111) — with the offset snapped to a device pixel, so a text run's subpixel variants survive the translation.
- `Scene` reports whether it changed and can re-present its last list; scheduling stays the host's.
- The missing `Object` surface: `parent`, `remove()`, reparent-on-add with a cycle guard, `getChildAt` / `getChildIndex` / `numChildren`, `name`; `localToGlobal` syncing first instead of returning last frame's matrix (`node.ms:174-180`).
- The camera out of every world matrix and into a uniform, as h2d has it, so a camera move stops re-multiplying the tree (`scene.ms:91-99`).
- Host-facing rendering services collected into one surface: text measurement, text geometry, hit geometry (`globalToLocal`, world bounds, clip-aware containment), the change flag, and the frame counters from P1.

**Defects closed.** The last "Known defects" line — `parent`, `TileGroup`, `Mask.scrollX/Y` and the text metrics it points at. Also the idle cost: `Scene.present` walking and drawing every frame with nothing knowing whether the tree changed.

**Exit.**

- Scrolling the P4 editor scene uploads only the shift and walks no tree.
- A caret blink and a hover upload a known small number of bytes and cause no structural change.
- An idle frame issues no draw and no upload.
- A fully static 100 000-node frame costs a column sweep, not a tree walk (the SCENE-SCALE.md budget).
- One node can no longer sit under two parents (`node.ms:133-137`).

**Tests.** T1 carries this phase: mutate one node, assert exactly one dirty range of a known size; assert byte-identical re-records; assert zero instances written on a blink; assert the draw order rebuilds only on structural change. T3: the h2d oracle for `getBounds`, `localToGlobal` / `globalToLocal`, mask intersection and scale modes, with HEAPS.md's deliberate divergences as the seed PENDING list. T4: scroll and idle budgets gated on uploaded bytes, which are deterministic.

**Measure.** Scrolling the 200-line text view: CPU per frame and uploaded bytes per frame, both against P4's numbers. A static 100 000-node frame: CPU. An idle frame: zero draws. The UI bench scene must not regress.

**Unblocks.** The Neon Void host; SCENE-SCALE.md's columnar model has a consumer for the first time.

**Risk → fallback.** Persistent ranges and the in-place patch depend on per-instance bytes being stable across frames, which P2's layout decides and T1's idempotence assertion is the only guard on. If snapping or a gradient parameter turns out to depend on something that changes every frame, ranges thrash and the phase delivers nothing. Fallback: keep dirty-range upload for the subtrees that are provably stable (`TileGroup`, text runs) and re-record the rest, which is Makepad's granularity and still far better than today. The assertion that catches it early is in P1, not here.

### P6 — Modules and hardening

**Goal.** Everything that is optional, measured by what it costs; and the paths that make a failure survivable.

**Par.** The remaining taken items across all four references, each behind a compile-time switch, so a game build pays for none of them (guardrail 6).

**Lands.** Each item is independently shippable and carries its own wasm measurement.

- **Shaper module** (candidate `kb_text_shape`): GSUB features, ligatures, complex scripts, shaping breaks as an input. The largest wasm item; measured alone.
- **SDF text** for the transformed regime: one ~32 px/em distance field per glyph, derivative-scaled ramp, luma bias (MAKEPAD.md:112) — so zoom and animation cost nothing, and void3d gets world-space text through the same glyph layer.
- Colour emoji, and variable-font axes and the hinting rasterizer **only if** P3's captures asked for them.
- **SVG → R8 mask → tinted sprite**, the icon path, with a single-header C rasterizer.
- Procedural sprite glyphs — box drawing, blocks, braille, powerline — for a terminal widget.
- Animated image frames keyed by frame index.
- `Graphics` antialiasing by a vertex-shader fringe: the edge normal per fringe vertex, extruded by `1px / scale`. No MSAA intermediate, no baked fringe (guardrail 4). `sample_count` exposed as a knob on the mobile bridges instead of hard-coded 1 (guardrail 5) — the one place this phase touches void3d, since the swapchain sample count must match its pipelines.
- Device loss: drop every GPU object, re-arm every dirty flag, redraw, with a **fault-injection switch** (MAKEPAD.md:104) — which is also how the path is tested. void3d already has the Android form of this (`voidEmbedLoseContext`); this generalises it and covers the atlas and the instance buffer.
- Warm-up of pipelines, device and the font database off the first-frame path; release of GPU resources when occluded; a synchronous draw during live resize; discard of a late frame at the wrong size.
- The frame profiler: histograms of dirty-to-present, draw time and input latency, plus the draw-call, instance and upload-byte counters GPUI lacks, drawn outside invalidation.

**Defects closed.** None remaining; "Known defects" is empty by the end of P5.

**Exit.**

- The editor scene shows `calt` ligatures; the shaper's pass rate against the HarfBuzz oracle is printed and its PENDING list is explicit.
- Text at 4× zoom and under rotation is crisp through the SDF regime, and the atlas does not grow with the zoom level.
- Every module's wasm delta is recorded per backend and gated against a committed budget; a build with all modules off is measured too, and is the number guardrail 6 is about.
- The fault-injection switch loses the device mid-frame and the next frame is correct.
- `sample_count > 1` works on the iOS and Android bridges without breaking void3d's pipelines.

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
- `tests/layout.test.ms` belongs to no tier. Porting its five Yoga cases is blocked by compiler
  card `../../.inbox/compiler/2026-09-22-imported-interface-literal-reachability.md`; the
  standalone file is the parked site and the card owns the next action.
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
| **fontstash** | `deps/fontstash` ✅ | Today's text path, until P3. | Its integer layout, its single fixed atlas. |

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
