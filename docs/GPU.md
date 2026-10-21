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

Only what Void calls exists: the inventory of sokol uses is the scope, and a WebGPU feature
with no Void caller (compute, storage buffers, stencil, mipmaps, cube/3D/array textures,
topologies other than triangle-list, readback) is left out until one appears.

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

Until Void has its own emitter, sokol-shdc stays the compiler, but its output is read as data:
the per-language source and the reflection, not `sg_shader_desc`. The generated table is
Void's `GPUShaderModule` descriptor, so nothing includes `sokol_gfx.h`. D3D11 compiles HLSL
source at load with `D3DCompile`, as sokol does (`sokol_gfx.h:14127`, `:14143`).

## Window, surface and time

The device and the per-frame target were already Void's on every platform except two:
`sokol_app` drove the Windows window (`SOKOL_NOAPI`, `docs/SOKOL.md`) and the web window path
(with `sokol_glue`). The Windows window is ported from `sokol_app.h` (Win32 `:8635-10514`) into
`src/platform/win32/`, keeping `sapp_event`'s fields and ordinals in `src/platform/appEvent.h`
because `src/sokol/window.ms` `AppEventType` mirrors them; its clock is `QueryPerformanceCounter`
(`src/platform/win32/clock.h`). The web window (`:7792-8350`) and the other clocks
(`mach_absolute_time`, `clock_gettime`, `performance.now`) are still sokol's.

## The door on this layer

The render layers above keep the door's contract (`src/gpu/door.h`, `door.ms`): flat descriptor
words, `uint32` ids, programs and layouts registered by index. `src/gpu/doorGpu.ms` carries that
contract onto the WebGPU-shaped API, adding the two things WebGPU leaves to its caller and
sokol's WebGPU backend does for it:

- **Uniforms** go to one 4 MiB uniform buffer at 256-aligned offsets, rewound at commit, and
  reach the shader through the pipeline's group 0 with one dynamic offset per block (sokol's
  uniform system, `_sg_wgpu_uniform_system_*`, `sokol_gfx.h:18387`).
- **Textures and samplers** of a draw become a group 1 bind group looked up in a cache keyed
  by the pipeline and the bound ids; a collision replaces the entry, as sokol's
  `_sg_wgpu_bindgroups_cache` does (`:18462-18763`).

## Native calls

A backend's logic (state caches, descriptor translation, the sokol mechanism) is MetaScript.
The driver call goes through a thin C file, one function per driver method, because COM and
Objective-C methods cannot be called from MetaScript directly (measured 2026-10-22: a COM
vtable call emits an `msClosure` call; importing `d3d11.h` by absolute path makes `msc check`
exit 127 with no message). The pattern: a `.h` with opaque typedefs and plain prototypes, a
`.c` with `#define COBJMACROS` and `#include <d3d11.h>`, and `import {…} from "./x.h"` in the
backend module. Metal follows it with a `.m`.

The JS target calls `navigator.gpu` through `extern class` declarations in a `.jms` file. A
`Vec<float32>` is a plain JS Array there and only a fixed `float32[N]` is a `Float32Array`, so
`writeBuffer` copies a growable array into a typed array on JS.

## Steps

The card `~/metascript/.wt/gpu-ms.md` tracks where the branch is. The order: the API module
and the D3D11 backend, then void2d, void3d and the door on it; WebGPU (C through
`webgpu.h`, JS through `navigator.gpu`); GL; window and time; shader tables without
`sokol_gfx.h`; Metal; delete every sokol include.
