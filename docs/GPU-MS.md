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
4. **`src/sokol/views.h` / `views.c`** — delete the `sg_swapchain` branch, so no platform
   (Linux included) reaches a sokol include.
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

G6 steps 1–6 are committed ("feat(webgpu): add the metal backend" onward, msc BUILD `794e1579a`)
and pushed to `wt/gpu-ms`. `webgpuMetalCheck` and the index are green; the void2d demo
and campfire draw under `MTL_DEBUG_LAYER=1` with no validation message; `nm` finds no sokol symbol.

- **Goldens:** `golden metal: 15 pass, 87 within bound, 18 fail of 120`. A sokol Metal build of
  the merge base with the same readback captured 58 of those rows byte-identical to this backend,
  so the 18 are the Apple GPU, not the port. How to record them waits for the person.
- **Bench (2026-10-23, M1, msc `794e1579a`):** 5 interleaved pairs, sokol Metal at the merge base
  `6d577fd` (plus `8b9c152`, which the current `msc` needs) against this backend. Every counter row
  passes; median `present.ms` (CPU of `scene.present`, GPU time not measured): ui 0.065 → 0.059,
  sprites 0.068 → 0.051, text 0.061 → 0.054, editor 0.064 → 0.050, scroll 0.076 → 0.077. The ranges
  overlap, so this shows no slowdown, not a win.
- **Shared files you pick up on rebase:**
  - "fix(gpu): leave the door's uniform ring out of the live buffer count": `doorLiveBuffers`
    leaves the door's own uniform ring out. meshLod failed on Metal with "close left GPU resources live"; the ring is a `createBuffer` on every backend, so run
    meshLod on D3D11 and GL after the rebase.
  - "fix(webgpu): return an invalid handle when a metal pool is exhausted" ports your `7a2f63d`
    to Metal.
  - "test(void3d): run the textured frame checks on metal readback" lets `texturedFrame` run its
    pixel checks on Metal readback (backend 5); deviceLoss3d passes all three presets there.
- **Integration on the Mac** (gate flags): all pass except three that fail the same way on a
  sokol Metal build, so they predate this branch: retainedReplay hangs, viewPaint "stage 1:
  demoted background still paints", mrtBlend "backdrop normal is 2155937649". deviceLoss (svg,
  colour, both misuse modes) passes now that `bridgeEmbed.m` has `voidLoseContext`.
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

### 2026-10-23

- **Goldens recorded:** the 18 Apple GPU rows are `golden:<scene>@metal` budgets in
  `tests/PENDING.md` (the person chose per-row budgets); on the 2026-10-22 captures the comparator
  gives `15 pass, 105 pending, 0 fail of 120`. A fresh run waits for the msc header fixes.
- **3D harness renamed:** `tests/capture3d/capture.{c,h}` is now `capture3d.{c,h}`, and
  `scripts/gate3d.sh` writes `@include("capture3d.h")`. Two headers named `capture.h`
  (`tests/capture/`, `tests/capture3d/`) in one program let the C compiler take the wrong one
  through the `-I` order; msc 2a4be982a changed that order and the textured entry stopped
  compiling. It also reads the macOS Metal drawable back now. Run gate3d once after the rebase.
- **3D consumers on Metal:** texturedFrame, unlitFrame, cameraRigFrame, perspectiveFrame,
  reparentFrame, gltfFrame, gltfColour and viewTeardown accept backend 5 and pass on the M1
  (gltf ones built with the msc before 2a4be982a, whose header bug they hit). Their frames do not
  match the D3D11 hashes in `docs/baselines3d.sha256`: that manifest is D3D11 bytes, and how
  gate3d judges a Metal frame is an open question for the person.
- **iOS from main:** the iOS app driver and its follow-ups (`a32dd50`, `3ac71dd`, `9d451e3`,
  `b6798c9`, `1a70a1c`, the demo `cb32d23`/`31de1bc` and its docs) are cherry-picked here.
  `src/platform/appEvent.h` gained `touchCount` and `touches[VOID_MAX_TOUCHPOINTS]`
  (`VoidTouchPoint`: identifier, x, y, changed), and `appWindow.c` the touch, safe-area and
  keyboard getters. The win32, linux and web drivers memset the event, so they report 0 touches;
  the Android driver (`86425bf`, yours) fills them when you pick it. `bridgeIosApp.m` builds
  `VoidAppEvent` and runs on the iOS simulator (iPhone 17 Pro, iOS 26.5): it draws, delivers
  focus/suspend/resume, and `loseContext()` rebuilds the door (generation 1 → 2). Touch and keys
  were not driven: the Mac has no tool here that taps the simulator.
- **Partial `writeTexture` on Metal stays refused**, with the measurement and the upgrade trigger
  in `docs/GPU.md` "Metal".

### 2026-10-23, main merged into the branch

The person's call: merge main in now, and land the whole branch as the step that retires sokol
everywhere. The merges take main up to `cc2dae57` (platform faces included). What changed
for you:

- **Frame admission from main (`e65f562a`):** `voidViewReady`/`viewReady`, and
  `voidPlatformSurfaceReady` in `frameView`. The D3D11 DXGI frame-latency waitable is
  `voidWindowAwaitFrame` in `windowSurface.h`. Metal's `tick` admits a frame through
  `presentGate.m` before `nextDrawable`. The simulator SDK has no `addPresentedHandler:`, so on
  the simulator the gate admits every frame.
- **Web MSAA from main:** `bridgeWeb.c` takes `voidViewsSampleCount()` for both views. The WGPU
  render view is the MSAA view when there is one, and `viewResolveView` gives the resolve target.
- **Kept deleted:** `src/gpu/door.c` and `shader2d.glsl.h`. Main's "no shader variant" message
  (`086de590`) has nothing to port, because a missing target is now a compile error: there is no
  `when` branch in the generated module.
- **Goldens:** main's single `conformance:metal-gpu-rounding` row is replaced by the branch's 18
  `@metal` budgets, which cover the same scenes. `regen-shaders.sh` reads its language list from
  `src/shader/program.ms` `SHDC_LANGUAGES`, as main does.
- **Capture:** `voidMetalReadDrawable` was the only macOS readback (since 26da77a9 the Apple capture reads through `doorReadScreen`). Main's sokol
  `voidWindowReadRgba` is gone, and `VOID_CAPTURE_SLOTS` is 3, as on main.
- **Measured on the Mac (msc `fce7770d3`):**
  - `msc test src/test/index.ms`: all-off 1931/1931, all-on 2323/2323.
  - `webgpuMetalCheck`: 304/304.
  - framePacing, layerSlot, paintedSlots, screenOver: PASS on Metal.
  - The iOS demo draws on the simulator.
  - `scripts/build-web.sh`: both backends built.
  - `nm` sokol count 0 on the mac and iOS builds.
- **Golden metal on the merged tree:** `15 pass, 105 pending, 0 fail of 120`. gltfColour and
  viewTeardown PASS on Metal. The other 3D frame consumers were not run this time: they need
  gate3d's generated entries.
- **`viewTeardown` was red after the merge, on main's side:** since main `65d44234` a
  `ForwardRenderer` holds two materials (copy and over), but the test checked for one.
  `3fc22de6` compares the survivor with the counts it had when it was made. On D3D11 the
  `views` row of gate3d should have been red the same way.
- **Metal adopts `src/webgpu/pool.ms`** (`31966549`): the same diff shape as D3D11. Pool
  exhaustion now stops by name instead of returning id 0.
- **Not measured on Windows:** the merged tree.
  - Please run your index and the WARP pins.
  - Watch `windowSurface.h`, `bridgeWin.c`, `windowGl.c` and `views.h`: they auto-merged the DXGI
    waitable.

### 2026-10-23, gate3d on Metal: please commit the 3D baseline images

The person chose how gate3d judges a Metal frame: as golden 2D does. The D3D11 frames are the
authored set, and a Metal frame passes within the cross-backend bound (docs/TESTING.md
"Guardrail 9") or within its own `golden3d:<baseline>_<frame>@metal` budget row in
`tests/PENDING.md`. That needs the D3D11 images, and only your machine renders them.

- **Ask:** commit `tests/golden3d/d3d11/<baseline>_<frame>.png` for every key in gate3d's
  `baseline_names` (18 baselines × frames 1 6 11 16, 320x240), converted from the
  `out/tmp/capture/<key>.ppm` copies whose SHA-256 matches `docs/baselines3d.sha256`. Please
  convert only a matching copy, and check that each PNG decodes back to those bytes. For a key
  `tests/PENDING3D.md` holds (`capture-m14forward`, `capture-m16anchor`), please also commit
  `<key>.held.png` from the frame whose hash is the row's held fingerprint. While the row holds,
  Metal is judged against what D3D11 draws now.
- **The Mac side:** gate3d's capture stage on Darwin compares against those PNGs instead of the
  hashes, through the 2D comparator's judgement and budget parsing. Until the PNGs exist, every
  Metal capture row fails and names the missing image.
- **Haro and Neon on the branch (Mac, msc `fce7770d3`):**
  - Haro builds and runs `--smoke` on Metal, and the shell answers. It drew 965 frames;
    the same Haro on main's sokol drew 991, and both drew 169 frames in 2 s of idle.
  - Neon `voidFrames`: 60 frames at a mean gap of 8.3 ms. An idle window draws nothing, and
    60 frames that change nothing draw 0.
  - Neon `voidDraw` draws and receives pointer input.
  - `nm` finds 0 sokol symbols in all three.

## From Windows (2026-10-23)

- **Coverage phases** (the person: coverage first, quality after). P0: the WebGPU members sokol
  exposes and Void lacked (formats, vertex formats, topologies, stencil, depth bias, sampler
  fields, mips, arrays, cube, 3d, view ranges, viewport, blend constant, stencil reference) are in
  `types.ms`/`device.ms`, and the reflection fields for storage and compute (`73b3703f`; arc
  `shader` fills them). P1: each backend ports P0. P2: copies and readback (`copyBufferToBuffer`,
  `copyTextureToBuffer`, `copyBufferToTexture`, `copyTextureToTexture`, mapped reads), the control
  sokol lacks. P3: compute and storage, once `shader` emits the reflection. P4: timestamps,
  labels, limits.
- **Where each backend is** (WARP pins in `webgpuD3d11Check.ms`, 410 tests; GL pins compile-only
  until a GO):

  | phase | D3D11 | GL | wgpu | Metal |
  |---|---|---|---|---|
  | P1 members | done | done | done | stops by name |
  | P2 copies, mapped reads | done | done | copies done; `mapAsync` stops (no ASYNCIFY) | stops |
  | P3 compute, storage | done | done (core 4.3, GLES 3.1; WebGL2 stops) | done | stops |
  | P4 limits, labels, debug groups, queries | done | done (WebGL2/GLES: no timestamps, occlusion 0/1) | done | stops |

  `mapAsync` blocks on native and `getMappedRange` returns a copy. `limits()` and `features()` are
  methods, so an unported backend stops only when asked.
- **For Metal:** a backend that has not ported a P0 member stops by name through the
  `stopOnUnported*` helpers in `types.ms`, so Metal keeps building; drop a helper call once Metal
  handles every member it guards (the D3D11 diff is the map). P2-P4 added backend functions; the
  Windows side committed Metal stubs that stop by name (`74b659a3`, `e19a6768`, `7499b938`), and
  Metal's `beginRenderPass` calls `stopOnUnportedRenderPass` so a `timestampWrites` or
  `occlusionQuerySet` is refused rather than ignored. Replace a stub when you port its call.
- **Window features:** `requestQuit`/`cancelQuit`, `frameDuration`, clipboard, cursors,
  `showMouse`, `lockMouse`, fullscreen and dropped files are in `src/sokol/window.ms` over
  `appWindow.c`. Windows, Linux (X11), the browser and Android implement them (Android gives what
  `sokol_app` gives there: an app-local clipboard, stored cursor and mouse state, no fullscreen, no
  drops); iOS stops by name (`notPortedIos` in `appWindow.c`). macOS and iOS are yours. The touch API is yours (`touchCount`, `identifier`); the
  browser driver now fills it.
- **Your two Windows items:** D3D11 `writeBuffer` already refuses a rewrite of bytes the frame
  wrote (`src/webgpu/d3d11/backend.ms`, `writeBuffer`, "rewrites bytes this frame already
  wrote"). The per-draw `applyPipeline` and uniform re-apply in void3d is queued as a beat-sokol
  row after the A/B bench.
- **Since `9968add0`, for Metal to follow** (each is a stop or a missing field on Metal today):
  - `GPURenderPassColorAttachment.depthSlice` (3d render attachments; 0 is slice 0) and
    `checkedDepthTexelCopy` in `types.ms` (WebGPU's depth copy rules) are used by D3D11, GL and wgpu.
  - Swapchain readback: the swapchain texture is `COPY_SRC`, and the door reads it with
    `doorReadScreen`/`doorReadTexture` (`src/gpu/doorGpu.ms`). `tests/capture*` switch to it next on
    Windows; the Apple branches of those files are yours.
  - `src/webgpu/pool.ms` is one generic handle pool (`0c9b0fe8`): D3D11 adopted it, GL and wgpu are
    adopting it now. Metal's `SlotQueue`/`allocateId`/`*Index` copy can go the same way (see the
    D3D11 diff of `0c9b0fe8`): pool exhaustion stops by name, and a slot at its last 16-bit
    generation is retired instead of reused.
  - From the shader arc (2026-10-23): a comparison sampler on Metal. `stopOnUnportedSampler`
    refuses `GPUSamplerDescriptor.compare` for Metal and `mtlNewSampler` takes no compare function;
    the need is `MTLSamplerDescriptor.compareFunction` (shader side prints `sample_compare`). D3D11,
    GL and wgpu already create comparison samplers.
- **Linux build in WSL:** `msc` there is synced to `4b5816aea`. Yoga has no linux branch, so
  build `libyoga.a` from `yoga/deps/yoga/yoga/**/*.cpp` with `zig c++ -std=c++20 -O2 -fPIC`
  (libc++, as msc links) and pass it with `--passL`.

## G7 — after Metal (either side, coordinated)

- Linux (Windows side, WSL2): `src/platform/linux/` (X11 + GLX, port of `_SAPP_LINUX`),
  `src/sokol/bridgeLinux.c` and the `when (linux)` block of `src/sokol/gpu.ms`. Cross-built from
  Windows (`msc build --os=linux` with WSL's GL/X11 headers and libs, Yoga built for linux by hand
  because `yoga/src/yogaH.ms` has no linux branch: note in `~/metascript/.inbox/yoga/`), it runs
  in WSLg on llvmpipe at 4b66e809 and draws the whole void2d demo. Linux goldens wait for a
  current `msc` in WSL.

- The backend selector defines were sokol's names until G7 (`SOKOL_WGPU`, `SOKOL_GLES3`,
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
- Since 2026-10-23 arc `shader` (branch wt/shader, rebased onto this one) owns `src/shader/` and the
  reflection format the backends read; a change to that format, `tools/shaderTables.ms` or
  regen-shaders is agreed with that arc's session first.
- Commits: conventional subject only, no body, no attribution trailer.
- GPU runs on the Windows machine go through void-manager's GO; the Mac has its own schedule.
- A compiler bug is a card in `~/metascript/.inbox/compiler/` (smallest repro, park the site);
  nobody here edits recompiler.

## Known follow-ups (solidify, not blocking G6)

- D3D11 binds each uniform block at its offset in the door's ring (`*SetConstantBuffers1`, no copy
  per draw) when the device has D3D11.1 constant-buffer offsetting, else uploads only blocks whose
  bytes changed; sokol uploads every applied block. Unmeasured until a GO.
- `writeTexture` takes WebGPU's `origin` + `size` (control sokol's whole-image `sg_update_image`
  lacks) on D3D11 (a `COPY_DST` texture is DEFAULT, written by `UpdateSubresource` with a box), GL
  (`glTexSubImage2D` in place; a whole write still rotates the copy) and wgpu. Metal stops on a
  write that is not the whole texture until it ports the same (`MTLRegionMake2D(x, y, w, h)` and
  the copy rotation only for a whole write). Its caller: a glyph page uploads only the union of
  the tiles written since its last upload (`doorUpdateTextureRect`); `batcher.c` keeps the
  whole-page upload under `__APPLE__` until Metal has the partial write. The DEFAULT texture's
  cost for a whole-texture stream is unmeasured until a GO.
- D3D11 skips a vertex buffer, index buffer, shader resource or sampler bind the context already
  holds (sokol re-issues all of them every apply); GL already caches them as sokol does. Both
  count the native binds they issue (`bindStats()`), pinned by the check files.
- Attribute order against the writers is only checked in the GL build (where modules carry
  names); the goldens catch a reorder on the other backends.
- Android: GLES 3.2's `glColorMaski` is refused today (one mask for all targets); MSAA 2/8 untested.
- Android: the app driver from `main` (`86425bf1`) delivers `VoidAppEvent` through `appWindow.c` and
  links with NDK 28 (`msc build src/examples/androidEntry.ms --os=android --app=lib --cc=<ndk>/toolchains/llvm/prebuilt/windows-x86_64/bin/aarch64-linux-android26-clang.exe`);
  it has never run on a device. Its window features other than `requestQuit` and `frameDuration` stop by name.

## A/B against main

`scripts/abBench.sh` provisions and `scripts/bench-ab.sh` measures (its protocol is docs/TESTING.md
"T4": interleaved pairs, load sampled on both sides of a run, NOISY pairs and `AB_MIN_CLEAN`).
The performance clause of "End-game done when" is read from the `tests/bench` entries
`Ui Sprites Text Editor Scroll`, built `--release` by one `msc` (`msc --version` and
`~/.metascript/BUILD` go to `$TEMP/voidAB/env.txt`) from side A, a detached worktree
`../void-ab-main` with `deps/` junctioned to the main checkout's, and side B, this tree.

```sh
bash ~/metascript/.wt/nim-audit/buildslot.sh sh scripts/abBench.sh build        # d3d11 and gl, CPU only
bash ~/metascript/.wt/nim-audit/buildslot.sh sh scripts/abBench.sh build linux  # both sides in WSL, CPU only
AB_BACKENDS="d3d11 gl linux" sh scripts/abBench.sh run 5                         # opens windows: only inside a granted GO
AB_BACKENDS=linux AB_LINUX_DRIVER=llvmpipe sh scripts/abBench.sh run 5          # the software-GL alternative
sh scripts/abBench.sh clean                                                     # deletes $TEMP/voidAB and the main worktree
```

- **Side A** is `git merge-base HEAD main` by default, so a delta measures the GPU layer and not void2d
  commits main gained since; both shas print. `AB_MAIN_SHA=main` (or any sha) overrides it, and a
  re-run of `build` moves the worktree to it.
- **Flags** per backend: d3d11 none; gl `-d:voidGlCore` plus `--passC=-DSOKOL_GLCORE` on A and
  `-DVOID_GLCORE` on B (each tree's golden runner define); linux `--os=linux` and a `libyoga.a`
  built once from `yoga/deps/yoga` by `zig c++` (yoga has no linux link line,
  `~/metascript/.inbox/yoga/`). Windows exes land in `$TEMP/voidAB/<backend>/<side>/`; Linux exes in
  WSL's `~/voidAB/<side>/`, which is not under `/mnt/c`, with the trees read through `/mnt/c`.
- **Rows**: `bench-ab.sh` with `AB_RAW` keeps every bench row of every run and prints, per scene and
  label, the median of the clean pairs. A `.ms` row is `RED` when B is more than `AB_TOL` (3 %)
  slower than A; a counter that differs is `DIFF` (a higher `draws`, `uploads` or `uploadBytes` is a
  regression; read it); a row one side lacks is `ONLY-A`/`ONLY-B`; identical counters are counted,
  not listed. The `present.ms` verdict lines and the arguments of existing callers are unchanged.
  Raw rows: `$TEMP/voidAB/raw-<label>.tsv`.
- **Linux driver**: `GALLIUM_DRIVER=d3d12` (Mesa's d3d12 on the real GPU, the default) or
  `AB_LINUX_DRIVER=llvmpipe`, set by a wrapper in `~/voidAB`. Before the rows, `glxinfo -B` runs under
  the same wrapper; a renderer string that is not D3D12 (or llvmpipe) voids the whole Linux row and
  says so, and the string heads the table. The bench exes print no renderer themselves.
  Load sampling is the Windows CPU counter of `bench-ab.sh`; the WSL VM's own load is not sampled.

Not covered:

- **Linux side A:** main has no Linux window path, so `build linux` fails on A (a compile error in
  `src/gpu/door.c`, no Linux backend define) and `run` skips Linux with that reason: the Linux
  rows exist on B only and no A/B is possible until main grows one or the comparison is made
  against another Linux baseline.
- **Web (wgpu, webgl2):** no bench path runs in a browser; `scripts/webGolden.mjs` and
  `web-liveness.sh` judge pixels and liveness, and `tests/bench/wasm.json` is a size record.
- **Metal:** another machine and another GO.
- **Particles and module scenes:** `benchParticles.ms` is on main's tip only, and TextEmoji,
  TextOutline and TextSdf need module defines; `AB_SCENES` can name them but the build passes none.
