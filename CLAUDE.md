# Void — Cross-Platform GPU Rendering via sokol_gfx (WebGPU + WebGL2 + native)

Write GPU code once in MetaScript, run everywhere — Desktop, Mobile, Browser (WebGPU **and** WebGL2), VR/XR.
Written in MetaScript (TypeScript superset that compiles to C, JS, WASM).

**Void is an opt-in, powerful GPU backend for Neon** (~/metascript/neon — a native UI framework like React Native, no JS runtime). Neon already has its own default renderer (maps to native components, lightweight, used by every app). Void is the heavier backend an app **opts into** when it needs raw GPU power: games, 3D, shader-driven UI, canvas-style custom rendering, data-viz. Void is allowed to be a bit heavier than Neon's default — that is its reason to exist.

## Direction (2026-06): Dawn → sokol_gfx ✅ DONE

**The Dawn/WebGPU GPU layer has been REPLACED with [sokol_gfx](https://github.com/floooh/sokol).** Dawn is fully removed (`deps/dawn`, `deps/sdl3webgpu`, `src/dawn`, `src/gpu`, `src/platform`, the SDL3-based entries — all deleted). sokol is now THE GPU layer. The rationale below is kept as the record of why.

**Why the switch:**
- **Web must be first-class, including old browsers.** Browsers without WebGPU (older Safari, in-app webviews, locked corporate, old Android Chrome) only have WebGL2. Dawn on web = `emdawnwebgpu`, a thin shim to `navigator.gpu` — **WebGPU-only, no WebGL fallback**. So Dawn structurally cannot cover old browsers.
- **sokol covers the whole matrix from one pure-C codebase** that fits Void's `MetaScript → C → emscripten` pipeline: WebGPU + WebGL2 on browser, Metal/D3D11/GL/Vulkan on native. (wgpu was rejected because its WebGL-fallback path is Rust/wasm-bindgen only; `wgpu-native` + emscripten is unmaintained/closed upstream.)
- **sokol is production-proven** (shipped Steam + web games; endorsed by Aras Pranckevičius; author = 20-yr game-tech veteran Andre Weissflog), **lighter than Dawn**, pure C single-header (clean MetaScript FFI), and its **WebGPU backend is more mature than bgfx's right now** (bgfx removed WebGPU in 2023, re-adding in 2026; sokol has shipped WebGPU since 2023 + compute since 2025).
- bgfx was the runner-up; sokol won on lightweight + web/WebGPU-forward + easiest binding. bgfx's only edges: bigger community + WebGL1 (ancient devices, ~2-3% tail).

**Void's scope discipline (load-bearing):** Void = a **thin GPU layer** (the "narrow waist"), NOT a game engine. No scene graph, ECS, physics, asset pipeline. UI-helpers (2D primitives, text) and game-helpers (camera, mesh, material) are **layers ABOVE Void**, pulled in per use case. This is what keeps Void "a bit heavier than Neon-default" from drifting into "Unity".

## Status (sokol — working, all native Metal + browser WebGPU + browser WebGL2)

- **3D cube** — `src/examples/{mainSokol,rendererSokol}.ms`: textured spinning cube. Geometry is **pure-MetaScript** `Vec<float32>`/`Vec<uint16>` (`src/examples/cubedata.ms`) — no C data file; the packed array's data pointer is handed to sokol via borrow-promotion (`cubeVertices[0]` → `Borrow<float32>`).
- **2D layer `void2d`** — `src/void2d/` + `src/examples/{mainSokol2d,renderer2d}.ms`: unified 2D batcher (filled rects, textured sprites, text via fontstash). **Batcher LOGIC lives in MetaScript** (`draw.ms` owns a `Vec<float32>` vertex buffer + quad/glyph geometry + flush); C (`batcher.c`) is thin sokol/fontstash primitives. Retained **`Node2D`** tree with translate + scale + alpha inheritance (`node.ms`) — the host for the planned JSX/Solid reconciler. See [docs/VOID2D.md](docs/VOID2D.md), [docs/VOID3D.md](docs/VOID3D.md).
- **Windowing:** native uses **`sokol_app`** (`sapp_run`, driven from MetaScript via `voidRun(w,h,init,frame)`), NOT SDL3. Web uses sokol_app's emscripten canvas loop.
- **Next:** rotation in `drawNode` (needs sin/cos + arbitrary-corner quads); swap the placeholder caps-only font; then build the JSX/Solid reconciler onto `Node2D`. Optional: wire as Neon's opt-in backend.

## Architecture (sokol)

```
src/
├── sokol/    bridge.{h,c}, gpu.ms, gpu.wms, sokol.m, sokolWeb.c, shader.glsl(.h)
│             ← GPU layer: thin sokol_gfx + sokol_app primitives (the "narrow waist")
├── void2d/   draw.ms, node.ms, types.ms, batcher.{h,c}, shader2d.glsl(.h)
│             ← 2D layer: batcher + Node2D tree (LOGIC in MetaScript; C = sokol/fontstash glue)
├── assets/   image.{h,c}, image.ms      math/  mat4.{h,c}, mat4.ms      ← helpers
└── examples/ mainSokol2d, renderer2d, mainSokol, rendererSokol, cubedata .ms  ← demos/entries

msc ──┬── --os=darwin → C + clang   (-DSOKOL_METAL; sokol.m precompiled → sokol.o @link'd; bridgeEmbed.m @compile'd by msc)
      └── --os=emcc   → C + emcc, TWO builds (sokol backend is compile-time):
            -DSOKOL_WGPU  → web/wgpu/   (WebGPU)
            -DSOKOL_GLES3 → web/gl/     (WebGL2, -sFULL_ES3=1 -sMAX_WEBGL_VERSION=2)
      web/index.html (cube) · void2d.html: navigator.gpu? → load wgpu/ else gl/  (?gl / ?wgpu force)
```

Build with **`msc`** — the synced local build on `$PATH` (`~/.metascript/bin/msc`, kept current via the recompiler's `tools/sync-local-binary.sh`). It is a `--gc=drc` build (no ORC cycle collector → immune to the ORC-collector heisenbug that the old `bin/msc-const` hit on large frames), and resolves `std/` relative to its install dir so it works from any project CWD. Native: `msc build src/examples/mainSokol2d.ms`. Web: run **`scripts/build-web.sh`** (uses `msc`; override with `MSC=…`) — it pins emscripten to `.emscripten-version` (currently **5.0.5**), builds both backends, deploys to `web/{wgpu,gl}/`, and retries the build (msc can flake on the uncached async-emcc path). **The emscripten pin is load-bearing:** vendored sokol (deps/sokol) uses recent WGPU enums (`R16Unorm`, `TextureFormatsTier1/2`); an older emscripten's emdawnwebgpu port lacks them → enum skew → swapchain depth format resolves to `BC3RGBAUnormSrgb` → WebGPU renders black ("[Invalid TextureView] … depthStencilAttachment"). A stray `emsdk activate <older>` re-introduces this; the build script re-activates the pin to prevent it.

### Platform Targets (sokol backends)

| Platform | sokol backend (`#define`) | Entry | Notes |
|---|---|---|---|
| macOS | Metal (`SOKOL_METAL`) | `main.ms` + SDL3 | |
| iOS | Metal (`SOKOL_METAL`) | `main.ms` | |
| Windows | D3D11 (`SOKOL_D3D11`) | `main.ms` + SDL3 | (sokol uses D3D11, not D3D12) |
| Linux | GL (`SOKOL_GLCORE`) | `main.ms` + SDL3 | Vulkan backend exists but experimental |
| Android | GLES3 (`SOKOL_GLES3`) | `main.ms` | |
| Browser (new) | WebGPU (`SOKOL_WGPU`) | `main.wms` + canvas | build A |
| Browser (old) | WebGL2 (`SOKOL_GLES3`) | `main.wms` + canvas | build B, ~97-98% coverage |
| VR/XR (native) | Vulkan/D3D + OpenXR | planned | |
| VR/XR (browser) | WebXR + WebGPU | planned | |

### Key Design Decisions

1. **Layered, thin entries** — GPU code in `src/sokol/` + `src/void2d/`; `src/examples/*.ms` are thin entries (`voidRun(...)` + init/frame closures). One source compiles to native + both web backends.
2. **sokol_gfx as the GPU layer** — pure C single-header, zlib license, backends Metal/D3D11/GL/Vulkan/WebGPU/WebGL2, web-first design, prod-proven, lighter than Dawn, fits `MetaScript → C → emscripten`.
3. **Void = opt-in backend for Neon, not Neon's default.** Neon-default = native components (light, every app). Void = heavy opt-in (games/GPU). Only opted-in apps pay Void's weight.
4. **Two web builds, runtime feature-detect.** sokol picks its backend at **compile time** (`SOKOL_WGPU` vs `SOKOL_GLES3`), so a single wasm = one backend. To cover old+new browsers, ship **two wasm artifacts** and a small JS loader that checks `navigator.gpu` and loads the WebGPU build, else the WebGL2 build.
5. **sokol_app for windowing (native + web).** The implementation uses `sokol_app` (`sapp_run` via `voidRun`) on both native and web — bare-bones is fine for the demos, swapchain via `sglue_swapchain()`. (SDL3 was the original plan but proved unnecessary; revisit if desktop needs richer input.)
6. **Shaders via sokol-shdc** — author annotated GLSL (`@vs`/`@fs`/`@cs`, separate `texture`+`sampler`), cross-compile offline to GLSL/GLES/HLSL/MSL/**WGSL** + a generated shader-desc header. Replaces the WGSL-only pipeline.
7. **`.wms` extension** — WASM/browser-specific MetaScript. Compiler resolves `.wms → .cms → .ms` for `--os=emcc`/`--os=wasm`.
8. **Rendering/GPU layer only** — no scene graph, ECS, physics, audio, asset pipeline, editor. (See scope discipline above.)
9. **Binding generation** — sokol auto-generates bindings for Zig/Nim/Odin/Rust/D/C3/Jai from a machine-readable API description. Follow the same pattern to generate MetaScript externs from `sokol_gfx.h` instead of hand-writing each function.

## Migration (Dawn → sokol) — ✅ COMPLETE

Done: sokol + fontstash headers vendored (`deps/sokol/`, `deps/fontstash/`); C bridges `src/sokol/bridge.*` + `src/void2d/batcher.*`; MetaScript GPU layer `src/sokol/gpu.{ms,wms}`; renderer ported to sokol_gfx (views/passes/pipelines/bindings); shaders via sokol-shdc; native windowing via **sokol_app** (sokol_app replaced the planned SDL3 — bare-bones is fine here); two emcc web builds + JS loader; **Dawn fully removed**.

## Current Implementation (sokol)

- **GPU bridge** `src/sokol/bridge.{h,c}` — flattened params, sokol handles as `uint32` ids; `voidRun(w,h,init,frame)` → `sapp_run`. `gpu.ms` (native: frameworks + `@link sokol.o` + `@compile bridgeEmbed.m`) / `gpu.wms` (web: `@compile sokolWeb.c`) wrap it with `extern function` (explicit types — needed because `voidRun` takes closures, which import-from-.h mis-types).
- **void2d batcher** `src/void2d/batcher.{h,c}` — sokol pipeline/buffer + fontstash (raw `fontstash.h` + `stb_truetype.h`); exposes `void2dUploadDraw` + the fontstash glyph iterator. `draw.ms` owns the `Vec<float32>` vertex buffer + geometry and imports the C primitives via **import-from-.h** (cleanly handles its `const char*`/`const float*` params; no closures here).
- **Shaders** in sokol-shdc dialect (`shader.glsl`, `void2d/shader2d.glsl`); regen: `scripts/regen-shaders.sh` (or inline: `deps/sokol-tools-bin/bin/osx_arm64/sokol-shdc -i X.glsl -o X.glsl.h -l metal_macos:glsl300es:wgsl -f sokol`).
- **GPU data in MetaScript:** sized typed arrays (`float32[]` / `Vec<float32>`) are packed native-size; hand `arr[0]` to a `Borrow<float32>` C param (borrow-promotion) — no C data files, no malloc. Only `number[]` is `double`-backed.

## MetaScript Essentials

- TypeScript syntax compiling to C and JS
- Sized integers: `int8`-`int64`, `uint8`-`uint64`, `float32`/`float64`
- `type` is a **reserved word** — use `nodeType`, `bufferType` etc.
- Move semantics: `move resource`, `defer cleanup()` (LIFO on scope exit)
- Match expressions: `match value { ... }`
- Result type with `try`: `const buf = try createBuffer(desc);`
- DRC memory management (deterministic refcount + ORC cycle collector)
- C FFI via `extern function` declarations
- Compiler decorators: `@include`, `@compile`, `@passC`, `@passL`, `@link`, `@emit`, `@derive`, `@comptime`, `@sizeof`
- `.ms` = general, `.cms` = C-only, `.jms` = JS-only, `.wms` = WASM/browser-only

## Conventions

- **Naming**: **camelCase** for files, variables, functions, and C-bridge functions (e.g. `mainSokol.ms`, `voidCubeInit`, `voidGfxSetup`); PascalCase for types. No snake_case.
- **Files**: camelCase filenames (e.g. `mainSokol.ms` — NOT `main_sokol.ms`), one primary type per file
- **GPU resources**: Always pair create/destroy, use `defer` for cleanup
- **Error handling**: Result types + `try` for fallible GPU operations
- **No `any`**: Use `unknown` with narrowing
- **C bridge pattern**: flattened params; sokol handles as `uint32` ids. **Buffer data IS passable from MetaScript** — a packed sized array (`float32[]`/`Vec<float32>`, native-size) hands its data pointer via `arr[0]` → `Borrow<float32>` C param (borrow-promotion). Do NOT pass through `unknown`/`Ptr<void>` (codegen derefs → wrong).
- **C compilation**: `import {..} from "./x.h"` auto-compiles companion `x.c` AND maps `const char*`→string / `const T*`→`Borrow<T>` — use for non-closure C funcs. Closure-taking funcs (`()=>void`) need `@include`+`@compile`+`extern function` (import-from-.h mis-types closures). Never both on one .c (dup symbols).
- **`@passC` / `@passL` / `@link` are module-relative** — a relative path resolves against the directory of the module that declares the directive (measured 2026-09-20 on `msc` build `94c23bfd`: `-I./inc` declared in `lib/x.ms` fails, `-I../inc` works, absolute works). A relative `#include "../../deps/..."` inside a `.c` avoids needing `-I` at all.
- **Layering**: `src/sokol/` (GPU) → `src/void2d/` (2D batcher + `Node2D`) → `src/examples/` (demos). One-way deps. Keep Void thin (no scene graph/ECS/physics — those are layers above).

## Git and the gate

Void follows the arc model of `~/.claude/CLAUDE.md` and lands with the plain-git recipe of `~/metascript/CLAUDE.md` §Arcs. A compiler or runtime limitation follows the workspace compiler boundary: repro, card in `~/metascript/.inbox/compiler/`, park, move on. A session started here reads `~/metascript/.inbox/void/` first.

The gate is both test entries, native: `msc test src/test/index.ms` (scene, node, transform, graphics, effect, text, tile) and `msc test tests/layout.test.ms` (yoga through `deps/yoga`). A change to the GPU or web path also runs `scripts/build-web.sh` and is looked at on the page: green on native Metal is not evidence for emcc, which is stricter.

Measured 2026-09-20 on `msc` build `94c23bfd`: **both entries are red**, one void-side (`src/void2d/render.ms:297` mutates the value parameter `out`), one a compiler internal error; both are in `~/metascript/.inbox/void/2026-09-20-agent-setup-review.md`. Until they are fixed, a commit here carries the evidence it can run and says which entry it could not.

## Known Limitations / Considerations (sokol)

- **Backend chosen at compile time** → two web builds (WebGPU + WebGL2) + a JS feature-detect loader to cover old+new browsers from one source.
- **No WebGL1** — sokol's floor is GLES3/WebGL2 (~97-98% coverage). Truly ancient WebGL1-only devices are unsupported (this was bgfx's one edge).
- **Single maintainer** (floooh) and **periodic breaking API changes** (compute, resource views, etc.) → regenerate bindings on update. Auto-gen mitigates the churn.
- **No GPU→CPU readback yet** in sokol (compute results can't be copied back to CPU; planned, no ETA). Rarely needed for render/UI.
- **Cross-backend common denominator** — sokol won't expose WebGPU-exclusive bleeding-edge features that can't be emulated on D3D11/Metal/GL. Acceptable for a UI + game render layer.
- **Compute is recent (2025)** and less battle-tested than the render path; WebGL2 has no compute (Metal/D3D11/GL4.3/WebGPU only).

## Key References

- sokol: https://github.com/floooh/sokol — docs in the header comments; samples: https://github.com/floooh/sokol-samples
- sokol-shdc (shader compiler): https://github.com/floooh/sokol-tools
- sokol_gp (2D on sokol_gfx): https://github.com/edubart/sokol_gp · NanoVG sokol backend: https://github.com/vinnyhorgan/nanovg
- floooh's blog (design rationale, updates): https://floooh.github.io
- MetaScript compiler: ~/metascript/recompiler (CLAUDE.md: ~/metascript/recompiler/CLAUDE.md)
- Neon (parent UI framework): ~/metascript/neon
- WebGPU spec: https://www.w3.org/TR/webgpu/ · WGSL: https://www.w3.org/TR/WGSL/
