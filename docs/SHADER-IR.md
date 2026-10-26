# Shader IR — what is fixed before any printer

The authoring side (macros, vocabulary, entry convention) is [src/shader/CLAUDE.md](../src/shader/CLAUDE.md);
the tiers are [SHADER.md](SHADER.md). This note holds the decisions the IR (`src/shader/ir.ms`)
and its printers rest on, which the code shows only as their result.

## One IR, five printers

The macros lower a typed MetaScript body once, into plain data (`ShaderModule`), and each target
is a printer of its own: `printGlsl450` (sokol-shdc's dialect, kept as the regression text),
`printGlsl` (GLSL 430 and ES 3.00), `printHlsl` (SM5), `printWgsl`, `printMsl`. This is Mach
sysgpu's split: `src/sysgpu/shader/Air.zig` is the one IR, `CodeGen.zig` `generate` dispatches to
one file per language under `codegen/` (`glsl.zig`, `hlsl.zig`, `msl.zig`, `spirv.zig`; Mach
`4be8e50f`). The alternative, one GLSL source cross-compiled by sokol-shdc (glslang + SPIRV-Cross),
went with sokol: Void's own GPU layer ([GPU.md](GPU.md)) takes a `GPUShaderModuleDescriptor`, and
an author error now stops at the author's line instead of in SPIRV-Cross's output.

A rule every target shares is an `irErrors` invariant, checked on every program
`descriptor.ms` builds (`checked`) before any printer runs; a rule only one language has is a refusal in that printer, naming the language. When
two printers would need the same lowering, it is an IR rewrite ahead of all of them
(`descriptor.ms` `colourWritten` is the pattern), not a copy per printer.

## Layout and binding before any printer

Slots, groups and uniform block offsets are decided once on the IR (`layout.ms` `bindingSlots`,
`uniformBlockLayout`) and every printer and the reflection read that decision; no printer numbers
a binding of its own. This is Heaps' order: `hxsl/Flatten.hx` `Flatten.flatten` packs the globals
before `GlslOut`/`HlslOut` run (Heaps `b9aa6dcb`). The WebGPU shape is kept for every backend:
uniform blocks in group 0, textures and samplers in group 1, a sampler at `MAX_VIEW_SLOTS` plus
its binding; HLSL and MSL take a uniform block's or sampler's native register from the
author's `@binding`.

Two resources of one kind may share a binding in a module, as `LitBindings` gives one view slot
to `backTexture` and to `metalRoughTexture`, because each program key reads at most one of them:
sokol-shdc laid out each `#ifdef` variant alone, and Heaps flattens each variant alone. The
check that holds is per program after specialization (`bindingSlots`: "this program reads
both"); `irErrors` refuses only two kinds at one binding.

## Reflection and its markers

The reflection is the `GPUShaderModuleDescriptor` of `src/webgpu/types.ms`, written by
`reflect.ms` `reflectProgram` and `reflectCompute`, the format gpu-ms's backends read. A change
to it is agreed with the gpu-ms arc first ([GPU-MS.md](GPU-MS.md) "Working together"), because
a backend reading a field the printer no longer writes fails only at draw time.

A binding is one entry per `(group, binding)`: its `visibility` is WebGPU's `GPUShaderStage`
mask of the stages that read it, and a view both render stages read takes the first native
slot free in each, the same in both stages' text, so D3D11 and Metal bind it once per stage
at one register. GL gives a combined sampler one unit for the whole program, since a linked
program refuses one uniform declared at two bindings.

- `DUMMY_SAMPLER_BINDING` (`-1`): GL has no fetch without a sampler, so a `textureLoad` texture
  that its stage samples through no sampler is paired with this binding, and the GL backend
  binds a sampler of its own there (`src/webgpu/gl/backend.ms`). No other backend sees it.
- `NUM_WORKGROUPS_BINDING`: reserved, not yet in code. HLSL has no system value for
  `numWorkgroups` (`printHlsl` refuses it by name); when a compute program needs it on D3D11,
  the count arrives in a uniform at this binding, which the backend fills at dispatch (Tint's
  `NumWorkgroupsFromUniform` does the same for Dawn; not read here). The binding number is
  chosen with gpu-ms, not by the printer.

## Conventions the IR fixes

- **No Y flip, no clip-Z remap.** Every printer writes the position the author computed. Clip
  space is the host's: the projection the app builds is the backend's. sokol-shdc did the same
  unless a program asked for `fixup_clipspace` or `flip_vert_y` (sokol-tools `0c591c3`
  `src/shdc/spirvcross.cc` `to_glsl`, `to_hlsl`, `to_msl` set both from the program's options,
  off by default), and no Void program asked.
- **Matrices are column-major,** as WGSL, GLSL and MSL hold them, and the host uploads them so.
  HLSL prints each matrix transposed under `row_major`, so `M * v` becomes `mul(v, M)` on the
  same bytes (`printHlsl.ms`, the note above `printHlsl`).
- **An array layer is an operand of its own,** after the coordinates, as WGSL's
  `textureSample(t, s, coords, layer)`. GLSL and HLSL pack it into the coordinate vector,
  MSL passes it as `uint`; the IR never holds the packed form, so no printer unpacks one.
- **A conditional is WGSL-safe.** WGSL's `select` evaluates both arms, so `printWgsl` hoists a
  conditional whose arm calls a function into a `var` assigned in an `if`, as Tint's
  `PromoteSideEffectsToDecl` does, and refuses one it cannot hoist without reordering an effect
  (`printWgsl.ms` `isHoisted`, `hoistReason`).
- **An attribute, varying or output is a scalar or vector,** WGSL's user-defined IO: refused at
  the author's field and in `irErrors` (src/shader/CLAUDE.md, "An author struct is a GLSL struct").
- **A discard demotes the invocation to a helper,** WGSL's meaning: it runs on, so a derivative
  its quad takes afterwards stays defined. GLSL, HLSL and SPIR-V end the invocation instead, and
  the void2d checker's `fwidth` tie bias read undefined values beside a clipped neighbour on GL
  (the `clip/roundedMask` golden). `demote.ms` `demotedDiscards` therefore rewrites a discarding
  fragment program at the start of `printGlsl`, `printHlsl` and `printSpirv`, as Tint's
  `DemoteToHelper` does for those writers (Dawn `1716e88`,
  `src/tint/lang/core/ir/transform/demote_to_helper.cc`): a discard sets the private flag
  `demoted`, a storage write or effect intrinsic runs only while it is clear, and the entry
  discards before it returns. An effect intrinsic whose result is read is refused by name.
  MSL keeps `discard_fragment`, which is uniform from Metal 2.3 and Void compiles Metal 2.4;
  Dawn lowers it on Apple GPUs only against a per-sample-shading driver bug
  (`src/dawn/native/metal/PhysicalDeviceMTL.mm:454-465`), not measured here. SPIR-V keeps the
  flag rather than `OpDemoteToHelperInvocation`, which needs SPIR-V 1.6 or an extension where
  Void prints 1.3.

## Validators run beside the code, never in the app

fxc (`scripts/validateHlsl.sh`, the flags `D3DCompile` gets at load), naga for WGSL
(`scripts/validateWgsl.sh`) and naga's GLSL front end check printed text in the repository's
probe directories (`out/hlslProbe/`, `out/wgslProbe/`, `out/glslProbe/`, `out/shadyPrograms/`),
which the shader checks write. They are developer and CI tools: no binary carries a validator,
and an app's program is printed by `shaderProgram` while msc compiles it, then compiled by the
driver as any source. The gate's oracle step runs `regen-shaders.sh --check`, which leaves every
stage of every program in `out/irPrograms/`, then fxc and naga over it: 518 HLSL stages in 26 s
and 518 WGSL files in 18 s, the regen itself about 4 min (2026-10-24, Windows); a missing tool
is a named SKIP. GLSL stays a SKIP: naga reads GL GLSL only after a rewrite to Vulkan 450
(combined samplers split, locations added) that lives outside the repository. On a Mac
`scripts/validateMsl.sh` compiles every MSL stage with `xcrun metal -c`, the `_ios` ones against
the iphoneos SDK, with no options, as `newLibraryWithSource` gets none: 1036 stages in 2.5 min,
plus the shader checks' `out/mslProbe/` (2026-10-24). Other hosts have no Metal compiler and
SKIP it.

## The DXBC cache

D3D11 compiles HLSL at load with `D3DCompile`, about 15 ms a stage (30 ms a program at first
use), so the generated modules carry each HLSL stage's DXBC precompiled, as Heaps caches compiled
shaders per platform keyed by a hash of the generated source (`hxsl/CacheFile.hx`,
`h3d/impl/ShaderCache.hx`). `tools/irPrograms.ms` keys a stage by the SHA-256 (`std/crypto/sha256`)
of its profile, entry point, flags and printed HLSL, and reads `src/shader/dxbc/<key>.dxbc`; on a
miss it runs fxc with the backend's flags (`-Zpc -O3`, `d3d11.c` `d3dCompile`). The cache sits
with the shader layer because one blob serves every module that prints the same stage: 518 HLSL
stages are 168 blobs, 0.92 MB (2026-10-23). The `windows` arm holds each blob once as base64
(`shaderBytecodeFromBase64`, `src/shader/dxbc.ms`) and leaves that stage's HLSL text empty, which
cut forwardOutline.exe from 13.94 to 13.20 MB (2026-10-24); a stage with no blob keeps its text.
Every other arm writes `[]`, since gl, wgpu and metal stop on bytecode.

fxc and the runtime `D3DCompile` (`d3dcompiler_47.dll`) gave the same bytes for a 22-stage sample
(2026-10-23, fxc of Windows Kit 10.0.26100). `regen-shaders.sh` adds a compiled blob and deletes
one no stage uses; `--check` reports either as stale. Where fxc is absent (macOS, Linux) a miss is
printed, not stale: that stage keeps no bytecode and compiles at load until a Windows regen.

## The oracle

sokol-shdc is on no build or regeneration path, and `deps/sokol-tools-bin` is not fetched. The
golden captures (`docs/baselines3d.sha256`, `scripts/web3d.sh`) drawn from the IR-printed modules
are the oracle; the GLSL 450 printer's text is only a regression pin.
