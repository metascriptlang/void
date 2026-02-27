# Heaps Engine Analysis — Reference for Void

Analysis of [Heaps](https://github.com/HeapsIO/heaps) (~/projects/heaps), a lean Haxe game engine. Used as architectural reference for Void.

## Engine Layer Stack

| Layer | Role |
|-------|------|
| Application (hxd.App) | Game loop, lifecycle, scenes |
| Scene Graph (h2d + h3d) | Object hierarchy, transforms, culling |
| Materials (h3d/mat/) | Pass system, shader composition, textures |
| Rendering Engine (h3d/Engine) | Draw calls, passes, batching, render targets |
| ~~Shader System (hxsl/)~~ | ~~Custom DSL → GLSL/HLSL compiler~~ — WGSL + Dawn handles this |
| ~~Graphics Driver (h3d/impl/)~~ | ~~OpenGL, DirectX, WebGL abstraction~~ — Dawn IS the driver |
| Platform Layer (hxd/) | Window, Input, File I/O, Audio |

### WebGPU/Dawn Coverage

Dawn eliminates two entire layers that Heaps had to build from scratch:

- **~~Graphics Driver~~**: Heaps wrote 4 backends (OpenGL, DX9, DX12, WebGL) — thousands of lines each, all duplicating the same work. Dawn abstracts Vulkan/Metal/D3D12 behind the WebGPU API. Zero driver code for Void.
- **~~Shader Compiler~~**: Heaps built 33 files (type checker, DCE, linker, GLSL output, HLSL output) to compile one shader source to multiple targets. Void writes WGSL — Dawn compiles it to native shaders internally. Zero shader compilation code.
- **Rendering Engine**: WebGPU gives primitives (command encoders, render passes, bind groups, pipelines) but orchestration is still on us — scene traversal, sorting, batching, multi-pass. This is the main work.
- **Shader composability**: The one part of hxsl/ worth learning from. Combining shader fragments (base + texture + lighting) into one program. For Void this is a material system concern using WGSL, much simpler than a full compiler.

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

## Rendering Pipeline — STILL NEEDED FOR VOID

WebGPU gives us command encoders, render passes, bind groups, pipelines — but the orchestration is ours to build.

- ~~`driver.beginFrame()`~~ — WebGPU: just create command encoder
- `scene.render(engine)`
  - `Renderer.render(ctx)`
    - For each pass:
      - sort objects (front-to-back or back-to-front) — **NEED THIS**
      - for each object:
        - `Material.selectPass()` — **NEED THIS**
        - bind shader + uniforms + textures — WebGPU bind groups
        - ~~`driver.draw(primitive)`~~ — WebGPU: `pass.draw()`
- ~~`driver.endFrame()`~~ — WebGPU: `encoder.finish()`
- ~~`driver.present()`~~ — WebGPU: `surface.present()`

- **Pass-based**: main pass, shadow pass, transparency pass, post-process — ADOPT
- **Batching**: ObjectInstance wrapping, batch primitives pooled — LATER (optimization)
- **Statistics**: drawTriangles, drawCalls, shaderSwitches tracked per frame — EASY, ADOPT
- **Render targets**: stack-based, push/pop for off-screen rendering — WebGPU render targets work, need management layer

## ~~Shader System (hxsl/) — Crown Jewel~~

~~33 files. Custom shader DSL that compiles to GLSL/HLSL at build time.~~ — Not needed for Void. WGSL is our single shader target, Dawn compiles it to native GPU shaders internally.

### ~~Architecture~~

- ~~HXSL source (Haxe class methods)~~
  - ~~Macros.buildShader() [compile-time]~~
    - ~~Checker.hx [type check]~~ — Dawn validates WGSL
    - ~~Flatten.hx [optimize]~~ — Dawn optimizes internally
    - ~~Dce.hx [dead code elimination]~~ — Dawn handles this
    - ~~Linker.hx [combine shader fragments]~~ — Interesting idea, see below
    - ~~GlslOut.hx / HlslOut.hx [target codegen]~~ — WGSL is the only target

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

For Void: we could do this at the WGSL string level — concatenate WGSL snippets into a complete shader module. Much simpler than a full compiler. Or just use pre-written WGSL shaders and swap them per material (good enough initially).

### ~~Shader caching~~

~~`Cache.hx` — compiled shader programs cached by signature.~~ — WebGPU pipeline caching handles this. `createRenderPipeline` with same config = same pipeline object.

### Built-in shaders (h3d/shader/) — Reference for what WGSL shaders Void needs

BaseMesh, Texture, ~~SpecularTexture~~, NormalMap, ~~ColorAdd/Mult/Matrix~~, ~~Bloom~~, ~~Blur~~, ~~DeferredLight~~, ~~CascadeShadow~~, ~~DefaultShadowMap~~, ScreenShader, ~~PBR variants~~...

Start with: BaseMesh + Texture + NormalMap. Add PBR/shadows/post-process later.

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

### Resource loading — SIMPLIFIED FOR VOID

```typescript
// Void approach: direct loading, no VFS abstraction
const tex = loadTexture("assets/player.png");    // stb_image via C bridge
const mesh = loadMesh("assets/level.obj");        // OBJ parser via C bridge
```

Start with direct file loading. Add VFS abstraction only when needed (prod embedding, pak archives).

### Supported formats — START SMALL

Textures: PNG, JPEG (via stb_image — single C header)
Models: OBJ (simplest, text-based) → glTF later
~~Fonts: BDF, bitmap fonts~~ ← Later
~~Audio: WAV, OGG~~ ← Later (SDL3 has audio)
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

- ~~`tools/hxsl/Main.hx` — standalone HXSL shader compiler~~ ← Not needed, WGSL is plain text
- ~~`tools/meshTools/` — mesh processing/conversion~~ ← Use external tools (Blender export)
- `h2d/Console.hx` — in-game debug console — WORTH ADOPTING (debug overlay)
- `h3d/impl/SceneProf.hx` — performance profiler — WORTH ADOPTING (GPU stats)
- Scene editing is code-based or via external tools — SAME FOR VOID
- ~~Prefab system (`hxd/res/Prefab.hx`)~~ ← Later, if scene serialization needed

## Void vs Heaps — Gap Analysis

| Layer | Heaps | Void Status | Priority |
|-------|-------|-------------|----------|
| Platform (window, input, timing) | hxd/ (47 files) | **Done** (SDL3 bridge) | - |
| ~~Graphics driver~~ | ~~h3d/impl/ (multi-backend)~~ | **Done** (Dawn = the driver) | ~~N/A~~ |
| ~~Shader compiler~~ | ~~hxsl/ (33 files, custom DSL)~~ | **Done** (WGSL + Dawn) | ~~N/A~~ |
| Rendering engine | h3d/Engine + Renderer | **Minimal** (manual draw calls) | High |
| Scene graph | h2d/Object + h3d/scene/Object | **None** | High |
| Materials | h3d/mat/ (Pass + ShaderList) | **None** | High |
| Asset loading | hxd/Res + hxd/fs/ (VFS) | **None** | High |
| Animation | h3d/anim/ (skeletal, blend) | **None** | Later |
| 2D system | h2d/ (sprites, text, UI) | **None** | Later |
| Audio | hxd/snd/ | **None** | Later |

WebGPU/Dawn eliminates 2 entire layers (driver + shader compiler) that were Heaps' biggest investments. Void's main work is the middle layers: rendering engine, scene graph, materials, assets.

## Key Heaps Design Decisions — Adopt or Skip

1. **Separate 2D + 3D scenes, composited** — ADOPT. Clean separation, 2D always on top.
2. **Pass-based materials** — ADOPT. Decouple shader from render state (blend, depth, cull).
3. **Composable shader fragments** — ADOPT (simplified). WGSL string concatenation or pre-written shader variants, not a full compiler.
4. ~~**Virtual filesystem**~~ — SKIP for now. Direct file loading. Add VFS when we need prod packaging.
5. **Interactive objects** — ADOPT LATER. Input routing to scene objects via hit testing. Needs scene graph first.
6. **Lazy transform evaluation** — ADOPT. Cache matrices, recompute only on change. Critical for performance.
7. **Object flags** — ADOPT. Bitfield for visibility, culled, allocated, etc. Fast checks.

## Build Priority for Void

Based on dependency order and practical impact:

1. **Asset loading** — textures (stb_image), meshes from files. Everything else needs content.
2. **Scene graph** — Object base class with parent-child hierarchy, transforms. Foundation for organizing the world.
3. **Material system** — shader + render state + textures per object. Enables visual variety.
4. **Renderer** — walk scene graph, sort by material/pass, emit draw calls. Replaces manual rendering.
5. **2D overlay** — text rendering at minimum (FPS, debug info).
6. **Animation** — skeletal or keyframe, once models can be loaded.
