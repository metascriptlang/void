# GPU — Void's own WebGPU-shaped layer, replacing sokol (branch `wt/gpu-ms`)

This branch replaces everything Void takes from sokol (`sokol_gfx`, `sokol_app`, `sokol_glue`,
`sokol_time`, and the `-f sokol` output of sokol-shdc) with a GPU layer written in MetaScript.
sokol at pin `2e75443d` stays the reference: every backend body is a port of the matching
`_sg_<backend>_*` function, and a difference from it is written down here with its reason.
The branch is an experiment kept off `main` until sokol is fully replaced; main stays on sokol
(`docs/SOKOL.md`).

## What the author writes

The surface reads like WebGPU, with TypeGPU's names where Void has the concept
(`docs/VOCABULARY.md`, GPU layer row):

```ts
const buffer = device.createBuffer({ size: 4096, usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST });
device.queue.writeBuffer(buffer, 0, vertices);
const encoder = device.createCommandEncoder();
const pass = encoder.beginRenderPass({ colorAttachments: [{ view, loadOp: "clear", storeOp: "store", clearValue }] });
pass.setPipeline(pipeline);
pass.setVertexBuffer(0, buffer, 0);
pass.setBindGroup(0, uniforms, offsets);
pass.draw(6, count, 0, 0);
pass.end();
device.queue.submit(encoder.finish());
```

The inventory of sokol uses was the first scope. The end-game adds the WebGPU calls a Void
caller needs and sokol refuses, listed under "Control sokol refuses" below with the caller that
uses each; a call with no caller is listed there too and is a backend-coverage item, not a use.

## Why this shape

- **Backend chosen at compile time, the way sokol does it.** sokol's public call is one
  function whose body picks the backend with `#if` (`_sg_create_buffer`,
  `sokol_gfx.h:23373`: `_SOKOL_ANY_GL` → `_sg_gl_create_buffer`, `SOKOL_METAL`, `SOKOL_D3D11`,
  `SOKOL_WGPU`). Here the facade's body is a `when` over the target and `-d:` defines, and
  each backend lives in its own module. Measured 2026-10-22 (msc 0.3.4, BUILD `afcd22f19`):
  `when (x) { import … } else { import … }` at module level imports only the chosen module
  (3 modules built, not 4), and `-d:name` sets `name` for `when`.
- **No runtime interface.** The C backend has no vtables: an interface with closure fields
  dispatches through an `msClosure` call, and class override dispatch is an if-chain per
  method whose dispatcher ignores the calling convention of struct returns and `Vec` params
  (probe repros in the compiler inbox). A GPU call happens thousands of times per frame, so the
  dispatch costs nothing only when it is decided at compile time.
- **Handles and descriptors are values.** A `GPUBuffer` is a struct holding a pool id, as
  sokol's `sg_buffer` is; a descriptor is a struct literal. A struct over 24 bytes passes as
  `const T*`, so a large descriptor costs a pointer. An interface or class would put each one
  on the heap under DRC.
- **Fields left out of a descriptor are WebGPU's defaults.** A struct literal zero-fills an
  omitted field (measured: `int` 0; a string-literal-union field is `""` on C and `undefined`
  on JS). So a backend reads `""`/`undefined`/0 as WebGPU's default for that member, and any
  other unknown value is an error naming the member. Struct fields cannot be written `x?: T`
  (does not parse); a nullable field is `x: T | null`.
- **String enums cost a compare.** `"clear" | "load"` lowers to `msString`, and a `match` on it
  is a string compare (emitted C, 2026-10-22). Descriptors are built at creation time, so this
  is paid once; a per-draw string (`setIndexBuffer`'s format) is the one to measure if a
  profile ever shows it.
- **Native backends run pass commands immediately, as sokol does.** WebGPU records commands
  and runs them at `submit`, and orders `queue.writeBuffer` before the commands it submits.
  Void's frame never depends on the difference because it keeps sokol's rule (inventory J):
  each buffer region is written once per frame, appends go to fresh 4-byte-aligned offsets, a
  texture is written once per frame. Under that rule immediate execution and recorded
  execution draw the same frame, so D3D11, GL and Metal execute each call as it comes, and only
  the WebGPU backends record.

## Uniforms and bind groups

WebGPU's shape is kept: uniforms live in a uniform buffer, reached through bind group 0 with a
dynamic offset per block; textures and samplers are bind group 1. That is sokol's own WebGPU
layout (`_sg_wgpu` uniform system, `sokol_gfx.h:18387`; group 0 uniforms, group 1 views and
samplers, `:7263`). Each backend maps it with sokol's mechanism for that backend:

| backend | uniform buffer | at draw | sokol anchor |
|---|---|---|---|
| WebGPU | real buffer, 256-aligned offsets | `setBindGroup` with dynamic offsets | 18387, 19882 |
| Metal | real buffer, 256 macOS / 16 iOS alignment | `setVertexBufferOffset` | 16958, 17557 |
| D3D11 | CPU shadow only | `UpdateSubresource` of the shader's per-slot cbuffer from the bound range | 15170 |
| GL | CPU shadow only | `glUniform4fv` of the flattened FLOAT4 array | 12687 |

A binding number reaches a register through the shader module's reflection, which shdc
already emits per language (`hlsl_register_b/t/s_n`, `msl_buffer/texture/sampler_n`,
`wgsl_group0/1_binding_n`, GLSL names).

Per-draw texture bindings (glyph pages, render targets) become bind groups through a cache
keyed by their contents, which is how sokol's WebGPU backend meets the same need
(`_sg_wgpu_bindgroups_cache`, `sokol_gfx.h:18462-18763`). On D3D11, GL and Metal a bind group
is its slot list and costs no driver object.

## Shaders

Void's own printers write each language from the shader IR (`src/shader/CLAUDE.md`), with the
reflection `sokol-shdc` used to give, which `scripts/regen-shaders.sh --oracle-shdc` still compares.
The generated table is Void's `GPUShaderModule` descriptor, so nothing includes `sokol_gfx.h`. D3D11 compiles HLSL
source at load with `D3DCompile`, as sokol does (`sokol_gfx.h:14127`, `:14143`).

## Window, surface and time

The device and the per-frame target were already Void's on every platform except two:
`sokol_app` drove the Windows window (`SOKOL_NOAPI`, `docs/SOKOL.md`) and the web window path
(with `sokol_glue`). The Windows window is ported from `sokol_app.h` (Win32 `:8635-10514`) into
`src/platform/win32/`, keeping `sapp_event`'s fields and ordinals in `src/platform/appEvent.h`
because `src/sokol/window.ms` `AppEventType` mirrors them. The frame clock is
`src/platform/clock.h`, sokol_time's four readings (`QueryPerformanceCounter`,
`mach_absolute_time`, `emscripten_get_now`, `clock_gettime`) behind one function. The web window
is ported from the emscripten backend (`:7466-8350`, the WebGPU device and surface `:3909-4366`)
into `src/platform/web/`: it delivers `VoidAppEvent`s itself, makes the WebGPU device and surface
or the WebGL2 context, and gives the door its swapchain views (WebGL2 draws framebuffer 0).

## The door on this layer

The render layers above keep the door's contract (`src/gpu/door.h`, `door.ms`): typed pipeline and
pass descriptors, a flat bindings descriptor, `uint32` ids, programs and layouts registered by index. `src/gpu/doorGpu.ms` carries that
contract onto the WebGPU-shaped API, adding the two things WebGPU leaves to its caller and
sokol's WebGPU backend does for it:

- **Uniforms** go to one 4 MiB uniform buffer at 256-aligned offsets, rewound at commit, and
  reach the shader through the pipeline's group 0 with one dynamic offset per block (sokol's
  uniform system, `_sg_wgpu_uniform_system_*`, `sokol_gfx.h:18387`).
- **Textures and samplers** of a draw become a group 1 bind group looked up in a cache keyed
  by the pipeline and the bound ids; a collision replaces the entry, as sokol's
  `_sg_wgpu_bindgroups_cache` does (`:18462-18763`).
- **Frame statistics** (draws, pipelines, passes, uploaded bytes) are counted through a frame and
  handed over at commit, sokol's `prev_frame` (`_sg_update_stats`); `src/void2d/frameClock.c`
  reads them through `doorFrameStat`.

C reaches the door through `@exportName` functions, whose prototypes are `door.h`. A C unit that
writes a uniform block takes its struct and slot numbers from a header generated from the same
GLSL the shader is built from (`tools/shaderSlots.ms`, `src/void2d/shader2dSlots.h`), so no C
includes `sokol_gfx.h`. Programs register with a function from index to
`GPUShaderModuleDescriptor` (`doorRegisterPrograms`), which void3d's generated
`gpu3dShaderModule` is.

## Control sokol refuses

Each row is a WebGPU-shaped call Void uses where `deps/sokol/sokol_gfx.h` refuses or lacks it
(lines are in the vendored header). The pin is the check file's test title: `D3D11` is
`src/test/webgpuD3d11Check.ms` (WARP), `GL` is `src/test/webgpuGlCheck.ms`.

| call | sokol | caller | pin |
|---|---|---|---|
| `queue.writeTexture` with `origin` and a sub-rect `size` | `sg_update_image` takes whole mips: `VALIDATE_IMAGEDATA_DATA_SIZE` `:24035` through `_sg_validate_update_image` `:25492`; the D3D11 path maps and rewrites every mip `:15249` | glyph page dirty rect: `batcher.c` `doorUpdateTextureRect` → `doorGpu.ms` `doorUpdateTextureRect` | D3D11 and GL "a partial writeTexture changes only its sub-rect…"; Metal "writeTexture writes a sub-rectangle in place over a whole write of the same frame…" |
| `queue.writeBuffer(buffer, offset)` beside other writes in a frame | `sg_update_buffer` writes from 0 once per frame `:25468`, and refuses an append in the same frame `:25487` | `doorGpu.ms` `doorAppendBuffer`, the uniform ring in `doorApplyUniformsOf` | D3D11 and GL "an indexed uint16 quad draws from a vertex buffer written twice in one frame" |
| `copyTextureToBuffer` + `mapAsync`/`getMappedRange`: GPU→CPU readback | no readback or copy function; `readback`, `ReadPixels`, `CopyResource`, `CopySubresourceRegion` and `D3D11_MAP_READ` have no match | `doorGpu.ms` `readTexture` behind `doorReadScreen`: `tests/capture/capture.c`, `tests/capture3d/capture3d.c` | D3D11 and GL "a writeTexture sub-rect reads back through copyTextureToBuffer…", "a cleared render target copies to a buffer…"; D3D11 "the door reads a cleared bgra8 target back as RGBA…" |
| `setBindGroup(group, bindGroup, dynamicOffsets)` on a uniform ring | `sg_apply_uniforms` copies the block into the shader's own constant buffer on every call `:15170` | `doorGpu.ms` `doorApplyUniformsOf` | D3D11 "a WARP triangle takes its colour from the uniform block at the dynamic offset", "a bind group entry offset selects the second uniform block"; GL "a GL triangle takes its colour from the uniform block at the dynamic offset" |
| uniform blocks uploaded only when their bytes changed (D3D11 without D3D11.1) | every applied block is uploaded `:15170` | same | none: no test names the fallback path |
| a bind the context already holds is not issued again (D3D11); `bindStats()` counts native binds | `_sg_d3d11_apply_bindings` clears its bind cache and re-issues all `:15035-15053` | `doorGpu.ms` `doorApplyBindings`, every draw | D3D11 "a bind that did not change issues no native call…"; GL same count pinned (GL already caches as sokol does) |

A bind skip saves time and adds no capability; it is here because the end-game's performance
clause reads it. `bindStats()` has no reader but the check files.

Not a control: `setVertexBuffer`/`setIndexBuffer` offsets (sokol has `vertex_buffer_offsets`
`:3309`, `index_buffer_offset` `:3311`). The rule that bytes written this frame are not written
again is sokol's once-per-frame rule enforced as a stop (`:25468`), kept because Metal and WebGPU
need it; the stop ends the process, so no test pins it.

### No caller yet

These exist and are pinned, and nothing in `src/` outside the backends and the check files calls
them. A caller that arrives gets a row above.

| call | sokol | pin |
|---|---|---|
| `depthSlice` of a colour attachment on a 3D texture | slice must be 0 on a 3D image `:24734` | D3D11 "a colour attachment with depthSlice 2 clears that slice of a 3d texture alone" |
| copy of a depth texture, and of the swapchain texture, to a buffer | no copy (see readback) | D3D11 "a depth16unorm texture round-trips a buffer copy…", "the swapchain texture copies out of the back buffer…" |
| `copyBufferToBuffer`, `copyBufferToTexture`, `copyTextureToTexture`, `writeMappedRange` | no copy | D3D11 and GL "a buffer range copies to a MAP_READ buffer…", "a MAP_WRITE buffer filled through a mapped range…", "copyTextureToTexture copies mip 1…", "a buffer region at an offset…" |
| `dispatchWorkgroupsIndirect` | `sg_dispatch` `:27469` only; `indirect` has no match | D3D11 and GL "a compute pass doubles a storage buffer, directly and through an indirect dispatch" |
| timestamp writes, occlusion queries, `resolveQuerySet` | `timestamp`, `occlusion` have no match | D3D11 and GL "two timestamps around a render pass…", "an occlusion query counts samples…" |
| `doorReadTexture` (any texture, door level) | no readback | D3D11 "the door reads a cleared bgra8 target back as RGBA…" |

## Native calls

A backend's logic (state caches, descriptor translation, the sokol mechanism) is MetaScript.
The driver call goes through a thin C file, one function per driver method, because COM and
Objective-C methods cannot be called from MetaScript directly (measured 2026-10-22: a COM
vtable call emits an `msClosure` call; importing `d3d11.h` by absolute path makes `msc check`
exit 127 with no message). The pattern: a `.h` with opaque typedefs and plain prototypes, a
`.c` with `#define COBJMACROS` and `#include <d3d11.h>`, and `import {…} from "./x.h"` in the
backend module. Metal follows it with a `.m`.

## Metal

`src/webgpu/metal/` ports `_sg_mtl_*`. Where it differs from sokol, the reason is Void's:

- **Two copies of a writable resource, until a GPU copy writes it.** A buffer created with
  `COPY_DST` or a single-subresource texture moves to its other copy at its first CPU write of a
  frame, so the frame in flight keeps reading the old one (sokol's `num_slots`,
  `_sg_mtl_update_buffer`). A resource that a GPU copy has written, a mappable buffer, and an
  attachment texture keep one live copy: a CPU write to them is a staging buffer and a blit in the
  frame's command buffer, ordered behind the frame's earlier reads. Inside a pass no blit can be
  encoded, so there a texture no GPU work has used yet is written by the CPU and any other stops.
  A `writeTexture` that is not a whole single-subresource texture, or a second one in a frame,
  takes the same blit path; a whole write of a mipped, array or 3d texture is a sub-rectangle write
  of its subresource. A second `writeBuffer` over bytes the frame already wrote stops, as before.
- **A readback never waits behind an open command buffer.** `mapAsync` waits for the last
  committed command buffer, and stops by name when the buffer's copy is still in the frame's
  uncommitted one: Metal runs a queue in order, so waiting would deadlock.
- **CPU writes wait on the frame semaphore.** Two frames in flight; the command buffer begins at
  the frame's first write or pass and waits for the oldest frame there, as sokol waits in
  `_sg_mtl_begin_pass`.
- **Command buffers retain their references** (`[queue commandBuffer]`, where sokol takes
  `commandBufferWithUnretainedReferences`), so `destroy*` releases the object at once and needs
  no deferred-release queue keyed on the frame.
- **The drawable comes from the window.** The bridge hands it over with `mtlSetDrawable` when it
  acquires; the pass that renders to the swapchain presents it at `endPass`.
- **Uniform offsets are 256-aligned on iOS too** (sokol: 16), because the door hands every
  backend 256-aligned offsets. It costs uniform-buffer space only.
- **Compute and storage run on the frame's command buffer.** A compute pass, a render pass and a
  blit share it, so Metal orders them by the resources they touch. A compute module takes MSL
  (`computeCode`) and its `workgroupSize`; the shader arc prints both (`main0`), and a pin runs
  such a program on the GPU. A compute stage reads uniform blocks from group 0 as a render stage
  does, through `setBindGroup(0, group, offsets)`, and the pass stops on a missing group or an
  offset past the buffer. Storage bindings are never clamped to the device's range, and a
  storage range's offset is a multiple of 32.
- **A stage loads from metallib bytes when the descriptor has them, else compiles its MSL.**
  `createShaderModule` takes `vertexBytecode`, `fragmentBytecode` and `computeBytecode` through
  `newLibraryWithData` (sokol `_sg_mtl_library_from_bytecode`, `sokol_gfx.h:16565`), and
  `tools/irPrograms.ms` fills them for `metal_macos` (MSL 2.4, macOS 12) and `metal_ios` (MSL 2.4,
  iOS 15) from `src/shader/metallib/`, as it does DXBC. A cold Metal cache spends 160-240 ms per
  module on source and 0.03 ms on a metallib. The iOS simulator takes no bytecode: an iphoneos
  metallib loads there but its pipelines fail, so a stage with no source stops by name.
- **Timestamps need `MTLCounterSamplingPointAtStageBoundary` and are refused on Intel.** A render
  pass writes them; `timestampWrites` on a compute pass stops by name, because on an Apple GPU the
  compute sample is not written before a resolve that follows it in the same command buffer
  (a second dispatch after the pass makes it appear).

On the Apple GPU the goldens differ from the D3D11 set by up to 4 levels on text, filter and
shadow rows; a sokol Metal build of the merge base captured the same 58 rows byte-identical to
this backend (2026-10-22), so the difference is the GPU, not the port.

The JS target calls `navigator.gpu` through `extern class` declarations in a `.jms` file. A
`Vec<float32>` is a plain JS Array there and only a fixed `float32[N]` is a `Float32Array`, so
`writeBuffer` copies a growable array into a typed array on JS.

## Coverage against sokol's pin

The layer covers every backend and platform that sokol `2e75443d` covers, Vulkan included and
supported in full rather than as sokol's experimental backend. A cell counts once goldens run
on it. As of `932a1562`:

| backend | platform | state |
|---|---|---|
| D3D11 | Windows | goldens 119/120 (`prim/boxFills` red) |
| GL core | Windows (WGL) | goldens 94 pass, 26 pending |
| GL core | Linux X11 (GLX) | demo in WSLg at `4b66e809`, no goldens |
| GLES3 | Android | links, never run on a device |
| GLES3 | Linux (EGL) | missing |
| WebGL2, WebGPU | browser | demo in headless Chrome, no goldens on this branch |
| Metal | macOS, iOS | goldens 120/120 |
| Metal | iOS simulator | demo only |
| WebGPU native | desktop | missing (sokol: experimental) |
| dummy | any | missing |
| Vulkan | Windows, Linux X11 | device, copy, clear, draw, compute and swapchain tests on NVIDIA and AMD, and on lavapipe with sync validation; no goldens until `backend.ms` |

GL core on macOS is deprecated by Apple and stays out unless asked. Wayland is beyond sokol,
whose `sokol_app.h` has no Wayland path.

Mach (`4be8e50f`) and Heaps (`b9aa6dcb`) are the references for this layer. Another source
decides a concern only where both lack it, and the text names why.

The Vulkan backend ports Mach's `src/sysgpu/vulkan.zig`:
- the tables of `vulkan/conv.zig`;
- Vulkan 1.1 with a negative viewport height (vulkan.zig:14, 3320);
- the render-pass key cache (vulkan.zig:726-863);
- the barrier tracker's hazard rules with resting layouts (vulkan.zig:2755-3088);
- the swapchain handoff through `oldSwapchain` (vulkan.zig:1001, 1117).

The port leaves Mach where Mach's code is wrong, each case pinned by `vulkanResourcesCheck.ms`,
`vulkanMemoryCheck.ms` or `vulkanDraw.ms`:
- a buffer-to-image row length counts texels of the format, not `bytes_per_row / 4`
  (vulkan.zig:2625; Dawn `UtilsVulkan.cpp:262-267`);
- `rgb10a2unorm` is `A2B10G10R10` (64), where `conv.zig` gives the red-blue swapped 58
  (Dawn `TextureVk.cpp:480`);
- copy usages add the transfer stage to a resource's resting state, and a layout change waits on
  the stages it leaves rather than on top-of-pipe, because either gap leaves a copy hazard
  unordered; the synchronization validation layer reports it when the fix is reverted;
- a cube-compatible image needs one sample (VUID-VkImageCreateInfo-samples-02257);
- a texture written twice in an unchanged layout gets a memory dependency, as Mach's buffer path
  already has; Mach's texture path has none, and sync validation reports write-after-write;
- a swapchain image enters the tracker at acquire as a write from `UNDEFINED`, and each image has
  its own present semaphore (Dawn `SwapChainVk.cpp:233-235`), where Mach transitions images at
  creation, before any acquire, and shares one semaphore;
- an integer target clears with integer values, where Mach clears every format as float;
- a viewport flips to `y + height` with a negative height, as Dawn does
  (`CommandBufferVk.cpp:2066-2069`), where Mach's `setViewport` flips to `extent.height - y`
  (vulkan.zig:3459-3466), which is right only for a viewport that reaches the bottom edge;
  a zero-width viewport becomes an empty one of width 1 and height 0, because Vulkan requires
  a positive width (VUID-VkViewport-width-01770).

Render-pass layouts follow Dawn (`RenderPassCache.cpp:176-208`): a pass starts and ends in the
attachment layout and the tracker moves the texture before the pass, where Mach's passes move
it inside the pass from top-of-pipe.

A resource whose driver requires its own allocation gets a dedicated block, and one that only
prefers it gets one until a quarter of `maxMemoryAllocationCount` is left, as VMA does (Godot
`876b290` `vk_mem_alloc.h` 13274-13280, 13555-13590, 13726). Mach, Heaps and Dawn do not read the
dedicated requirements of ordinary resources.

Mach's Vulkan file has gaps, filled from Mach and Heaps first:
- **Memory:** Mach allocates per resource (vulkan.zig:1247, 1416). The backend suballocates
  through Mach's own `gpu_allocator.zig`, which only its D3D12 backend uses (d3d12.zig:696-872).
- **Frames and descriptors:** Mach has one descriptor pool per bind group (vulkan.zig:1731),
  a framebuffer per pass (vulkan.zig:3295) and a fence per submit (vulkan.zig:3531). The backend
  follows Heaps' `DX12Driver.hx` instead: a per-frame bump heap reset each frame (243-296, 1127)
  and descriptor tables built only when the bindings change (2770-2783, 2872-2931).

Where neither has the concern, the backend goes elsewhere. Heaps' `VulkanDriver.hx` is an
86-line stub abandoned for DX12 in 2021, and Mach has no Android platform (`Core.zig:816`):
- **Swapchain loss and present mode:** Dawn `1716e88` `SwapChainVk.cpp` covers SUBOPTIMAL,
  OUT_OF_DATE, SURFACE_LOST and the Adreno/Mali acquire timeout (468-556), and present modes
  fall back to FIFO (245-275).
- **Render-pass dependencies and per-image present semaphores:** Dawn.
- **Mobile driver workarounds:** Dawn's vendor toggles (`PhysicalDeviceVk.cpp:1025-1417`).
- **Validation layer:** wgpu `100c142` probes for it before enabling it (`instance.rs:847-915`),
  which also works from an APK.
- **Android pre-rotation:** Godot `876b290` `rendering_device_driver_vulkan.cpp` (3162, 3235-3282).
  Dawn and wgpu present at identity.
- **Lifecycle:** Void's own Android host owns it (`bridgeAndroidApp.c:277-298`). The swapchain
  and surface go down in `nativeSurfaceGone`, before the window is released.

SPIR-V is printed from the shader IR as one more target, as Mach prints it from its Air
(`shader/CodeGen.zig:153-158`). Vulkan has no load-time compiler, so SPIR-V generated by an
external tool would leave a program dead on a cache miss. For each lowering, naga's
`back/spv` is the code read, because Mach's emitter ignores the array layer, lacks depth
compare, atomics and `switch`, and swaps `sample_index` and `sample_mask` (`spirv.zig:2773`).
spirv-val and naga check the printer's output.

Sokol's `_sg_vk_*` is a comparison only. It requires Vulkan 1.3 and `VK_EXT_descriptor_buffer`
(sokol_app.h 4447, 4558) and calls itself highly experimental.

Every platform compiles the backend against one pinned copy of Khronos Vulkan-Headers,
v1.4.341, kept in `deps/vulkan-headers/include`. The OS's own headers are not used. Mach
(`build.zig.zon:52`), Dawn (`DEPS:396`) and Godot (`thirdparty/vulkan`) each pin their own copy
the same way. The Windows toolchain ships no Vulkan headers, and a pin keeps Windows, Linux
and Android on one API version.

## Beyond sokol on the frame path

Each item is built once a probe shows the cost it removes; the A/B against main decides.

- **Frame calls:** the door's frame calls (pass begin, pipeline, bindings, uniforms, draw) reach
  each backend as thin, unchecked calls, as Heaps' `Driver.hx:285-316` does. The WebGPU
  descriptors stay the surface for creation, as in Mach (`main.zig:976-1068`). A resource id
  in these calls indexes a dense array directly.
- **Uniforms:** stay on the ring with dynamic offsets. Mach binds every backend this way
  (d3d12.zig:3839-3848, metal.zig:2055, opengl.zig:1915), and so does Heaps on DX12 (243-296).
  - An upload whose bytes match the last one is skipped (Heaps `DirectXDriver.hx:1239-1253`).
  - Globals upload per shader switch and params per draw (Heaps `h3d/pass/Output.hx:103-118`).
  - A slot is rebound only when its buffer changes (`DirectXDriver.hx:1259-1281`).
  - GL uploads each block at its own frequency rather than under one dirty bit
    (`GlDriver.hx:605-623`).
- **Bindings:** compared against the last applied set, and work is done only on a change.
  Views and samplers are cached per resource rather than as whole groups (DirectXDriver.hx
  1336-1394, DX12Driver.hx 2770-2783). There is no hashed key per apply.
- **D3D11 state:** native state persists across passes with no `ClearState`, as in Heaps,
  whose DirectXDriver has none. Before a texture is set as a target, its shader-resource view
  is unbound from both stages (`DirectXDriver.hx:969-980`). A test binds a texture, then renders
  into it in the next pass.
- **Pass begin:** D3D11 caches render-target views per texture and subresource (Heaps
  `DirectXDriver.hx:943-1015`). GL uses one shared framebuffer, re-attached on each target
  change (`GlDriver.hx:1842-1867`). Vulkan caches the render pass by key (Mach).
- **Draw order:** void3d sorts opaque draws by layer, shader and texture, using ids renumbered
  each frame. Alpha draws sort by layer, then depth back to front (Heaps `SortByMaterial.hx:15-29`,
  `scene/Renderer.hx:104-131`). Neither reference packs a radix key.
- **Instance data:** void2d builds instances in a CPU `Vec` and uploads once per flush, as Heaps
  (`h2d/RenderContext.hx:595-605`) and Mach (`gfx/Sprite.zig:540-561`) do. Writing straight
  into mapped memory (GPUI `metal_renderer.rs:1531-1574`) waits on a measured copy cost,
  because neither reference does it.

## Steps

The card `~/metascript/.wt/gpu-ms.md` tracks where the branch is. The order: the API module
and the D3D11 backend, then void2d, void3d and the door on it; WebGPU (C through
`webgpu.h`, JS through `navigator.gpu`); GL; window and time; shader tables without
`sokol_gfx.h`; Metal; delete every sokol include.
