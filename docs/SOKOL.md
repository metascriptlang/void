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
2. **Patch in our fork, `~/projects/sokol`.** It is a clone of floooh/sokol, with remote `upstream` = floooh/sokol. It has two kinds of branches:
   - **`void`:** Void's pinned commit plus Void-local patches.
   - **PR branches:** cut from `upstream/master`.

   `deps/sokol` is a git checkout pinned by `setup.sh` (`SOKOL_REV`). When the pin names a commit that floooh/sokol lacks, `setup.sh` fetches the `void` branch from the fork (override the path with `SOKOL_FORK`). A GitHub fork, needed to open PRs, is added as a remote of `~/projects/sokol` when the first PR is ready. `deps/` stays gitignored and fetched by `setup.sh`, not a submodule. A submodule only pays once its URL is a fork other machines can clone; reconsider when the GitHub fork exists.
3. **Keep every Void-local patch on its own commit.** Each carries an upstream reference: the PR link, the issue link, or "not upstreamable" with the reason. A patch with no upstream path needs that reason written down.
4. **Open the PR as soon as the patch works in Void.** Don't wait for Void to ship it. Review feedback is cheaper before Void builds on top.
5. **When upstream merges, move the pin back to floooh/sokol** at a commit that contains the change, and drop the local commit. The goal is a fork with zero local commits.
6. **Never edit `deps/sokol` without committing it to the fork.** An uncommitted change in `deps/` is lost on the next `setup.sh`.

### Where Void is likely to need sokol changes

Ordered by how soon Void hits them. None is started; each waits for the Void need that asks for it.

| Need | Void driver | Upstream state (2026-09-20) |
|---|---|---|
| Sub-rect texture updates that persist across frames | Glyph atlas: VOID2D.md P3 | Pinned rev: `sg_update_image` replaces a whole mip level, once per frame. Upstream `sg_write_image_transient` writes sub-rects but does not survive the frame. `write_persistent` is announced. Coordinate on that. |
| GPU→CPU readback | Golden-image tests on every backend | No API. `out/tmp/capture/capture.c` does it for D3D11 through native handles. Async `read-buffer`/`read-image` is announced. |
| Android host-owned EGL: context loss, preview and live side by side | Hibernal V6 (`hibernal/docs/ROADMAP.md`) | `sokol_gfx` works on an external GL context (`SOKOL_EXTERNAL_GL_LOADER`, hand-filled `sg_environment`/`sg_swapchain`), but has no context-loss rebuild. `sokol_app` on Android is NativeActivity only. |
| Embedding `sokol_app` in a host view | Neon hosts, `bridgeEmbed.m` / `bridgeIos.m` | No embed mode (issues #520, #335, per the 2026-09 research; not re-read). Void keeps its own host glue for now. |
| Async pipeline creation on WebGPU | Only if first-frame hitches show up on the web | Pipelines are created with synchronous `wgpuDeviceCreateRenderPipeline`. void2d needs about two pipelines, created at init. |

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
- The four copies of the `bridge.h` functions (`bridge.c`, `bridgeEmbed.m`, `bridgeIos.m`, `bridgeAndroid.c`) double that cost. Merging them is worth doing before the next sokol upgrade.

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
- **Bus factor.** floooh has 4,430 commits; the next contributor has 27. Mitigated by the zlib licence, the pinned commit and the fork workflow above. Contributing upstream also widens the pool of people who know the code.
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
- `setup.sh`: the pins. `scripts/regen-shaders.sh`: sokol-shdc outputs.
- sokol changelog: https://github.com/floooh/sokol/blob/master/CHANGELOG.md
