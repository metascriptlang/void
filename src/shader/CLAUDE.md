# src/shader — shaders written in MetaScript

**Goal.** A shader is an ordinary MetaScript function. A macro `glsl(fn)` reads its typed body and emits
Vulkan-style GLSL 450 for sokol-shdc, which emits every backend. The same function runs on the CPU as a
logic oracle in the native gate. Shader-tier context: [docs/SHADER.md](../../docs/SHADER.md) Tier 3.

**Why now.** void3d hand-writes one program per feature combination (`Program` in `src/void3d/gpu3d.ms`),
and `ProgramMap` packs at most 24 of them. void3d's feature-bit ProgramKey keys the variants, and this module
later replaces the hand-written GLSL source of each base.

## Design

- **One GPU target: sokol-shdc GLSL 450.** Metal, D3D11, GL, GLES3/WebGL2 and WebGPU all come from shdc.
  A feature sokol cannot express gets a native door and a hand-written per-backend shader for that
  program only (`sg_shader_desc` takes raw per-backend source).
- **Emitter = macro library, not a compiler backend.** On msc `244ef48c`, `getImpl(bindSym("frag"))`
  inside a macro returned the `FunctionDecl` with checker types on every expression (`typeKind` Float32
  on `uv.x * t`).
- **The emitter enforces the shdc dialect at the MetaScript source**, so the error points at the
  author's code: textures and samplers are separate; uniform block members are only float, int,
  vec2–4, ivec2–4, mat3, mat4, and arrays only vec4, ivec4 or mat4; no recursion. The emitter packs an
  author's struct into those types, so a uniform block's layout comes from one MetaScript struct.
- **Entry convention** (shady's, approved 2026-10-10). A plain parameter is a stage input and an
  `out` parameter an output, each at `layout(location)` in parameter order. A `FragCoord` parameter is
  `gl_FragCoord`. `Texture2D` and `Sampler` parameters are separate uniforms, bindings counted per kind
  in parameter order. The stage and program name are the generator's (`@fs copyFs`), not the function's.
- **Builtins by declaring module.** A call to a function declared in `glsl.ms` emits under that
  declaration's name; a struct getter declared there emits as the swizzle it names. Any other callee
  is the user's (slice 2: emitted transitively). The walk sits in nested functions of the macro body:
  a top-level helper cannot read `Node` fields.
- **Generated GLSL lives on disk.** `tools/genShaders.ms`, run by `scripts/regen-shaders.sh`, writes
  `src/void3d/shader3dGen.glsl`, which `shader3d.glsl` includes; `--check` is the staleness gate.
  Runtime modules never call `glsl`, so no binary carries GLSL text.
- **CPU oracle within a tolerance, never pixel-exact.** GLSL allows contraction and looser ULP bounds,
  and `sin`/`exp` are implementation-defined. shady's own tests use `1e-4`. Pixel truth is
  the readback in `tests/capture3d/capture.c`.

## Compiler surface the emitter relies on

Measured 2026-10-08 on installed msc BUILD `99a851d7`, C and `--target=js` identical, probes in
`out/shaderPrerequisites/`. Compiler pins: corpus `macroTypedBodyCalleeIdentity`,
`macroTypedBodyBeforeDeclaration`, `macroOutputKeepsSymbols`, `macroSeesGetterIdentity`,
`accessorStructGetter`.

- **Callee identity.** `getImpl(callee)` on a callee in a typed body returns the declaration the call
  resolved to: an imported helper, a same-named helper under an alias, the winning overload, an
  imported module constant. Never look a callee up by its spelling.
- **Declaration order.** A body read before its declaration comes back checked.
- **Swizzles.** `get xy()` in a struct body: `v.xy` is a value read with no heap object, and a
  receiver with side effects runs once.
- **Macro output keeps its symbols**; a local placed outside its own function is an error.
- A top-level helper cannot read flat `Node` fields; a function nested in the macro body can, and
  recurses (measured 2026-10-11, BUILD `89005562`).
- **Open:** a literal `bindSym("name")` node has `resolvedSym == null`, while the computed form and
  every typed-body callee carry it (`out/shaderPrerequisites/bindSymSymbol.ms`, C and JS). The
  builtin check needs it: card `~/metascript/.inbox/compiler/2026-10-11-bindsym-literal-node-has-no-symbol.md`.

## Measured — sokol-shdc coverage

`sokol-tools-bin` `11d0cf6`, win32 sokol-shdc, void tree `ec6ca36`. Compile-only probes, 55 features ×
`metal_macos:hlsl5:glsl300es:glsl430:wgsl`.

- **Pass on all five**: control flow, structs, uint/bit ops, flat/noperspective/centroid,
  VertexIndex/InstanceIndex, FragDepth, discard, derivatives, every sample/fetch/gather (gather not
  ES300), shadow compare, cube/3D/2D-array, uint textures, MRT, dual-source, storage buffers in VS/FS,
  SampleID/SampleMask, compute with shared memory, barriers, atomics and storage images (not ES300).
- **shdc's own limits**: arrays of textures, `gl_PrimitiveID` and `invariant` fail only on Metal,
  because shdc never sets an MSL version (`sokol-tools` `0c591c3` `src/shdc/spirvcross.cc` `to_msl`).
  Subgroup ops fail everywhere, because the GLSL → SPIR-V step targets SPIR-V 1.0 (`src/shdc/spirv.cc`,
  `EShTargetSpv_1_0`). Both are option patches in shdc, not reasons to emit HLSL or MSL ourselves.
- **Walls neither shdc nor self-emitting can pass**: sokol API (spec constants compile, but sokol has
  no field for them, so the default always wins; push constants; framebuffer fetch degrades to a
  texture read; bindless; indirect) and platform floors (WebGL2, WebGPU core, D3D11 SM5).
- **Precision**: the `precision mediump float;` line in shdc's ES output is only the default.
  SPIRV-Cross qualifies every variable, varying, uniform and sampler `highp`. `precision highp float;`
  in the source changes nothing. Only `precision mediump float;` in the source drops the qualifiers.

## Rejected

- **Own HLSL/MSL/GLSL backends, as shady has.** About 1000 of the 1817 lines of shady's `shared.nim` are
  per-backend layout, and it has no WGSL. Every wall above is in sokol or the platform, not in shdc.
- **A GLSL backend inside msc** (what docs/SHADER.md Tier 3 still says). The macro already reads the
  typed body, so only the callee gap needs the compiler.

## Reference

- `treeform/shady` `c899f7c` (clone at `~/projects/shady`): `src/shady/backends/shared.nim` `gatherFunction`
  (pulls in callees and module globals transitively), `toGLSLInner`, `toCode`. CPU stubs for texture
  and derivatives sit at the end of the same file. `Uniform[T]` marks a uniform, a plain parameter is
  an input, a `var` parameter is an output.
- `floooh/sokol-tools` `0c591c3` (clone at `~/projects/sokol-tools`): `docs/sokol-shdc.md` "GLSL uniform
  blocks and C structs" and "Storage buffer content restrictions".
- Heaps HXSL: [docs/HEAPS.md](../../docs/HEAPS.md).
