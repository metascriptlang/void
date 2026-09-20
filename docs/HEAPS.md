# Heaps Engine Analysis — Reference for Void

Analysis of [Heaps](https://github.com/HeapsIO/heaps) (~/projects/heaps), a lean Haxe game engine. Used as architectural reference for Void.

> **Refreshed for the sokol era (2026-07).** Dawn + SDL3 are fully removed; `sokol_gfx` is the GPU driver, `sokol-shdc` is the shader compiler, `sokol_app` is the platform/window layer. The gap analysis at the bottom is the authoritative status; older prose above may still read "Dawn/WGSL/SDL3" in struck-through context — treat those as historical rationale, not current truth.

## Engine Layer Stack

| Layer | Role |
|-------|------|
| Application (hxd.App) | Game loop, lifecycle, scenes |
| Scene Graph (h2d + h3d) | Object hierarchy, transforms, culling |
| Materials (h3d/mat/) | Pass system, shader composition, textures |
| Rendering Engine (h3d/Engine) | Draw calls, passes, batching, render targets |
| ~~Shader System (hxsl/)~~ | ~~Custom DSL → GLSL/HLSL compiler~~ — `sokol-shdc` handles this |
| ~~Graphics Driver (h3d/impl/)~~ | ~~OpenGL, DirectX, WebGL abstraction~~ — `sokol_gfx` IS the driver |
| Platform Layer (hxd/) | Window, Input, File I/O, Audio |

### sokol Coverage

sokol eliminates two entire layers that Heaps had to build from scratch:

- **~~Graphics Driver~~**: Heaps wrote 4 backends (OpenGL, DX9, DX12, WebGL) — thousands of lines each, all duplicating the same work. `sokol_gfx` abstracts Metal/D3D11/GL/Vulkan/WebGPU/WebGL2 behind one C API. Zero driver code for Void.
- **~~Shader Compiler~~**: Heaps built 33 files (type checker, DCE, linker, GLSL output, HLSL output) to compile one shader source to multiple targets. Void authors annotated GLSL; `sokol-shdc` cross-compiles offline to GLSL/GLES/HLSL/MSL/WGSL + a generated shader-desc header. Zero shader compilation code at runtime.
- **Platform/window**: `sokol_app` covers window + input + lifecycle on macOS/iOS/Win/Linux/Android/browser — the role Heaps' `hxd/` plays.
- **Rendering Engine**: sokol gives primitives (pipelines, passes, bindings, buffers) but orchestration is still on us — scene traversal, sorting, batching, multi-pass. void2d now owns the 2D orchestration; void3d orchestration is still minimal.
- **Shader composability**: The one part of hxsl/ worth learning from. Combining shader fragments (base + texture + lighting) into one program. For Void this is a material-system concern (see `docs/SHADER.md` Tier 2 über-shader uniforms), much simpler than a full compiler.

## 2D + 3D — How They Mix

Two separate scene graphs, rendered in order:

```haxe
// hxd/App.hx
s3d : h3d.scene.Scene;   // 3D rendered first
s2d : h2d.Scene;          // 2D overlaid on top
sevents : hxd.SceneEvents; // unified input for both

render(engine) {
    s3d.render(e);  // 3D to render target
    s2d.render(e);  // 2D on top (HUD, UI, debug)
}
```

No mixing within a single scene — they're composited as layers. Both share the same event/input system.

## Scene Graph

### 2D (`h2d/`)

```
h2d.Scene (root)
  └─ h2d.Object (x, y, scaleX, scaleY, rotation, alpha, visible)
       ├─ h2d.Drawable (color, filters, shaders)
       │    ├─ Bitmap, Text, Graphics, Particles, Anim
       │    └─ TileGroup, SpriteBatch
       ├─ Interactive (click/hover/drag)
       ├─ Flow (layout — like flexbox)
       ├─ Mask (clip region)
       └─ Layers (z-order management)
```

Transform: 2D affine matrix (matA/B/C/D + absX/absY), cached, lazy evaluation.
Viewport: scaling modes — Resize, Stretch, LetterBox, Fixed, Zoom, AutoZoom.

### 3D (`h3d/scene/`)

```
h3d.scene.Scene (root, camera, lights, renderer)
  └─ h3d.scene.Object (position, scale, rotation quaternion, bounds)
       ├─ Mesh (geometry + material)
       ├─ Skin (skeletal mesh + joints)
       ├─ Light (point, directional, spot)
       ├─ Batcher (GPU instancing)
       └─ Interactive (3D picking via raycasting)
```

Transform: full 3D (position Vector, rotation Quaternion, scale). Matrix-based, bounds tracking, frustum culling.

Key pattern: **parent-child hierarchy with transform propagation**. Changes to parent cascade to children automatically.

## Rendering Pipeline — OWNED IN void2d, STILL NEEDED FOR void3d

sokol gives us pipelines, render passes, bindings, buffers — but the orchestration is ours to build. **void2d now owns the 2D orchestration** (batcher flushes, Node2D tree walk, clip stack, render-target passes — see `src/void2d/draw.ms`); the items below remain open for the 3D path.

- ~~`driver.beginFrame()`~~ — sokol: `sg_begin_pass` from `sglue_swapchain()`
- `scene.render(engine)`
  - `Renderer.render(ctx)`
    - For each pass:
      - sort objects (front-to-back or back-to-front) — **NEED THIS (3D)**
      - for each object:
        - `Material.selectPass()` — **NEED THIS (3D; void2d has no material concept yet)**
        - bind shader + uniforms + textures — sokol `sg_bindings` (resource-views generation)
        - ~~`driver.draw(primitive)`~~ — sokol: `sg_draw()`
- ~~`driver.endFrame()`~~ — sokol: `sg_end_pass` + `sg_commit()`
- ~~`driver.present()`~~ — sokol_app presents the swapchain

- **Pass-based**: main pass, shadow pass, transparency pass, post-process — ADOPT
- **Batching**: ObjectInstance wrapping, batch primitives pooled — LATER (optimization)
- **Statistics**: drawTriangles, drawCalls, shaderSwitches tracked per frame — EASY, ADOPT
- **Render targets**: stack-based, push/pop for off-screen rendering — WebGPU render targets work, need management layer

## ~~Shader System (hxsl/) — Crown Jewel~~

~~33 files. Custom shader DSL that compiles to GLSL/HLSL at build time.~~ — Not needed for Void. We author annotated GLSL (`@vs`/`@fs`, separate `texture`+`sampler`); `sokol-shdc` cross-compiles offline to GLSL/GLES/HLSL/MSL/WGSL + a generated shader-desc header. See `src/sokol/shader.glsl`, `src/void2d/shader2d.glsl` and `docs/SHADER.md`.

### ~~Architecture~~

- ~~HXSL source (Haxe class methods)~~
  - ~~Macros.buildShader() [compile-time]~~
    - ~~Checker.hx [type check]~~ — sokol-shdc validates the annotated GLSL
    - ~~Flatten.hx [optimize]~~ — backend compilers optimize internally
    - ~~Dce.hx [dead code elimination]~~ — handled by backend compilers
    - ~~Linker.hx [combine shader fragments]~~ — Interesting idea, see below
    - ~~GlslOut.hx / HlslOut.hx [target codegen]~~ — sokol-shdc emits all targets from one source

### Key concept: Composable Shaders — WORTH ADOPTING (simplified)

The one idea worth keeping from hxsl/. Shaders are fragments that get linked together at runtime:

```haxe
// A material combines multiple shader fragments
mainPass.addShader(baseMeshShader);    // vertex transform + base color
mainPass.addShader(textureShader);      // texture sampling
mainPass.addShader(normalMapShader);    // normal mapping
mainPass.addShader(bloomShader);        // post-process
```

The linker merges these into a single GPU shader program. This is how Heaps avoids a combinatorial explosion of hand-written shader variants.

For Void: shader composability is **deferred to a material system** (Tier 3 in `docs/SHADER.md`). The pragmatic path is an über-shader with uniforms (`color` multiply, `colorAdd`, `colorMatrix`, `colorKey` — the Heaps `h2d.Drawable` color pipeline) landed as Tier 2 first; true fragment linking only if/when variant explosion bites.

### ~~Shader caching~~

~~`Cache.hx` — compiled shader programs cached by signature.~~ — sokol pipeline state objects ARE the cache. Same `sg_pipeline_desc` → reuse the `sg_pipeline`.

### Built-in shaders (h3d/shader/) — Reference for what Void shaders need

BaseMesh, Texture, ~~SpecularTexture~~, NormalMap, ~~ColorAdd/Mult/Matrix~~, ~~Bloom~~, ~~Blur~~, ~~DeferredLight~~, ~~CascadeShadow~~, ~~DefaultShadowMap~~, ScreenShader, ~~PBR variants~~...

Void currently ships: a 3D cube shader (`src/sokol/shader.glsl`) and a void2d über-shader (`src/void2d/shader2d.glsl`, tint + texture + gradient). 3D NormalMap / PBR / shadows / post-process are later void3d work.

## Materials (h3d/mat/)

```haxe
class Material extends BaseMaterial {
    mainPass : Pass;              // primary render pass
    texture : Texture;            // diffuse
    specularTexture : Texture;
    normalMap : Texture;
    color : Vector4;
    shadows : Bool;
    castShadows : Bool;
    receiveShadows : Bool;
}

class Pass {
    shaders : ShaderList;         // linked list of shader fragments
    culling : Face;               // Back, Front, None
    depthWrite : Bool;
    depthTest : Compare;
    blendSrc : Blend;
    blendDst : Blend;
    layer : Int;                  // render order
}
```

A Material has one or more Passes. Each Pass has render state + a list of shader fragments. This decouples appearance (shaders) from render configuration (blend, depth, cull).

## Asset System

### ~~Virtual Filesystem (`hxd/fs/`)~~

~~Pluggable backends:~~ — Over-engineered for Void's stage. Start with simple file loading.
- ~~`LocalFileSystem` — disk~~ ← Just use C `fopen`/`fread` via bridge
- ~~`EmbedFileSystem` — compiled into binary~~ ← Maybe later for prod builds
- ~~`BytesFileSystem` — in-memory~~ ← Not needed
- ~~`MultiFileSystem` — chained fallback~~ ← Not needed

### Resource loading — VOID'S APPROACH

```typescript
// Void approach: direct loading, no VFS abstraction
const tex = loadImageSync("assets/player.png", 4);   // stb_image via C bridge — DONE
const mesh = loadMesh("assets/level.gltf");            // TODO — mesh loaders not yet built
```

Direct file loading is the current path (`src/assets/image.{h,c,ms}`). Add a VFS abstraction only when prod packaging needs it (embed, pak archives).

### Supported formats — CURRENT STATE

Textures: PNG, JPEG ✅ (via stb_image — `src/assets/image.{h,c}`)
Models: None yet — cube is hand-authored in MetaScript. OBJ (simplest) → glTF later.
~~Fonts: BDF, bitmap fonts~~ ← Replaced by fontstash (TTF, `src/assets/` ships a real TTF)
~~Audio: WAV, OGG~~ ← Later
~~Tiled maps: TMX~~ ← Later, if 2D needed

## Input System

**Event-based** with `Interactive` objects for hit testing:

```haxe
// hxd/Event.hx — event types
EKeyDown, EKeyUp, ETextInput,
EPush, ERelease, EMove, EOver, EOut,
EWheel, EFocus, EFocusLost

// hxd/SceneEvents.hx — central dispatcher
// Routes events to Interactive objects under cursor
// Supports: hover tracking, focus, drag, event bubbling

// Interactive objects (2D + 3D)
h2d.Interactive — rectangular/shape hit areas
h3d.scene.Interactive — 3D raycasting against collision shapes
```

Input flow: Window → SceneEvents → find Interactive under cursor → dispatch.
Key state: `hxd.Key.isDown(K)`, `hxd.Key.isPressed(K)`.

## Animation — LATER

- `Animation.hx` — base: frame, speed, loop, events — ADOPT (core concept)
- `LinearAnimation.hx` — keyframe interpolation — ADOPT (basic)
- ~~`BufferAnimation.hx` — pre-baked data~~ — Optimization, later
- ~~`SimpleBlend.hx` — 1D blend space~~ — Advanced, later
- ~~`BlendSpace2D.hx` — 2D blend space~~ — Advanced, later
- `Transition.hx` — smooth transitions between anims — Nice to have
- ~~`SmoothTarget.hx` — procedural animation toward target~~ — Very advanced

~~Skeletal: Joint hierarchy with bind pose, inverse pose, parent/child. Dynamic joints for physics-based secondary motion (hair, cloth). Retargeting support.~~ — Full skeletal system is a large effort. Start with simple keyframe transforms, add skeletal when loading glTF models.

## Editor / Tools

No built-in visual editor. Heaps is a library-based engine. Void follows the same approach — code-first, no IDE.

- ~~`tools/hxsl/Main.hx` — standalone HXSL shader compiler~~ ← Not needed; `sokol-shdc` compiles annotated GLSL offline
- ~~`tools/meshTools/` — mesh processing/conversion~~ ← Use external tools (Blender export)
- `h2d/Console.hx` — in-game debug console — WORTH ADOPTING (debug overlay)
- `h3d/impl/SceneProf.hx` — performance profiler — WORTH ADOPTING (GPU stats)
- Scene editing is code-based or via external tools — SAME FOR VOID
- ~~Prefab system (`hxd/res/Prefab.hx`)~~ ← Later, if scene serialization needed

## Void vs Heaps — Gap Analysis

Statuses reflect the **sokol** era (Dawn/SDL3 removed). void2d is the active front.

| Layer | Heaps | Void Status | Priority |
|-------|-------|-------------|----------|
| Platform (window, input, timing) | hxd/ (47 files) | **Done** — `sokol_app` (native + browser canvas) | - |
| ~~Graphics driver~~ | ~~h3d/impl/ (multi-backend)~~ | **Done** — `sokol_gfx` (Metal/D3D11/GL/Vulkan/WebGPU/WebGL2) | - |
| ~~Shader compiler~~ | ~~hxsl/ (33 files, custom DSL)~~ | **Done** — `sokol-shdc` (annotated GLSL → GLSL/GLES/HLSL/MSL/WGSL) | - |
| 2D render engine | h2d batcher + drawables | **Done** — `src/void2d/draw.ms` quad batcher + clip stack | - |
| 2D scene graph | `h2d.Object` retained tree | **Done** — `Node2D` (`src/void2d/node.ms`, translate + scale + alpha inheritance) | - |
| 2D text | `h2d.Font` / `Text` | **Done** — fontstash glyph atlas (`src/void2d/batcher.{h,c}`) | - |
| 2D gradients | — | **Done** — linear + radial fill (`src/void2d/graphics.ms`) | - |
| Render targets + post | h3d render-target stack | **Done** (void2d) — offscreen RT + separable gaussian blur (`src/void2d/effect.ms`) | - |
| Texture loading | hxd/Res bitmaps | **Partial** — PNG/JPEG via stb_image (`src/assets/image.{h,c,ms}`); no mesh loaders yet | Medium |
| 3D render engine | h3d/Engine + Renderer | **Minimal** — manual draw calls, cube demo only (`src/examples/rendererSokol.ms`) | High |
| 3D scene graph | `h3d.scene.Object` | **None** | High |
| Materials | h3d/mat/ (Pass + ShaderList) | **None** (über-shader uniforms are the Tier 2 plan, see `docs/SHADER.md`) | High |
| Mesh asset loading | hxd/Res models | **None** — cube is hand-authored in MetaScript (`src/examples/cubedata.ms`) | Medium |
| Input routing | hxd/SceneEvents + Interactive | **None** (sokol_app delivers raw events; no hit-testing layer) | Later |
| Animation | h3d/anim/ (skeletal, blend) | **None** | Later |
| Audio | hxd/snd/ | **None** | Later |

sokol eliminates 2 entire layers (driver + shader compiler) that were Heaps' biggest investments; `sokol_app` folds in platform. Void's done work concentrates in the **2D middle layers** (batcher, Node2D, text, gradients, RT/blur). The remaining open tiers are the **3D path** (scene graph + materials + mesh loading) and **input routing** — all of which sit above the GPU bridge, not below it.

> ⚠️ **The feature table above is a feature checklist, not a quality verdict.** void2d has *coverage* on most 2D rows, but internal quality is not yet at Heaps parity — see the next section. **Direction lock (2026-07): 2D reaches full Heaps parity BEFORE 3D resumes.** The reconciler + any real UI inherits every 2D quality defect, so finishing 2D is a dependency for 3D/Neon, not a detour.

## 2D Quality Parity — vs Heaps (the committed front)

Feature-Done ≠ quality-parity. This section tracks the **internal quality** of each 2D dimension against Heaps `h2d`, with code evidence. Grades: NAIVE / BASIC / MATURE / PARITY-GRADE. First audited 2026-07; **re-graded 2026-09-20** against `src/void2d/*` at `45d88e0` and `~/projects/heaps` at `b9aa6dcb`. Parity with h2d is no longer the finish line: the bar is in [VOID2D.md](VOID2D.md), and several rows are already past h2d.

| Dimension | void2d grade | void2d reality (2026-09-20) | Heaps mechanism | Gap |
|---|---|---|---|---|
| Transform laziness | **MATURE** | world matrices cached; `scene.present` passes `viewChanged`, not `true` (`scene.ms:91-99`). But the scale mode and camera are baked into every world matrix, so a camera move re-multiplies the tree; five field compares per node per frame instead of a set-time flag (`render.ms:79`); `localToGlobal` reads last frame's matrix (`node.ms:174-180`) | `posChanged` set in setters + downward propagation in `sync()`; `syncPos()` before every query; camera as a uniform (`RenderContext.hx:275-283`) | Medium |
| Bounds + culling | **MATURE** | `getBounds` (world space, `render.ms:285-305`); every node kind incl. Label and Graphics culled against the viewport (`:191-201`). Not culled against the active clip; no subtree cull; no `relativeTo` | per-tile cull in `drawTile` only; Text/TileGroup/Graphics never culled | **Ahead of h2d**; clip cull missing |
| Batching | **BASIC** | always-on dynamic batching for Rect/Sprite/Anim/ScaleGrid; flush on view, blend, effect, smooth, clip change and on **every Label and Graphics node** (`draw.ms:79-81, 264-320`); fixed 65536-vertex stream, draws dropped past it (`batcher.c:19`) | off by default (`BUFFERING` is a compile flag, `RenderContext.hx:24`); throughput from user-chosen `TileGroup`/`SpriteBatch` | High — [VOID2D.md](VOID2D.md) P1, P2 |
| Alpha | **PARITY+** | premultiplied in the shader (`shader2d.glsl:53-54`), `ONE / ONE_MINUS_SRC_ALPHA` pipelines (`batcher.c:88-96`), render-target sources flagged already premultiplied | non-premultiplied with `blendAlphaSrc=One` | none |
| DPI / scale modes | **MATURE** | six `ScaleMode`s (`types.ms:30`), logical-point scene units, fonts rasterised at `size × dpi`. **Defects:** the logical size is truncated to int (`scene.ms:89`), so fractional DPI is off-grid; `Zoom`/`AutoZoom` mean something different from h2d's (`scene.ms:65-78` vs `Scene.hx:415-427`) | 6 `ScaleMode` + viewport in the vertex shader; **DPI not modelled at all** (`displayScale` has no reader) | Ahead in design, one real defect |
| Filters | **BASIC, wrong semantics** | per-node Blur/Glow/DropShadow (`types.ms:32-41`). Only children enter the target; alpha applied twice under Blur; screen-space target at dpi 1; two subtree re-syncs per frame; the pass is nested inside the swapchain pass; blur tap spacing multiplied by the radius (`render.ms:216-283`, `shader2d.glsl:81-87`) | `Filter` base + RT pool + `filterMatrix` + self-and-children in object-local space + Group; true Gaussian (`h3d/pass/Blur.hx:74-112`) | High (correctness) |
| Clip / mask | **MATURE** | scissor, intersect-on-push; rotated mask → four-corner AABB (`render.ms:204-205`), which is more correct than h2d's two-corner form (`Mask.hx:26-43`). No `scrollX/Y` | scissor + intersect-on-push; `Mask.scrollX/Y` | Low — scroll fields missing |
| Text | **BASIC** | on-demand TTF glyph cache (ahead of h2d's baked atlases); but integer glyph origins and advances (`fontstash.h:1230-1244`), `kern`-only, `split(" ")` wrapping, fixed 512² atlas that drops glyphs when full, no `textWidth`, no fallback, no runs | `FontChar` + kerning list, `needsRebuild`, `HtmlText`, SDF fonts; but baked atlases, Int metrics, one page | High — replaced at [VOID2D.md](VOID2D.md) P3 |
| **Color pipeline** | **PARITY** | multiply + add + matrix + key in one shader, no variant compilation (`shader2d.glsl:41-54`). `colorKey` is a looser threshold than h2d's exact match (`ColorKey.hx:9-12`) | same set via `ShaderList`, plus `addShader` | none |
| **Static buffers** | **BASIC** | Graphics and Label each own an `sg_buffer`: past sokol's 128-buffer pool nothing more renders; a text change destroys and recreates the buffer (`render.ms:110-111`); `removeChild` leaks unless `dispose` is called | `TileGroup` persistent + `allocated` lifecycle (`onAdd`/`onRemove`) | High — [VOID2D.md](VOID2D.md) P1, P5 |

### Parity plan (sequenced by dependency, not by difficulty)

> **Status 2026-09-20.** Done: T0.1, T0.2, T0.3 (one defect left: the int truncation), T1.1. Partly: T1.3 (65536, still no grow), T2.1 (per-node filters exist, semantics wrong). Open: T1.2, T2.3. What remains is carried by the sequencing in [VOID2D.md](VOID2D.md); this list is kept as the record of the 2026-07 plan.

**Tier 0 — correctness (no deps, blocks the reconciler). ~2–3 days.**
- **T0.1 Transform cache actually lazy** — cache last cam/zoom/fbW/fbH in `scene.present`, pass `parentChanged=false` when unchanged. *Smallest, highest-leverage; do first as the validating win.*
- **T0.2 Premultiplied-alpha path** — premult blend mode in `batcher.c`, premult at emit or in shader, `premultiplyAlpha` flag on Node2D/Scene. Verify all 4 blend modes compose through groups.
- **T0.3 DPI / `ScaleMode`** — `ScaleMode` enum (Resize/Stretch/LetterBox/Fixed/Zoom/AutoZoom), viewport offset+scale as **shader uniforms** (mirror `Base2d.viewportA/B`), resize hook.

**Tier 1 — perf at scale (unblocks large scenes/lists). ~3–5 days.**
- **T1.1 `getBounds()` + culling** — bounds recursion on Node2D, `addBounds` corner-transform, per-tile/per-node viewport cull at emit.
- **T1.2 Texture-bucketed batching** — `BatchDrawState`-style run collector; sort emit by (texture, pipeline, blend) within zIndex.
- **T1.3 `MAX_VERTS` grow** — dynamic resize of the `Vec` + sokol buffer realloc-on-grow.

**Tier 2 — API surface (closes the "feels like Heaps" gap). ~1 week+.**
- **T2.1 Filter stack** — `Filter` base + render-target pool + `filterMatrix` (2×3 inverse) + bounds-extend/clip-to-viewport; ship Blur + DropShadow + Group.
- **T2.2 Stencil masking** — *OPTIONAL*. Heaps 2D is scissor-only too (parity as-is); add only if rotated/non-rect masks become a real need.
- **T2.3 Text richness** — multi-font + fallback chain, break-char-aware word wrap, kerning toggle, `HtmlText`/markup. (bidi genuinely hard — may defer; verify fontstash kerning first.)

**Near-parity — verify, don't rebuild:** color pipeline (parity+), static buffers. Rotation in `drawNode` + real TTF (caps placeholder) roll up under T2.3 / general 2D polish — they were the old "Next" line in CLAUDE.md, now subsumed here.

## The h2d contract — status (2026-09-20)

What void2d keeps of h2d, what it still lacks, and what it must not copy. void2d stays h2d in **interface and semantics**; how pixels are produced comes from the rendering references ([VOID2D.md](VOID2D.md)).

### Keep, and still add

Kept as-is: radians, S·R·T then parent, alpha multiplied down the tree, colour/blend/effects not inherited, array-order painter's drawing, filter as a node property, Mask as a node, `getBounds`, `localToGlobal/globalToLocal`.

Missing from void2d today:

- `parent`, `remove()`, reparent-on-add with a cycle guard, `getChildAt / getChildIndex / numChildren`, `name` (`h2d/Object.hx:411-443` vs `void2d/node.ms:133-137`, where one node can sit under two parents). A reconciler host needs `parent` anyway.
- **`TileGroup`** — a retained multi-quad node on one texture (`h2d/TileGroup.hx:562-718`); `Text` is built on it (`h2d/Text.hx:187-189`). It maps onto a persistent instance range and is the h2d-native form of the non-overlap hint.
- **`Tile.dx/dy`** with `center()` / `setCenterRatio()` (`h2d/Tile.hx:26-30, 166-175`). Today's node `pivot` is applied for Rect/Sprite/Anim, ignored by ScaleGrid, Label and Graphics, and used by Mask (`render.ms:42-56, 192-204`).
- `Mask.scrollX/Y` (`h2d/Mask.hx:70-125`) — the scroll mechanism in [VOID2D.md](VOID2D.md) "Clip and scroll".
- The `Text` metric surface and `Align` enum; `lineSpacing` in pixels (void2d's is a multiplier, `text.ms:49`).
- ~~`smooth` as a tri-state with a scene default; `tileWrap`, with clamp as the default sampler.~~ **Landed at P1**: `Smooth.Inherit/Off/On` in `void2d/types.ms` resolving against `Scene.defaultSmooth`, and `Node2D.tileWrap` with clamp by default. The scene default is **linear**, not h2d's nearest - that is the "Do not copy from h2d" entry below, applied.
- ~~Filter semantics (`h2d/Object.hx:896-956`)~~ **Landed at P1**, all six: the node itself goes into the target, alpha applied once (on every filter kind - the Glow and DropShadow branch took a second pass of the review to get right), the target in object-local space through a filter matrix that the emitter subtracts as it records rather than a second sync, bounds clipped to the viewport, a frame-linear target pool (`h3d/impl/TextureCache.hx`) capped at 16, and clip state saved and cleared per target.
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

## Key Heaps Design Decisions — Adopt or Skip

1. **Separate 2D + 3D scenes, composited** — ADOPT. Clean separation, 2D always on top.
2. **Pass-based materials** — ADOPT. Decouple shader from render state (blend, depth, cull).
3. **Composable shader fragments** — DEFER. Pragmatic path is a Tier 2 über-shader + uniforms (closes the Heaps `h2d.Drawable` color-depth gap); true fragment linking only if variant explosion bites. See `docs/SHADER.md`.
4. ~~**Virtual filesystem**~~ — SKIP for now. Direct file loading. Add VFS when we need prod packaging.
5. **Interactive objects** — ADOPT LATER. Input routing to scene objects via hit testing. Needs scene graph first.
6. **Lazy transform evaluation** — ADOPT. Cache matrices, recompute only on change. Critical for performance.
7. **Object flags** — ADOPT. Bitfield for visibility, culled, allocated, etc. Fast checks.

## Build Priority for Void

**Direction (2026-07): 2D parity first, 3D deferred.** See the "2D Quality Parity" section above for the committed, sequenced plan. Summary:

1. **Tier 0 — 2D correctness** (transform cache, premultiplied alpha, DPI/ScaleMode). Blocks the reconciler. **~2–3 days.**
2. **Tier 1 — 2D perf at scale** (`getBounds`+culling, texture-bucketed batching, `MAX_VERTS` grow). **~3–5 days.**
3. **Tier 2 — 2D API surface** (filter stack, optional stencil, text richness). **~1 week+.**
4. **Void Host adapter** — implement Neon's `Host` contract (`~/metascript/neon/src/render/host.ms`) over Node2D: ~50–100 lines mapping `createElement`/`setAttr`/`append` → Node2D ops. NOT a reconciler (that's Neon's Layer A); the reconciler already exists renderer-agnostic in Neon. Now safe to land; inherits a solid 2D host. See `~/metascript/neon/docs/RENDER-LAYERS.md`.
5. **3D path (deferred)** — `Object3D` scene graph, materials, mesh loading, 3D renderer. Resumes once 2D is parity-grade.
6. **Input routing** — hit-testing over sokol_app events (needed before interactive UI).
7. **Animation** — keyframe then skeletal, once models load.
