# Void — Cross-Platform GPU Rendering on its own WebGPU-shaped layer (WebGPU + WebGL2 + native)

Write GPU code once in MetaScript, run everywhere — Desktop, Mobile, Browser (WebGPU **and** WebGL2), VR/XR.
Written in MetaScript (TypeScript superset that compiles to C, JS, WASM).

**Void is an opt-in, powerful GPU backend for Neon** (~/metascript/neon — a native UI framework like React Native, no JS runtime). Neon already has its own default renderer (maps to native components, lightweight, used by every app). Void is the heavier backend an app **opts into** when it needs raw GPU power: games, 3D, shader-driven UI, canvas-style custom rendering, data-viz. Void is allowed to be a bit heavier than Neon's default — that is its reason to exist.

## Direction: Dawn → sokol → Void's own layer

- **2026-06, Dawn → sokol_gfx.** Web must be first-class including old browsers, and Dawn on the web (`emdawnwebgpu`) is WebGPU-only with no WebGL2 fallback. sokol covered the whole matrix from one C codebase; wgpu was rejected because its WebGL fallback is Rust/wasm-bindgen only, bgfx because it had dropped WebGPU.
- **2026-10, sokol → Void's own WebGPU-shaped layer** (arc `gpu-ms`, branch `wt/gpu-ms`). Why, and every call sokol refused that a Void caller needs: `docs/GPU.md`. sokol at pin `2e75443d` stays the reference for the mechanism: each backend body is a port of the matching `_sg_<backend>_*` function, and `src/platform/` ports `sokol_app`. `deps/sokol` (fetched by `setup.sh`) is kept so those comments can be read; no Void build includes it, and only `scripts/wasmModuleDelta.sh` copies `sokol_gfx.h`, for a baseline ref from before the switch.

**Void's scope discipline (load-bearing):** Void = a **thin GPU layer** (the "narrow waist"), NOT a game engine. No scene graph, ECS, physics, asset pipeline. UI-helpers (2D primitives, text) and game-helpers (camera, mesh, material) are **layers ABOVE Void**, pulled in per use case. This is what keeps Void "a bit heavier than Neon-default" from drifting into "Unity".

## Architecture

```
src/
├── webgpu/   device.ms, types.ms, validate.ms, pool.ms + one dir per backend
│             ← the WebGPU-shaped device; shared validation runs before every backend
├── gpu/      door.ms, doorGpu.ms, pipeline.ms, ...  ← the door: what void2d/void3d call
├── host/     bridge.{h,c}, bridge<Platform>.*, appWindow.c, gpu.ms, window.ms
│             ← per-platform host: window, frame loop (voidRun), embedding
├── platform/ windowCore.h + macos/ win32/ linux/ web/  ← window core ported from sokol_app
├── shader/   shader IR and its printers (WGSL, GLSL, HLSL, MSL, SPIR-V)
├── void2d/   2D batcher + Node2D tree      void3d/  3D scene layer      particles/
├── assets/   math/                          ← helpers
└── examples/ main2d, mainCampfire, ...     ← thin entries
```

Backend per build, chosen at compile time in `src/webgpu/device.ms`:

| Target | Backend (`src/webgpu/…`) | Flag |
|---|---|---|
| macOS, iOS | `metal/` | default |
| Windows | `d3d11/` | default; `-d:voidGlCore` → `gl/`, `-d:voidVulkan` → `vulkan/` |
| Linux, Android | `gl/` | default; `-d:voidVulkan` → `vulkan/` |
| Browser, new | `wgpu/` (WebGPU) | `--os=emcc -d:webgpu` |
| Browser, old | `gl/` (WebGL2, ~97-98% coverage) | `--os=emcc -d:webgl2` |
| Tests without a GPU | `dummy/` | `-d:voidDummy` |

Build with **`msc`** — the synced local build on `$PATH` (`~/.metascript/bin/msc`). Native: `msc build src/examples/main2d.ms`. Web: **`scripts/build-web.sh`** (override with `MSC=…`) pins emscripten to `.emscripten-version`, builds both backends, deploys to `web/{wgpu,gl}/`; `web/void2d.html` loads `wgpu/` when `navigator.gpu` exists, else `gl/` (`?gl` / `?wgpu` force). **The emscripten pin is load-bearing:** under sokol an older emdawnwebgpu port's WGPU enums skewed against the headers, the swapchain depth format resolved to `BC3RGBAUnormSrgb` and WebGPU rendered black. A stray `emsdk activate <older>` re-introduces the risk; the build script re-activates the pin.

## Key Design Decisions

1. **Layered, thin entries** — `src/examples/*.ms` are thin entries (`voidRun(...)` + init/frame closures). One source compiles to native and both web backends.
2. **A WebGPU-shaped device of our own** — the surface reads like WebGPU (`docs/GPU.md` "What the author writes"); checks that every backend shares live once in `src/webgpu/validate.ms`, and a backend only translates.
3. **Void = opt-in backend for Neon, not Neon's default.** Only opted-in apps pay Void's weight.
4. **Two web builds, runtime feature-detect.** One wasm carries one backend, so old and new browsers get two artifacts and a small JS loader.
5. **Void owns the window.** `src/platform/` and `src/host/` replace `sokol_app`; the host owns the device and swapchain on every platform.
6. **Shaders are MetaScript functions** — lowered by macros to Void's shader IR and printed per backend with their reflection. See [docs/SHADER.md](docs/SHADER.md) and [docs/SHADER-IR.md](docs/SHADER-IR.md).
7. **`.wms` extension** — WASM/browser-specific MetaScript. Compiler resolves `.wms → .cms → .ms` for `--os=emcc`/`--os=wasm`.
8. **Rendering/GPU layer only** — no scene graph, ECS, physics, audio, asset pipeline, editor.

## Current Implementation

- **Device** `src/webgpu/` — `device.ms` runs the shared checks in `validate.ms`, keeps ids in `pool.ms`, then calls the backend. Design and measured costs: `docs/GPU.md`; the Windows/Mac channel for the arc: `docs/GPU-MS.md`.
- **Door** `src/gpu/` — the calls `void2d` and `void3d` make (`doorGpu.ms`); pipelines are cached by key in `pipeline.ms`.
- **void2d** `src/void2d/` — batcher logic in MetaScript (`draw.ms`), thin C in `batcher.c`, text via fontstash. See [docs/VOID2D.md](docs/VOID2D.md); 3D: [docs/VOID3D.md](docs/VOID3D.md).
- **Shaders** are MetaScript functions (`src/void2d/shader2d.ms`, `src/void3d/shader3d.ms`); `scripts/regen-shaders.sh` prints the generated modules, `--check` fails when one is stale. An app's own program uses `shaderProgram` (`src/shader/program.ms`) with no regen step.
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

- **Naming**: **camelCase** for files, variables, functions, and C-bridge functions (e.g. `main2d.ms`, `voidCubeInit`, `voidGfxSetup`); PascalCase for types. No snake_case.
- **Files**: camelCase filenames (e.g. `main2d.ms` — NOT `main_2d.ms`), one primary type per file
- **GPU resources**: Always pair create/destroy, use `defer` for cleanup
- **Error handling**: Result types + `try` for fallible GPU operations
- **No `any`**: Use `unknown` with narrowing
- **C bridge pattern**: flattened params; GPU handles as `uint32` ids. **Buffer data IS passable from MetaScript** — a packed sized array (`float32[]`/`Vec<float32>`, native-size) hands its data pointer via `arr[0]` → `Borrow<float32>` C param (borrow-promotion). Do NOT pass through `unknown`/`Ptr<void>` (codegen derefs → wrong).
- **C compilation**: `import {..} from "./x.h"` auto-compiles companion `x.c` AND maps `const char*`→string / `const T*`→`Borrow<T>` — use for non-closure C funcs. Closure-taking funcs (`()=>void`) need `@include`+`@compile`+`extern function` (import-from-.h mis-types closures). Never both on one .c (dup symbols).
- **`@passC` / `@passL` / `@link` are module-relative** — a relative path resolves against the directory of the module that declares the directive (measured 2026-09-20 on `msc` build `94c23bfd`: `-I./inc` declared in `lib/x.ms` fails, `-I../inc` works, absolute works). A relative `#include "../../deps/..."` inside a `.c` avoids needing `-I` at all.
- **Layering**: `src/webgpu/` (device) → `src/gpu/` (door) → `src/void2d/`, `src/void3d/` → `src/examples/` (demos); `src/host/` and `src/platform/` give the window and frame loop. One-way deps. Keep Void thin (no scene graph/ECS/physics — those are layers above).

## Git and the gate

Void follows the worktree playbook enabled by `~/metascript/CLAUDE.md` and uses `~/nerdtools/claude/tools/wt.sh` with the gate below. Shared session context reads this repo's card and `~/metascript/.inbox/void/`. A compiler or runtime limitation follows the workspace compiler boundary: repro, card in `~/metascript/.inbox/compiler/`, park, move on.

The gate is `scripts/gate.sh` (`docs/TESTING.md` "The gate"): its T0 runs `msc test src/test/index.ms` with module stages all-off and all-on, Yoga layout included (`src/test/layoutCheck.ms`), then the golden suite and the bench. Choose checks by the change's effect: the index covers logic, and a change to the GPU or web path also runs `scripts/build-web.sh` and is looked at on the page, because green on native is not evidence for emcc, which is stricter.

Choose how a land is gated by what the gate can observe. When the change reaches code the gate compiles or runs (shared `.ms`, C built for the native target, `src/test/`, goldens, the bench), the land runs the whole gate, because a red there is only found by the whole run. When the gate cannot observe the change (emcc-only C such as `bridgeWeb.c`, web test scripts and pages, docs), land with `--no-gate` after the checks that do observe it went green, and write in the card what ran and what did not, because the gate would spend its run proving nothing new. In doubt, run the gate.

## Known Limitations / Considerations

- **Backend chosen at compile time** → two web builds (WebGPU + WebGL2) + a JS feature-detect loader to cover old+new browsers from one source.
- **No WebGL1** — the floor is GLES3/WebGL2 (~97-98% coverage).
- **WebGL2 has no compute**; compute runs on Metal, D3D11, GL 4.3, Vulkan and WebGPU.
- **Vulkan's ceilings** (queries, lost-device recovery, MSAA canvas, ...) are listed in `docs/GPU-MS.md` under the Vulkan entries.

## Key References

- sokol at pin `2e75443d` (`deps/sokol`): the reference for each backend body and for `src/platform/` — https://github.com/floooh/sokol
- WebGPU spec: https://www.w3.org/TR/webgpu/ · WGSL: https://www.w3.org/TR/WGSL/
- MetaScript compiler: ~/metascript/recompiler (CLAUDE.md: ~/metascript/recompiler/CLAUDE.md)
- Neon (parent UI framework): ~/metascript/neon
