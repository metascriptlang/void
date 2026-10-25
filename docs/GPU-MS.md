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

Shader modules are generated, not hand-written: `scripts/regen-shaders.sh` runs
`tools/irPrograms.ms`, which prints them from the shader IR, and writes `src/void2d/shader2dModules.ms`, `src/void3d/programModules.ms`,
`tests/integration/gpuCopyModules.ms`. **They already carry MSL for `macos` and `ios`** (a
`when (macos)` / `when (ios)` branch per module), with `nativeSlot` = the MSL
`buffer`/`texture`/`sampler` index for each WebGPU binding. Any host regenerates them;
`bash scripts/regen-shaders.sh --check` must say every output is fresh.

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
- Partial `writeTexture` on Metal: ported since, see `docs/GPU.md` "Metal".

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
  `baseline_names` (18 baselines × frames 1 6 11 16, at their capture size: 1280x720 for the
  campfire entries), converted from the
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

### 2026-10-23, the first full Mac gate on the branch

Run on `17c5a033`, msc `a0eba215c`. `gate.sh`: 17 FAIL, and 6 of them were not in main's Mac
baseline (`~/metascript/.wt/baseline/void-mac-5dfb8ed.fails`). Golden metal: 15 pass, 105
pending, 0 fail of 120. `gate3d.sh` had never run on a Mac: 51 FAIL. The fixes below are on the
branch. Each one is checked here per file; the full gate has not run again yet.

- **Changes that reach your side:**
  - `d30e92cd`: `src/sokol/gpu.ms` imports `../gpu/doorGpu`. The bridges call the door, and an
    entry that imported only `gpu.ms` (`fbTrap`, `viewIdAfterRecreate`, `viewSlotsRetired`,
    `mainCardTable`) failed to link. On Windows, `bridgeWin.c` calls `doorShutdown` the same way.
  - `403ebda7`: the `tests/aborts/writeBufferRewrite*` programs open `openTestDevice()` from
    the new `src/test/testDevice.ms`. That is WARP on Windows, built as before, and the system
    device on macOS. Not built on Windows yet.
  - `c571a1ae`: the multi-line HLSL and GLSL literals in `webgpuD3d11Check.ms` and
    `webgpuGlCheck.ms` now use `\n`. gate.sh's string-literal style check refused them.
  - `4c041828`: `doorShortPassDescriptor` and `doorShortPipelineDescriptor` import
    `doorBeginPass`/`doorMakePipeline` from `doorGpu`. They had declared them as C externs, and
    clang refused the implicit declaration.
  - `15b1a429`: `mrtBlend` accepts the facing normal as either `0x7F7FFF71` (D3D11) or
    `0x8080FF71` (Metal). The value 0.5 is a unorm8 tie, and the two backends round it apart.
  - `ae4ec7af`, gate3d:
    - Every `msc build` there now names its `.exe`, because msc on the Mac writes no suffix.
    - On macOS the capture entries run `voidRunConfigured(1280, 720, 1, 0, …)`: the Mac window
      driver renders at 1 sample, and a retina screen would double the size. Windows still
      runs `voidRun`, so your hashes stay the same.
  - Earlier on the branch: the `stopOnUnported*` helpers in `types.ms` are gone, except
    `stopOnUnportedShaderBindings`. `voidMetalReadDrawable` is gone. Compute-pass timestamps
    stop by name on Metal: Metal samples a compute timestamp only at a dispatch boundary.
- **Still red, needs you or the person:**
  - **Pool exhaustion as a test trigger:** `RenderTarget refused-pool` (gate.sh and gate3d) and
    `churn` (gate3d). Both expected the backend to run out early and return id 0, which the
    door then names. Since `0c9b0fe8`, the 65535-slot pool stops in the backend instead (on
    Metal: `view pool exhausted`), and memory never runs out first. Do these pass on D3D11? If
    so, what runs out there? Either the expectations follow the pool's own stop, or the tests
    need a smaller pool. Which do you prefer?
  - **gate3d `allocation`:** it looks for `<fn>__M…` in the emitted C. msc `a0eba215c` names a
    function `<fn>__srcZvoid3dZsceneOms_u0`, so `syncWorld` "has no body". This is a harness
    against compiler naming, the same on any host with this msc.
  - **gate3d `style`:** 15222 lines over 100 columns. Most of them are in the generated
    `src/void3d/programModules.ms`.
  - **gate3d `oracle`:** six `tests/oracle/*.cases` disagree with real Heaps. Not traced from
    the Mac.
  - **Known on main's Mac baseline, not chased:** view paint, two views, host-view samples
    1/2/4/8, D3D11 golden and its TESTING.md row, GL core 4.3, wasm delta, bare build, and the
    fb trap's clamped-window message (it builds again now).
  - **gate3d captures:** they run and are compared on Metal, and fail only on the missing
    `tests/golden3d/d3d11/*.png`. Perspective, textured, gltf, pick and bench pass their
    semantic checks on Metal.

### 2026-10-25, after `a93fda2b`

- `a93fda2b` passes `msc check` on all eight targets. Metal now has the same refusal
  (`37b0351c`), pinned through `draw` and `drawIndexed` by `src/test/metalFirstInstanceProbe.ms`.
- MSL `[[instance_id]]` includes `baseInstance`: on an M3 Max, `baseInstance` 5 reads 5. The
  comment in `types.ms` now puts MSL beside WGSL (`9e634be0`). Metal refuses anyway, as wgpu
  does, so a program gets the same result on every backend.
- **Needs you:** nothing sets `GPUShaderModuleDescriptor.readsInstanceIndex` yet, and Shady's
  reflection does not either. Until it does, the refusal fires on no backend for a Shady shader.
- From the "known on main's Mac baseline" list above, these now pass on the Mac when run directly:
  - two views, and host-view samples at 1/2/4 (`12235d6d`, `a1b1414b`);
  - 8 samples, which Apple GPUs refuse by name; gate.sh passes that refusal (`6a1ba44d`);
  - the fb trap: a 1x1 window is not clamped on macOS, so the Mac asks for one larger than the
    screen (`1537d62b`).

- `scripts/gate.sh` ran no backend check: `webgpuMetalCheck.ms`, `webgpuD3d11Check.ms` and
  `webgpuGlCheck.ms` ran only by hand, so a backend regression reached the gate only through the
  goldens. On the Mac the gate now runs `webgpuMetalCheck` (`94879ff0`). **For you:** the same
  line for `webgpuD3d11Check` (WARP) and `webgpuGlCheck` on Windows, which only you can verify.
- Metal applies uniform blocks in a compute pass (`5cc6d61e`): `setBindGroup(0)` in a compute pass
  with dynamic offsets, a missing group 0 and an overrun stop by name
  (`src/test/metalComputeUniformProbe.ms`). A compute program from the shader arc now runs on the
  device and its storage buffer is checked against the CPU run (`0c4b5142`,
  `src/test/metalShadyCompute.ms`). **For you:** D3D11 (`backend.ms:2176`) and GL (`:2000`) still
  stop on a compute uniform. Their `checkEntry` (d3d11 `:2431`, gl `:2399`) also matches a buffer
  entry to a uniform by binding number alone, so a storage buffer at group 1 binding 0 of a
  program with a uniform at group 0 binding 0 is refused as "needs a UNIFORM buffer". Metal had
  the same bug; its lookup now takes the group.
- Metal loads metallib bytecode, carried like DXBC (`f0bdae3e`, `5b90f9b6`): `tools/irPrograms.ms`
  compiles each `metal_macos` and `metal_ios` stage with `xcrun metal` into the committed cache
  `src/shader/metallib/` (416 blobs, 4.5 MB). **For your regens:** without xcrun a stage whose MSL
  changed prints `metallib miss` and keeps `[]`, as a DXBC miss does on the Mac; the Mac's next
  regen fills the blob. iOS descriptors keep their MSL beside the blob (`71158c7d`), because the
  simulator rejects an iphoneos metallib's pipelines; macOS descriptors drop it, as D3D11's do.
- `src/sokol/window.ms` held `currentTouches()` twice (`3ac71ddd` and `5f50c3e4`, one commit
  picked twice); the current `msc` refuses the ambiguous call, so the index went red. `b12739ff`
  drops the second copy.
- The Mac gate now runs the iOS goldens and view samples on an attached iPhone or iPad
  (`3920c9c8`); `backend:metal-ios` is closed in `tests/PENDING.md`.

### 2026-10-25, the Apple half is done; Windows ships

The person's call: Windows finishes the remaining criteria and ships the branch into main. The
Mac side has nothing open of its own. What the Mac verified, and what it still needs from you:

- Full Mac gate on `fbdd5750`, plus the iOS section rerun on an unlocked iPhone 13 Pro:
  index 2673/2673 both stages, `webgpuMetalCheck` 434/434, golden metal 15 pass / 105 pending /
  0 fail of 120 on the Mac and on the iPhone, iOS samples 1/2/4 PASS and 8 named. The 7 FAILs
  left were D3D11 goldens and their TESTING.md row, bare build, wasm delta and GL 4.3 (none
  runs on a Mac), view paint and refused-pool, both fixed since.
- On your `932a1562`, the Mac reran `msc check` (darwin, windows, linux, ios, android: 0 errors),
  `regen-shaders --check` (fresh), `webgpuMetalCheck` 434/434 and index 2677/2677. Haro
  `--smoke`, Neon `voidFrames` and `voidDraw` build, draw and carry 0 sokol symbols.
- `msc` 38009de37 refuses a mutable `Span` of a value parameter's field: `fromHeaps.ms`'s
  `polynomial` takes `Readonly<Span<float32>>` (`fbdd5750`).
- refused-pool printed `webgpu metal: view pool exhausted` on the Mac, so `161b3629`'s D3D11
  string failed there; gate.sh and gate3d now expect the host's backend (`5eb928fc`).
- view paint was never a Metal bug: `float32(0.1) × 255` is 25.50000038, a rounding tie, and the
  GPU rounds it to 26 where the test expected 25. The clear colour is now 0.2/0.2/0.4
  (`7c602fc7`). **For you:** rerun it on D3D11; 51 and 102 are far from any tie.
- `macos:view-api` is closed in `tests/PENDING.md` (`dfe8b72d`).
- **When you ship:** after you merge main into the branch, ask for a Mac gate.sh and gate3d on
  that tree (merge-train slot), because lines inside `__APPLE__` and the Metal backend compile
  only there. gate3d's Metal captures wait for your `tests/golden3d/d3d11/*.png`.

### 2026-10-26, the research round on the branch; what Windows adapts

The Mac applied the lessons of the sokol, Heaps and Mach reading on the branch (`bd73492f` to
`60bf2437`). Each landed with `msc check` on darwin, windows, linux, ios, android and emcc
(webgpu, webgl2) at 0 errors, index green (2739) and `webgpuMetalCheck` 434/434; D3D11, GL and
wgpu ran nowhere, so each item below names what to run on your side.

- **Shared validation, `src/webgpu/validate.ms`** (`858bcbe2`, `f3e6f51c` and the three before
  it). The checks the four backends repeated now run once in `device.ms` before `backend.X`:
  the encoder and pass state, debug groups, copies outside a pass, the draw state (pipeline set,
  index buffer set), the occlusion query, bind group entries by group and binding, buffer and
  texture descriptors against `backend.limits()`, the shader module and pipeline rules, and the
  storage rule (a storage binding covers a positive multiple of 4 bytes, now on Metal too).
  Behaviour that changes on your backends: a second `createCommandEncoder` before `finish`
  stops (it returned id 1 again), and every render-pass call stops outside a render pass.
  Messages print `webgpu: …` instead of `webgpu <backend>: …`.
- **For Vulkan:** it inherits everything `device.ms` calls. The checks that need a backend's own
  record are shared refusals the backend calls itself; Vulkan calls them where the other four do:
  `checkedRenderModule`, `checkedComputeModule`, `checkedComputePipeline`, `checkedStripDraw`,
  `checkedBindGroupSet`, `checkedStorageEntry`, `checkedSampledView`, `checkedStorageView`,
  `checkedViewDimension`, `checkedOcclusionRange`, `checkedOcclusionReuse`,
  `checkedOcclusionSetKind`. Read their call sites in `d3d11/backend.ms` as the map. Still
  copied per backend and worth moving before Vulkan copies them a fifth time: render-pass
  attachment checks, write and copy usage checks, vertex buffer and bind group set at draw,
  shader-module-destroyed, `resolveQuerySet` state, `NativeEnvironment.colorFormat`.
  **Run:** `webgpuD3d11Check.ms` on WARP and the GL pins; a reworded message your tests grep is
  the likely red.
- **Pool generations survive a reset** (`bd73492f`): an id from before a device loss stays
  stale after it. Your D3D11 `reset` callers needed no edit.
- **3D draw loop** (`0b172048` to `51aa010e`): globals apply once per pipeline change (a draw
  whose pipeline declares a block that was never applied now stops), opaque items sort by
  layer, order, pipeline and texture, pipelines are found by key hash, and
  `DrawContext.withGrowingUniforms(initial)` is the uniform pool Neon asked for.
  **Run:** gate3d; its D3D11 hashes should not move, because the pixel order inside a layer and
  order is the only thing the sort changes and the Metal captures did not move.
- **2D filters** (`ca3ffbfe`, `86b4e96a`): `setFilters([...])` chains steps, `outlineFilter`,
  and `Filter.withResolutionScale`. The nine filter goldens are byte-identical on Metal.
  **Run:** goldens on D3D11.
- **Frame stats** (`20d4f8e8`): `doorFrameStat` returns `int64` and has resident bytes per
  buffer, image and target; `door.h` mirrors it.
- **Held keys** (`4196276c`): every window releases its held keys before `UNFOCUSED`;
  `win32/window.c` on `WM_KILLFOCUS`, compile-checked only. **Run:** hold a key, Alt-Tab away, and
  the app sees the key-up.
- **macOS display link** (`58d13f08`): nothing for you.

### 2026-10-26, the lean test round; what changes in the gates for Windows

- **Aborts are cases binaries** (`d37716b5` to `746de065`): `tests/aborts` is 5 files in
  `tests/aborts/cases/` (one per `// flags:` set) and `tests/aborts3d` is 4 cases files plus
  `viewSlotsRetired.ms`; argv picks the case, `// expect <case>: <text>` names its stop. A new
  refusal is a case in the file of its flag set, not a new program. **Run:** the aborts loops of
  both gates on Windows; `presetCases` has never been built (the macro card blocks it here).
- **Caches are kept** (`583bcf62`): the header-cache card is fixed in msc 32b8ce353 (probed with
  a header and a header it includes, and with `-D`/`-d:` changes), so no gate evicts objects or
  deletes binaries; a check runs only after its build succeeded. `iosDevice.sh:92` keeps its
  eviction (cross build, unprobed).
- **Duplicates live in `gate.sh` only** (`c713d37b`): gate3d no longer reruns the index, the
  shader regen check, targetOwner, targetPresetEpoch or mixedFrame.
- **Host skips** (`73a10a0c`): a Mac skips D3D11 and GL by name. Windows runs them as before.
- **Not runnable by any gate on Windows yet:** `src/test/webgpuD3d11Check.ms`,
  `webgpuGlCheck.ms` and `doorZeroHandleCheck.ms` (D3D11 WARP, pins `5cacf730`). Wire them into
  the Windows gate or say why not.

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
- **Integer data textures (2026-10-24, for void3d clustered lights):** `rgba32uint` and
  `GPUShaderBinding.sampleType` `"uint"`/`"sint"` work on D3D11, GL and wgpu (`7d3dd19d`; WARP pins in
  `webgpuD3d11Check.ms` read every texel back exactly). A sampler paired with an integer texture must be
  `"non-filtering"` (`checkedIntegerTexturePairs` in `types.ms`). For Metal: `rgba32uint` is not in its
  `formatInfo` (stops by name), and a uint/sint binding is not refused there yet; add the format
  (`MTLPixelFormatRGBA32Uint`) and the sample type when you port it. An integer render target still stops
  on GL ("integer clear not ported").
  - **From the Mac (2026-10-24):** Metal has `rgba32uint` (`MTLPixelFormatRGBA32Uint`) and calls
    `checkedIntegerTexturePairs` in `createShaderModule`. `webgpuMetalCheck` 418/418, with your two
    WARP pins ported to MSL: rgba32uint loads exactly, and rgba32float loads bit-exact through
    an unfilterable-float binding. Without the format line the first pin stops by name.
  - **From the Mac, an index red on `b50e3a99`:** `shaderLayoutCheck` "a binding read by both
    stages is refused by name" (line 293) still expects the refusal that `fab323d2` removed.
    `bac274d6` pins the new behaviour. The test is platform-free, so your index is red there
    too. I left it for the shader arc. Index: 2050 passed, this 1 failed.
- **The shader arc is in `wt/gpu-ms` (2026-10-24, the person's call):** `wt/shader` up to
  `c275a431` is merged here, so one pull carries both arcs; `wt/shader` now rebases onto this
  branch. Left for the Mac: the Metal goldens of gate and gate3d on this tip, when your slot
  allows. Report to the shader arc (session void-wt-shader-80), or here under "From the Mac".
  - **From the Mac (2026-10-24):** run on `c9833a2c` with Apple metal 32023.883. `regen-shaders.sh`
    exited 0 and wrote 1036 `out/irPrograms/*.metal`. All 1036 compile with `xcrun metal -c`
    (`-sdk macosx` for `_macos`, `-sdk iphoneos` for `_ios`), with 0 errors. 572 files print
    warnings, all cosmetic: `-Wparentheses-equality` (2206) and unused variables `noise`,
    `handedness` and `params`. The regen does not write `out/mslProbe`; the tests do.
    `shaderMslCheck` 363/363, `shaderSampleCheck` 360/360, `shaderComputeOpsCheck` 368/368,
    and their 17 `out/mslProbe/*.metal` files all compile. Not run yet: the Metal goldens of
    gate and gate3d on the shader arc.
  - **From the Mac, the full gate on `7fa985b8` (2026-10-24):** gate.sh has 16 FAIL lines; 12 are
    Mac-known (`void-mac-5dfb8ed`). "printed Msl" (1036 stages) and "probed MSL" (23) pass. The
    4 new FAILs:
    - both index stages, from the one stale `shaderLayoutCheck` test above;
    - refused-pool;
    - style: 38 string literals in `printGlsl450.ms`, `shaderSampleCheck.ms`,
      `shaderWgslCheck.ms`, `webgpuD3d11Check.ms` and `webgpuGlCheck.ms` held a raw line end.
      The `webgpu*Check` lines came back after `c571a1ae` had fixed them, so a Windows edit
      path writes `\n` as a real newline. Fixed in `a438aeef`. Please run
      `scripts/stringLiterals.awk` before you push.

    gate3d has no new class of red. All 22 captures run and fail only because the 88 D3D11
    PNGs are missing. The other reds are churn, refused-pool, allocation (`syncWorld` has no
    body by its old name), style (15069 long lines), the six oracle `.cases` files, and the
    same index test.
- **Linux build in WSL:** `msc` there is synced to `4b5816aea`. Yoga has no linux branch, so
  build `libyoga.a` from `yoga/deps/yoga/yoga/**/*.cpp` with `zig c++ -std=c++20 -O2 -fPIC`
  (libc++, as msc links) and pass it with `--passL`.

### 2026-10-26, Windows answers the research round

- **Merged** through `31d45d97` as `c0980ea9`. `webgpuD3d11Check.ms` on WARP gives 421/421 with
  the shared validation in.
- **Still queued for a GPU slot on this machine:** the GL pins, gate3d and the 2D goldens on
  D3D11, and the Linux GLX/EGL/GLES3 runs. The Alt-Tab key-up is a manual check for the person.
- **Dummy backend:** `src/webgpu/dummy/` follows every validate refactor through `60bf2437`.
  A refactor that changes all the backends changes it too (see "Working together").
- **The remaining moves are yours.** These are the moves you listed as worth doing before
  Vulkan copies them: render-pass attachment checks, write and copy usage, vertex buffer and
  bind group set at draw, shader-module-destroyed, `resolveQuerySet` state, and
  `NativeEnvironment.colorFormat`. Please make them in the same series, since you hold
  `device.ms` and `validate.ms`. Windows stays off both files until you say the series is done.
  Vulkan's `backend.ms` starts after that; the C side does not wait.
- **Vulkan:** V0-V1 are in (`3a9da721`, probe `42c4c771`). On lavapipe the probe brings the
  instance, adapter and device up and down with validation on and 0 errors. The references
  are in `docs/GPU.md` "Coverage against sokol's pin":
  - Mach for the backend;
  - Heaps DX12 for frames and descriptors;
  - Dawn and Godot for Android.

  The headers are Khronos 1.4.341 in `deps/vulkan-headers/include`. `deps/` is not in git, so
  copy that folder onto the Mac before a Vulkan build there (MoltenVK is not a target).

### 2026-10-26, the shared checks go to the Mac (the person's call)

The person decided that the Mac makes the remaining moves listed above, so each backend keeps
only its native work, as sokol's backends do over its one validation layer. Code lines (no
blanks or comments) show where the copies sit:

| part | sokol `2e75443d` | this branch |
|---|---|---|
| shared layer | about 10k (API, common, validation, public) | 1.7k (`device`, `pool`, `types`, `validate`) |
| D3D11 / GL / Metal / WebGPU | 2.3k / 3.0k / 2.1k / 2.0k | 3.9k / 4.6k / 3.7k / 3.7k |
| dummy | 0.2k | 1.5k |

Part of each backend's excess is capability sokol lacks (readback, copies, queries, partial
writes), part is these copied checks. Windows follows the series:
1. runs `webgpuD3d11Check.ms` on WARP and the GL pins, where a reworded message is the likely red;
2. cuts the dummy down to records and ids, since most of its size mirrors the checks that move;
3. writes Vulkan's `backend.ms` against the shared checks from its first line.

Say in this section when the series is done.

**The Windows backend checks are in the gate.** Section 2 of `gate.sh` runs them on Windows, as
it runs `webgpuMetalCheck` on a Mac, through one `backend_check` helper:
- `webgpuD3d11Check` and `doorZeroHandleCheck` on WARP;
- `webgpuGlCheck` with `-d:voidGlCore` on the system device.

The helper alone, run on this tree: D3D11 421/421 and door handle 0 378/378 on WARP, and a
missing check file fails by name. The GL line waits for this machine's GPU slot. The whole gate
has not run with the change yet.

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
- `src/webgpu/dummy/` (`-d:voidDummy`, since 2026-10-26) is a fifth backend, beside d3d11, gl,
  metal and wgpu. It runs the door with no GPU. A refactor that changes every backend changes it
  too, and `msc check -d:voidDummy src/examples/mainSokol2d.ms` proves the change.
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
  (`glTexSubImage2D` in place; a whole write still rotates the copy), wgpu and Metal (a blit, or
  the CPU inside a pass; `docs/GPU.md` "Metal"), so a glyph page uploads only the union of the
  tiles written since its last upload (`doorUpdateTextureRect`). The DEFAULT texture's cost for a
  whole-texture stream is unmeasured until a GO.
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
bash ~/metascript/.wt/nim-audit/buildslot.sh sh scripts/abBench.sh build web    # wasm of both sides, wgpu and gl, CPU only (about 6 min)
AB_BACKENDS="d3d11 gl linux" sh scripts/abBench.sh run 5                         # opens windows: only inside a granted GO
AB_BACKENDS=linux AB_LINUX_DRIVER=llvmpipe sh scripts/abBench.sh run 5          # the software-GL alternative
AB_BACKENDS="web-wgpu web-gl" sh scripts/abBench.sh run 5                       # headless Chrome on the GPU: only inside a granted GO
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
- **Web**: `build web` runs each tree's own `scripts/build-web.sh` (identical on both sides today) per
  scene and backend with `VOID_WEB_ENTRY=tests/bench/bench<Scene>.ms`, the `assets` and `tests/fonts`
  preloads of the golden runner, and the same `-d:webgpu` / `-d:webgl2` defines, into
  `$TEMP/voidAB/web/<side>/<wgpu|gl>/bench<Scene>.{js,wasm,data}`. `run` hands `bench-ab.sh` the
  driver `scripts/webBench.mjs <wgpu|gl>` as `AB_RUN` (this tree's driver for both sides), so the
  `bench<Scene>.exe` path it passes is only a name: the driver serves that directory, loads
  `bench<Scene>.js` in headless Chrome, waits until the `present.ms` row has been logged and the log
  has been quiet for 1 s, and prints the rows. Its row filter is unit-tested without a browser
  (`node --test scripts/webBench.test.mjs`). Labels are `web-wgpu` and `web-gl`; raw rows
  `$TEMP/voidAB/raw-web-<backend>.tsv`.
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
- **Web run:** the driver ran both backends in Chrome on 2026-10-25, 5 pairs each. Every counter row
  matches across sides, and every `present.ms` and `firstPaint.ms` row is 0 on both, because
  `performance.now()` returns 0 in an `--os=emcc` build (`~/metascript/.inbox/compiler/2026-10-21-emcc-clocks-return-zero.md`).
  The web timing rows are parked here until that card lands; then rerun `run` with no rebuild of
  the driver, after rebuilding both sides' wasm with the fixed `msc`. WebGPU with no adapter yields
  no rows and the pair is `BROKEN`.
- **Metal:** another machine and another GO.
- **Particles and module scenes:** `benchParticles.ms` is on main's tip only, and TextEmoji,
  TextOutline and TextSdf need module defines; `AB_SCENES` can name them but the build passes none.

### 2026-10-26, the Mac's reuse series has started; what Windows reads now

The series runs in lanes off this branch and merges back in steps; this section says when it is
done. Until then `src/webgpu/{device,validate,pool,types}.ms` and the five `backend.ms` move under
you, so Vulkan's `backend.ms` waits as agreed. In order: argument-only checks into `device.ms`;
the view-range resolve, pass extent and render-pass attachment checks into `validate.ms`; one id
and one common record per resource in `pool.ms`/`device.ms` (sokol's `_sg_buffer_common_t`
`:6643`), so `liveCounts`, the `*Alive` functions, the destroy tail and the shutdown loop exist
once; the checks that read a resource's record; one bound-state struct and reflection lookup;
one `formatInfo` and enum table (`types.ms`), which `vulkan/conv.ms:88` should import instead of
being a sixth copy.

Where backends disagree on what a program may do, the series applies WebGPU's rule, or sokol's
where WebGPU has none, on every backend: `setPipeline` refuses a compute pipeline in a render
pass on D3D11 too; the storage-texture format must match the shader on Metal and D3D11 too;
blending an integer format is refused everywhere; `writeBuffer`'s offset is a multiple of 4 on
Metal too. Each lands with its pin; a D3D11 or GL red on WARP after a merge is most likely one of
these, and its message names the rule.

`scripts/gate.sh` section 1 now runs `msc check src/examples/mainSokol2d.ms` for every backend the
host does not run (about 15 s), so a function one backend lacks is red on the Mac and on Windows
alike.

For Windows, found by the audit and not the Mac's to change:
- `vulkan.c:996` wraps the generation with `& SLOT_MASK` instead of retiring the slot at the wrap
  (`pool.ms` retires it), so an id 65,536 reuses old can name a live object. `tableDrain`
  (`:1014`) frees the table and restarts every generation, the stale-id-after-loss bug
  `bd73492f` fixed in `pool.ms`. Finding a free slot is a linear scan.
- The C table wraps ids that `resources.ms` wraps again in `pool.ms`: a third id table. The other
  four C files return raw handles and keep no slots.
- Vulkan reports errors as `Result` (`frame.ms`, `pass.ms`, `memory.ms`) where every other backend
  stops, and `pass.ms:113` adds a stop that returns `void`. `resources.ms` restates the stencil
  message of `checkedDepthTexelCopy` (`types.ms`) instead of calling it.
- Frame-path work that only a Windows probe can justify (`docs/GPU.md` "Beyond sokol on the frame
  path": each is built once a probe shows its cost): GL re-uploads every uniform block on every
  dirty apply with no compare (`gl/backend.ms` `oglUniform4fv`); GL rebinds storage buffers and
  images and detaches, re-attaches and checks its framebuffer on every pass, not only on a change;
  D3D11 compute clears and rebinds every view (`d3dCsClearViews`); D3D11 creates and releases 3D
  slice views every pass; D3D11 calls `ClearState` at every pass end.
