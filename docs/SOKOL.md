# sokol — Void's GPU layer, and how we treat it (2026-09-20)

Void's GPU layer is [sokol](https://github.com/floooh/sokol): `sokol_gfx` is the driver, `sokol-shdc` is the shader compiler, and `sokol_app` provides the window where Void does not bring its own host glue. This doc records why it stays after a deliberate review against the alternatives, and how Void relates to it: **we are ready to hack sokol and to contribute upstream, not only consume it.**

## Stance: hack it, and send it upstream

sokol is a dependency we own a stake in, not a black box.

- **We change sokol when Void needs something it lacks.** That covers a feature, a backend fix, or a platform path such as Android host-owned EGL, context loss or embedding. "sokol does not do X" is a task, not a blocker and not a reason to switch layers.
- **The change goes upstream as a PR to [floooh/sokol](https://github.com/floooh/sokol)**, written to the repo's own conventions so the author can take it. We contribute alongside the author, as a collaborator. The changelog regularly credits outside PRs; three merged in September 2026 alone: #1600, #1601, #1602.
- **Only when Void needs it.** We do not send drive-by refactors, style changes or features no Void use case asks for. Every patch traces to a Void need: a milestone, a GPUI.md step, a Hibernal requirement.
- **For API floooh is actively redesigning, open an issue before a PR.** That covers the resource update series (`write_transient` landed 2026-08-30; `write_persistent`, buffer/image copies and async readback are announced in the 2026-08-09 changelog entry) and `sokol_cmdbuf.h` ([#1557](https://github.com/floooh/sokol/issues/1557)). Agree the shape on an issue, then send the PR. A patch built against a design the author is about to replace is wasted twice.

### Workflow

1. **Before touching the header,** check upstream master and the changelog. The need may already be solved, or be on the way.
2. **Reach the need through sokol's public API first.** `sokol_gfx` takes any externally provided `sg_swapchain` and `sg_environment`, and `sokol_app` can run without a graphics API (`SOKOL_NOAPI`), so a need around the device or the swapchain belongs in Void's own layer (see "The Windows window owns its swapchain" below). Only a real sokol bug or a missing feature goes upstream.
3. **An upstream patch is written in a clone of floooh/sokol, `~/projects/sokol`,** on a branch cut from `upstream/master`, and sent as a PR once the person agrees: a PR is outward-facing. `deps/sokol` is a git checkout of floooh/sokol pinned by `setup.sh` (`SOKOL_REV`); the pin always names an upstream commit, so a fresh clone needs nothing but GitHub. `deps/` stays gitignored and fetched by `setup.sh`, not a submodule.
4. **A local patch is the person's decision, never a default.** Until 2026-10-20 the pin named a fork commit (`sapp_skip_present`, below), and every fresh clone of the public repo failed in `setup.sh`. If a patch is ever needed again, the decision records why neither sokol's API nor upstream serves, and `setup.sh` must still work without the patch's machine.
5. **When upstream merges a PR Void needs, move the pin** to a commit that contains it.
6. **Never edit `deps/sokol`.** An uncommitted change in `deps/` is lost on the next `setup.sh`.

### The Windows window owns its swapchain (2026-10-20)

Neon's canvas skips idle frames: a frame that made no `voidCommit` draws nothing. Under `sokol_app` a frame always presents (`_sapp_win32_frame` calls `_sapp_d3d11_present` or `_sapp_wgl_swap_buffers`, `deps/sokol/sokol_app.h` at `2e75443d`), and upstream's contract is that `sapp_acquire_swapchain` "must be called exactly once per frame". On D3D11 `FLIP_DISCARD` an unpresented-but-flipped frame showed the undrawn back buffer, so the window alternated between its last two pictures.

- **Rejected: the fork patch `sapp_skip_present()`** (fork commits `7b7a84d5` D3D11 and `68bd4de8` WGL on `2e75443d`). It worked, but pinned a commit floooh/sokol lacks.
- **Rejected: render into a Void-owned texture and blit it into sokol_app's back buffer every frame.** It follows sokol_app's contract, but an idle frame still costs a fullscreen copy and a present.
- **Chosen: `sokol_app` with `SOKOL_NOAPI`** (`src/sokol/sokolAppWin.c`), which keeps the window, events, DPI and resize and never presents. Void owns the device and swapchain (`src/sokol/windowSurface.h`; D3D11 in `bridgeWin.c`, GL core in `windowGl.c`), the way macOS, iOS, Android and the host views already do, presents at the end of a frame that called `voidCommit` (as `sokol_app` did, so a readback after `voidCommit` still sees that frame; a present inside `voidCommit` read back zeros from the discarded `FLIP_DISCARD` buffer, gate 2026-10-21), and waits an undrawn frame on `DwmFlush`. A side effect: `-d:voidGlCore` now runs on `bridgeWin.c`, so it gains the IME path.
- **What the no-API backend changes:** with `high_dpi` off the process is DPI-unaware and Windows scales the window (sokol_app's GL behaviour), where the D3D11 backend stretched a smaller swapchain; the framebuffer is the requested size either way.

Measured 2026-10-20 with a throwaway probe on `voidRun` that clears 3 red and 3 green frames at 640x480, MSAA 4, then idles 5 s, reporting wakeups per second, process CPU, and the centre pixel read through `PrintWindow` once a second; 165 Hz display, two runs each, the box at 25-49% CPU under a recompiler gate. The fork rows ran on tree `c1196936`, the Void-owned rows on tree `1f66803b` (the upstream pin; the probe binary predates a comment move only):

| | wakeups/s | CPU | picture |
|---|---|---|---|
| fork, D3D11 | 165 | 0.00 / 0.59% | green x5 |
| fork, GL core | 165 | 8.84 / 11.49% | green x5 |
| Void-owned, D3D11 | 165 | 0.88 / 0.59% | green x5 |
| Void-owned, GL core | 165 | 0.29 / 0.29% | green x5 |

### Where Void is likely to need sokol changes

Ordered by how soon Void hits them. None is started; each waits for the Void need that asks for it.

| Need | Void driver | Upstream state (2026-09-20) |
|---|---|---|
| Sub-rect texture updates that persist across frames | Glyph atlas: VOID2D.md P3 | Pinned rev: `sg_update_image` replaces a whole mip level, once per frame. Upstream `sg_write_image_transient` writes sub-rects but does not survive the frame. `write_persistent` is announced. Coordinate on that. |
| GPU→CPU readback | Golden-image tests on every backend | No API. `out/tmp/capture/capture.c` does it for D3D11 through native handles. Async `read-buffer`/`read-image` is announced. |
| Android host-owned EGL: context loss, preview and live side by side | Hibernal V6 (`hibernal/docs/ROADMAP.md`) | `sokol_gfx` works on an external GL context (`SOKOL_EXTERNAL_GL_LOADER`, hand-filled `sg_environment`/`sg_swapchain`), but has no context-loss rebuild. `sokol_app` on Android is NativeActivity only. |
| Embedding `sokol_app` in a host view | Neon hosts, host views (docs/EMBED.md) | No embed mode (issues #520, #335, per the 2026-09 research; not re-read). Void keeps its own host glue: `src/sokol/views.ms` and a `voidPlatform*` half per OS. |
| Async pipeline creation on WebGPU | Only if first-frame hitches show up on the web | The pin calls synchronous `wgpuDeviceCreateRenderPipeline`, forwarded by emdawn to Browser `device.createRenderPipeline`. Current startup is `batcher.c` `void2dSetup`; D1's cache/creation decision is in VOID2D.md "D1 direction agreed for the fresh session". No Browser hitch measurement or async implementation is claimed. |

## Why sokol stays

The review ran on 2026-09-20: the vendored `sokol_gfx.h` read at the pin; the alternatives' repos, changelogs and release notes; and how shipping UI renderers choose their GPU layer. Void's hard constraints filter the field:

1. **GLES3 inside an EGL context owned by the host,** for the Hibernal live wallpaper.
   - **SDL3 GPU is out.** It has only Vulkan, D3D12 and Metal, and cannot wrap an Android `Surface`.
   - **Dawn is out.** Compatibility mode needs GLES 3.1, and `libwebgpu_dawn.a` is about 21 MB (macOS) to 58 MB (Android arm64) as a release static library.
   - **wgpu-native is out.** Its GLES backend is best-effort, and its release `.so` for Android arm64 is about 10 MB.
   - Hibernal already recorded this rejection: `hibernal/docs/RENDERER-BRIEF.md:87`.
2. **A WebGL2 fallback, reachable from C.** WebGPU covers about 87% of browsers (caniuse, 2026-08). Firefox on Linux and Android, Android below 12 and iOS below 26 are still missing. That leaves sokol, bgfx and LLGL.
3. **C, small, one vendored header.** That leaves sokol alone.
   - bgfx is C++ with the bx/bimg libraries and a GENie build, and its WebGPU is native Dawn only.
   - LLGL is a beta (v0.04b).

**Size, measured here on 2026-09-20:**
- sokol_gfx D3D11 + sokol_app Win32 come to about 74 KB of code and data in the release object.
- The void2d demo built with `msc build --danger --strip` is 505 KB. stb_image alone is about 134 KB of that.
- The web build of the same demo is 511 KB of wasm on WebGPU and 411 KB on WebGL2.

**Shipping UI renderers point the same way:**
- **Zed GPUI** keeps Metal and D3D11 direct. It put Linux and the web on wgpu (PR #46758, 2026-02), with WebGL2 as the web fallback.
- **Vello** moved its default off the compute renderer onto raster with a WebGL2 floor (repo reorganisation, 2026-09).
- **Flutter Impeller** keeps a GLES fallback on Android, and its experimental web renderer targets WebGL.
- **Skia Graphite** runs on Dawn because Chrome already ships Dawn.

Void needs Metal, D3D11, GLES3, WebGPU and WebGL2 from one API. That backend set is sokol's.

**Coupling is narrow.**
- Every sokol call lives in six C/ObjC bridge files, about 1,630 lines. No `.ms` file calls `sg_*`.
- Swapping the layer would mean rewriting that C and about 290 lines of GLSL, not the MetaScript.
- `bridge.c` holds the resource and pass wrappers once, for Windows, macOS, iOS and Android; each driver (`bridgeWin.c`, `bridgeIos.m`, `bridgeAndroid.c`) keeps only the device and the swapchain. `bridgeEmbed.m` (macOS) now uses them too.

**Control is kept.**
- The WebGPU device can be injected (`sg_environment.wgpu.device`).
- Native handles are exposed: `sg_wgpu_device/queue/command_encoder/render_pass_encoder`, and `sg_*_query_*_info` for buffers, images and pipelines.
- A raw WebGPU pass can therefore sit next to sokol's passes on the same command encoder.
- One trap: do not inject raw calls *inside* a sokol pass. sokol's bindings cache is cleared only at `begin_pass`, so state changed behind its back desynchronises it.

## Known limits and the plan for each

- **API churn.** About six breaking changes in the last twelve months:
  - resource views (2025-08)
  - `sg_image_data` cubemap layout
  - binding limits
  - `sapp`/`sg_desc` nesting
  - swapchain composite mode (2026-07)
  - `write_transient` (2026-08-30)

  The pin moved from `6c3fa5ac` (2026-08-10) to upstream master `2e75443d` (2026-09-14) in `0c36bd1`. `stream_update` is gone; the batcher's vertex buffer and the font atlas moved to `dynamic_update`, which still allows `sg_append_buffer`. **VOID2D.md P1 moves the display list to `write_transient`:** it writes one buffer once per frame, which is exactly that model.
- **Feature ceiling.**
  - Missing: indirect draw, timestamp/occlusion queries, readback, render bundles, async pipeline creation.
  - Present: compute, storage buffers and images, and MRT.
  - The UI plan needs none of the missing features. If void3d ever needs GPU-driven rendering, add a raw `webgpu.h` path through the native handles beside sokol, or implement the feature in sokol per the stance above.
- **Per-backend feature gaps.**
  - Dual-source blending is false on GLES3 and WebGL2, so text is grayscale there (already the GPUI.md decision).
  - Storage buffers are unavailable on WebGL2. Feed instance data as per-instance vertex attributes, as GPUI.md plans.
- **Bus factor.** floooh has 4,430 commits; the next contributor has 27. Mitigated by the zlib licence, the pinned commit and the workflow above. Contributing upstream also widens the pool of people who know the code.
- **Roadmap risk.** The Vulkan backend (experimental since 2025-12, desktop feature set, no mobile path) is described as "the first step towards deprecating the OpenGL backend … won't happen for a while". GLES is Hibernal's path. Watch the changelog; if GL deprecation gets a date, raise Android's needs upstream early.

## When to revisit

- void3d needs GPU-driven rendering that sokol will not take upstream.
- GL deprecation gets a date before sokol's Vulkan backend runs on Android devices the size of Hibernal's target.
- sokol stops being maintained and our fork becomes the only maintainer.

None of these holds today.

## Reference

- [GPUI.md](GPUI.md): the void2d frame shape (display list, instanced UI pipeline) that the sokol upgrade lands with.
- [VOID2D.md](VOID2D.md): the 2026-06-20 decision to own the batcher on `sokol_gfx` instead of vendoring sokol_gp.
- [HEAPS.md](HEAPS.md): sokol replacing the Heaps driver and hxsl layers.
- `setup.sh`: the pins. `scripts/regen-shaders.sh --oracle-shdc`: the sokol-shdc reflection oracle.
- sokol changelog: https://github.com/floooh/sokol/blob/master/CHANGELOG.md
