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

Feature-Done ≠ quality-parity. This section tracks the **internal quality** of each 2D dimension against Heaps `h2d`, with code evidence. Grades: NAIVE / BASIC / MATURE / PARITY-GRADE. Source: parallel audit of `src/void2d/*` vs `~/projects/heaps/h2d`.

| Dimension | void2d grade | void2d reality | Heaps mechanism | Gap |
|---|---|---|---|---|
| Transform laziness | **BASIC** | cache exists but `scene.present` hardcodes `parentChanged=true` every frame (scene.ms:37) → **whole tree re-muls world matrix per frame** | `posChanged` bool + downward propagation in `sync()`; `lastFrame` dedup; separate upward `syncPos()` for queries | **Critical, easy fix** |
| Bounds + culling | **NAIVE** | no `getBounds()`, no subtree cull; Graphics/Label never culled (node.ms:304-311) | per-tile viewport cull at emit (`RenderContext.drawTile` corner test vs NDC), no stored flag | High |
| Batching | **BASIC** | tree-DFS order, no texture sort, no `BatchDrawState`, `MAX_VERTS=32768` hard ceiling no grow | `BatchDrawState` linked-list (texture,count) → 1 draw call per texture swap | High (perf cliff) |
| Alpha | **BASIC** | straight-alpha only; Add/Multiply/Screen under non-unit-alpha group = **mathematically wrong** (halo, double-darken) | `blendAlphaSrc=One` + alpha fold at leaf (`setupColor`); `premultiplyAlpha` toggle | Critical (correctness) |
| DPI / scale modes | **NAIVE** | re-reads `fbW/fbH` per frame; no LetterBox/Auto/Stretch/Zoom, no pixel ratio | 6 `ScaleMode` + viewport matrix **in the vertex shader** (`Base2d.viewportA/B`) | Critical (retina/mobile) |
| Filters | **NAIVE** | one hardcoded 5-tap Gaussian, caller ping-pongs RT, no per-Node attachment | `Filter` base + RT pool + `filterMatrix` + Group/Blur/Glow/DropShadow/Outline | Medium (API gap) |
| Clip / mask | **BASIC** | scissor-axis only; rotated mask collapses to AABB (draw.ms:35-42) | scissor + intersect-on-push (Heaps 2D is also scissor-only — actual parity here) | Low |
| Text shaping | **BASIC** | 1 font, ASCII-space-only word wrap, no rich/bidi/fallback (draw.ms:302-353) | `FontChar`+kerning list, `needsRebuild` deferred, charset fallback, `HtmlText` | Medium |
| **Color pipeline** | **MATURE** | multiply+add+matrix+key in one shader (shader2d.glsl:41-51) — **exceeds Heaps** (`colorKey`) | same via `ShaderList` | **Parity+** |
| **Static buffers** | **BASIC+** | Graphics+Label retain immutable buffers, re-emit per frame | TileGroup persistent + `allocated` lifecycle + per-subtree retention | Near-parity |

### Parity plan (sequenced by dependency, not by difficulty)

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
