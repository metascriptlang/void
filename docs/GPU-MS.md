# gpu-ms — hand-off for the Metal half (G6)

Branch `wt/gpu-ms` of void. This file is the brief a session on macOS starts from. The design
is `docs/GPU.md` on this branch; read it first, then this.

## Intent

Void stops depending on sokol. Everything it took from sokol (`sokol_gfx`, `sokol_app`,
`sokol_glue`, `sokol_time`, the `-f sokol` output of sokol-shdc) becomes Void's own GPU layer in
MetaScript, under `src/webgpu/`. The person's terms (2026-10-22):

- **The API reads and is written exactly like WebGPU / TypeGPU**: `device.createBuffer({ size,
  usage })`, `device.queue.writeBuffer`, `encoder.beginRenderPass`, bind groups, dynamic offsets.
  Only what Void calls exists; a WebGPU feature with no Void caller is left out.
- **Each backend is reached the way sokol reaches it**: chosen at compile time, one module per
  backend, no runtime interface. The body of each backend function is a port of sokol's
  `_sg_<backend>_*` at pin `2e75443d` (`deps/sokol`), traced with `/trace-ref`. A difference
  from sokol is written down with its reason (docs/GPU.md, and the backend module's comments).
- **Replace first, solidify after.** The end-game is the "Done when" below; then the person
  decides whether the branch merges. It is an experiment: never land it into `main`, never
  rebase `main` onto it. `main` stays on sokol.

- **The end-game is better than sokol, not equal to it** (the person, 2026-10-22): Void's own
  layer must beat sokol on performance and on the control it gives the caller. Following sokol's
  mechanism is how a backend starts; where sokol leaves speed or control on the table, Void goes
  further, and says so with the measurement.

Replacement done when: no file under `src/` includes a sokol header or calls
`sg_*`/`sapp_*`/`sglue_*`/`stm_*`, `deps/sokol` is not needed to build, and the goldens and both web
backends render as on main.

End-game done when, in addition:

- **Performance:** every `tests/bench` row is at least as fast on this branch as on `main` (sokol),
  same `msc`, same machine, quiet window, per backend; a row that is slower is a bug with its
  profile.
- **Control:** each thing a Void caller needs and sokol refuses is a WebGPU-shaped call here (for
  example a partial `writeTexture`, a GPU→CPU readback, a buffer bound at an offset), listed in
  docs/GPU.md with the caller that uses it.

## What the Windows half proved (as of `edeb348f`)

| target | backend | evidence |
|---|---|---|
| Windows | D3D11 (`src/webgpu/d3d11`) | door goldens 120/120 against `tests/golden/d3d11`; WARP check `src/test/webgpuD3d11Check.ms`; index 134 files / 1884 tests green at `b0be359b` |
| Windows | GL core 4.3 (`src/webgpu/gl`, `-d:voidGlCore`) | `src/test/webgpuGlCheck.ms` 304/304; `sh scripts/golden.sh --backend gl` 94 pass + 26 pending (within `tests/PENDING.md` budgets), 0 fail of 120 |
| Browser | WebGPU (`src/webgpu/wgpu`, `-d:webgpu`) | `scripts/build-web.sh`, headless Chrome shows the full void2d demo |
| Browser | WebGL2 (`src/webgpu/gl`, GLES3 path, `-d:webgl2`) | same page, same picture outside the animated node tree |
| Android | GLES3 (`src/webgpu/gl`, `OGL_GLES`) | check-only: NDK clang `-fsyntax-only` clean, `msc check --os=android` 114 modules; never linked or run |

On those targets nothing includes sokol any more. The windows are Void's own: Win32
(`src/platform/win32/`, ported from `sokol_app.h`), browser (`src/platform/web/`), Android EGL
(`src/sokol/bridgeAndroid.c`). The clock is `src/platform/clock.h` (sokol_time's four readings,
`mach_absolute_time` included).

## The map

```
void2d / void3d  (render layers, unchanged contract)
   │  door.h: flat descriptor words, uint32 ids, programs and layouts registered by index
src/gpu/doorGpu.ms        the door, MetaScript; C reaches it via @exportName (prototypes in door.h)
   │  uniforms: one 4 MiB buffer, 256-aligned dynamic offsets, group 0
   │  textures + samplers: group 1 bind groups from a cache (sokol's _sg_wgpu_bindgroups_cache)
src/webgpu/device.ms      the facade: `when` picks ONE backend module at compile time
src/webgpu/types.ms       WebGPU-named descriptors and handles (values, pool ids)
src/webgpu/<backend>/backend.ms + <backend>.{c,h}   logic in MetaScript, driver calls in thin C
src/platform/swapchain.h  the window hands the door its frame target (6 getters)
```

Shader modules are generated, not hand-written: `scripts/regen-shaders.sh` runs sokol-shdc with
`-f bare_yaml` and writes `src/void2d/shader2dModules.ms`, `src/void3d/programModules.ms`,
`tests/integration/gpuCopyModules.ms`. **They already carry MSL for `macos` and `ios`** (a
`when (macos)` / `when (ios)` branch per module), with `nativeSlot` = the MSL
`buffer`/`texture`/`sampler` index for each WebGPU binding. Regenerate on a Mac with the
`osx_arm64` shdc; `bash scripts/regen-shaders.sh --check` must say every output is fresh.

## G6 — what the Mac session builds

Port order follows the Windows one: the backend, then the window bridges, then the goldens.

1. **`src/webgpu/metal/`** — `backend.ms` + `metal.m` + `metal.h`, a port of `_sg_mtl_*`.
   - The backend exports the same 49 functions as `src/webgpu/d3d11/backend.ms` (`setup`,
     `shutdown`, `createBuffer` … `drawIndexed`, `swapchainTexture`, `liveCounts`, …) and the
     same `NativeEnvironment` / `NativeSwapchain` structs. Copy its shape; diff against the GL
     and D3D11 ones when a choice is unclear.
   - Objective-C methods cannot be called from MetaScript, so `metal.h` is opaque typedefs plus
     plain C prototypes, one per driver method, and `metal.m` implements them (docs/GPU.md
     "Native calls"; `d3d11.c`/`gl.c` are the pattern).
   - Uniforms: a real `MTLBuffer`, 256-byte alignment on macOS and 16 on iOS, bound with
     `setVertexBufferOffset`/`setFragmentBufferOffset` per block (sokol `:16958`, `:17557`).
   - Pass commands execute as they come, as sokol and the D3D11/GL backends do (docs/GPU.md "Why
     this shape", last bullet).
   - Fail loud: an unhandled descriptor value stops with a message naming the member.
   - `src/webgpu/device.ms`: add `else when (macos || ios) { import * as backend from
     "./metal/backend.ms"; }`.
   - A check like `src/test/webgpuD3d11Check.ms` / `webgpuGlCheck.ms`: `src/test/webgpuMetalCheck.ms`
     on the system default device, run on its own with `msc test` as those two are (they are
     not in `src/test/index.ms`, because they need a GPU).
2. **`src/sokol/bridgeEmbed.m`** (macOS: the Cocoa `voidRun` window and the host-view driver).
   It already owns its window and `CAMetalLayer`; only the GPU part moves.
   - `setupMetal` → `doorSetup((__bridge void*)g_device, NULL, DOOR_PIXEL_FORMAT_BGRA8, <depth>,
     samples)` + `doorValid()`.
   - `voidDriverSwapchain` / `voidPlatformSurfaceSwapchain` → the six `src/platform/swapchain.h`
     getters (render view = the MSAA texture when samples > 1, else the drawable's texture;
     resolve view = the drawable's texture when MSAA; depth view when there is one).
   - Patterns to copy: `src/sokol/bridgeWin.c` (`doorSetup` at :245, the getters at :513–542),
     `src/sokol/bridgeAndroid.c` (commit `7f3da43b`, a host-view driver onto the door),
     `src/sokol/bridgeWeb.c` (context loss → `doorShutdown` + `doorSetup`).
3. **`src/sokol/bridgeIos.m`** — the same move for the React-Native host views.
4. **`src/sokol/views.h` / `views.c`** — add `&& !defined(__APPLE__)` to the guards around
   `sg_swapchain` (they read `!_WIN32 && !__EMSCRIPTEN__ && !__ANDROID__` now); after that the
   `voidViewsSwapchain` branch is dead everywhere and can go.
5. **`src/sokol/gpu.ms`** — the `when (macos)` block drops `@link("./sokol.o")`; the
   `-I../../deps/sokol` line goes. Delete `src/sokol/sokol.m` and
   `scripts/build-sokol-macos.sh`.
6. **Goldens on Metal** — `tests/capture/capture.c` has no Metal readback (PENDING
   `backend:metal-macos`): read the drawable back through a blit to a shared `MTLBuffer`
   (`bridgeEmbed.m` `captureDrawable` already does it for a PPM). Then `scripts/golden.sh
   --backend metal` judged against `tests/golden/d3d11` under the cross-backend bound, like
   `--backend gl`; the D3D11 set stays the one authored set.

Verify on the Mac: `msc test src/test/webgpuMetalCheck.ms`, then the index
(`msc test src/test/index.ms`), then the Metal goldens, then the void2d demo
(`msc build src/examples/mainSokol2d.ms`) and the campfire example, looked at on screen. Before
claiming "sokol-free": `nm <exe> | grep -ci " _\?\(sg\|sapp\|sglue\|stm\|slog\)_"` must print 0.

## From the Mac (2026-10-22)

G6 steps 1–6 are committed (`7d6dcd0` … `738fe69`, msc BUILD `794e1579a`), not pushed until the
person says so. `webgpuMetalCheck` and the index are green; the void2d demo and campfire draw
under `MTL_DEBUG_LAYER=1` with no validation message; `nm` finds no sokol symbol.

- **Goldens:** `golden metal: 15 pass, 87 within bound, 18 fail of 120`. A sokol Metal build of
  the merge base with the same readback captured 58 of those rows byte-identical to this backend,
  so the 18 are the Apple GPU, not the port. How to record them waits for the person.
- **Shared files you pick up on rebase:**
  - `a32d4c0` `doorLiveBuffers` leaves the door's own uniform ring out. meshLod failed on Metal
    with "close left GPU resources live"; the ring is a `createBuffer` on every backend, so run
    meshLod on D3D11 and GL after the rebase.
  - `b8afcdb` ports your `7a2f63d` (pool exhausted → id 0) to Metal.
  - `738fe69` lets `texturedFrame` run its pixel checks on Metal readback (backend 5);
    deviceLoss3d passes all three presets there. The other 3D consumers still accept D3D11 only:
    `tests/capture3d/capture.c` reads back D3D11 alone, so gate3d on Metal needs a Metal capture3d
    first (Mac's next job).
- **Integration on the Mac** (gate flags): all pass except three that fail the same way on a
  sokol Metal build, so they predate this branch: retainedReplay hangs, viewPaint "stage 1:
  demoted background still paints", mrtBlend "backdrop normal is 2155937649". deviceLoss (svg,
  colour, both misuse modes) passes since `16ef580` gave `bridgeEmbed.m` `voidLoseContext`.
  colourSampler and fontPanel accept backends 1 and 4 by design; fbTrap exits 0 because macOS does
  not clamp a 1×1 window (sokol behaves the same).
- **For the Windows side:**
  - D3D11 `writeBuffer` (`src/webgpu/d3d11/backend.ms:858`) does not refuse a second write over
    bytes the frame already wrote; Metal stops there. Same sokol rule, enforced on one side only.
  - Per draw item, void3d calls `applyPipeline` and every uniform block again
    (`src/void3d/draw.ms:1598-1610`), and `doorApplyPipeline` always calls `setPipeline`
    (`src/gpu/doorGpu.ms:631`). Backend-independent; under the end-game it is a candidate to beat
    sokol, measured with a 3D bench row first, and it belongs on `main` as much as here.
- **References by layer** (checkouts on the Mac): sokol `2e75443d` for backend bodies; wgpu-hal
  (`~/projects/wgpu` `4fb3cca`) for WebGPU-to-native semantics and a future D3D12/Vulkan; Bevy
  (`2bddbdfd7`) for renderer mechanisms (its `batched_uniform_buffer.rs` caps uniform arrays at
  4 KB on WebGL2); Heaps (`25f9a88f`) for render concepts (`Engine.hx:90-111` picks its driver
  with `#if`, as `device.ms` does); Mach sysgpu (`4be8e50`) for the shader compiler.

## G7 — after Metal (either side, coordinated)

- The backend selector defines are still sokol's names (`SOKOL_WGPU`, `SOKOL_GLES3`,
  `SOKOL_GLCORE`, `SOKOL_D3D11`, `SOKOL_METAL`) in `src/sokol/backend.h`, `bridgeWin.c`,
  `bridgeWeb.c`, `src/platform/web/`, `tests/capture/capture.c`, `scripts/gate*.sh`,
  `scripts/golden.sh`. They are renamed once, after Metal, so `backend.h` is rewritten one time.
- `src/sokol/` becomes a name that says what it is now (bridges and views).
- sokol-shdc stays the shader compiler (`-f bare_yaml` only) until Void has its own emitter.

## Working together

- Two sessions share this branch: the Windows one (void-wt-gpu-ms) and the Mac one. The Mac
  owns `src/webgpu/metal/`, `src/sokol/{bridgeEmbed.m,bridgeIos.m,sokol.m,views.h,views.c,gpu.ms}`,
  `tests/capture/capture.c` and `scripts/build-sokol-macos.sh` until G6 lands; the Windows session
  stays off them. A change to a shared file (`doorGpu.ms`, `types.ms`, `device.ms`, generated
  modules) is small, committed alone and pushed promptly, so the other side rebases onto it.
- Commits: conventional subject only, no body, no attribution trailer.
- GPU runs on the Windows machine go through void-manager's GO; the Mac has its own schedule.
- A compiler bug is a card in `~/metascript/.inbox/compiler/` (smallest repro, park the site);
  nobody here edits recompiler.

## Known follow-ups (solidify, not blocking G6)

- D3D11 uploads every uniform block when any one is dirty. void3d re-applies every block per item
  after `applyPipeline` (`src/void3d/draw.ms` ~1600), so today it costs what sokol's per-slot
  update costs. Under the end-game it is a candidate to beat sokol: upload only the dirty block.
- `writeTexture` writes the whole texture only, as sokol's `sg_update_image` does. A partial write
  (WebGPU's `origin` + `size`) is control sokol lacks; build it when a caller (glyph atlas pages)
  can use it, with the bench row it moves.
- Attribute order against the writers is only checked in the GL build (where modules carry
  names); the goldens catch a reorder on the other backends.
- Android: GLES 3.2's `glColorMaski` is refused today (one mask for all targets); MSAA 2/8 untested.
- `src/examples/androidEntry.ms` calls `voidAndroidM2Run`, which nothing defines (older than this branch).
