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
- **Vocabulary is TypeGPU's** ([docs/VOCABULARY.md](../../docs/VOCABULARY.md)): `Vec4f`, `Vec2i`/`vec2i`,
  `textureLoad`, `textureDimensions`, `@builtin(position)`. `std.ms` declares it with CPU
  meaning; the emitter spells each declaration in GLSL.
- **Entry convention** (TypeGPU's `fragmentFn`, approved 2026-10-13; it replaces the shady `out`
  parameter approved 2026-10-10). The stage input is one struct parameter and the colour is the
  return value, so an entry writes to nothing it was handed and the CPU call is the GPU call. A field
  decorated `@builtin(position)` reads `gl_FragCoord`. `Texture2d` and `Sampler` parameters are
  separate uniforms, bindings counted per kind in parameter order. The stage and program name are the
  generator's (`@fs copyFs`), not the function's. Written `fragColor = value; return;`, the output
  compiles to the same seven backend sources as a hand-written assignment (measured below).
- **Builtins by declaring module.** A call to a function declared in `std.ms` is a builtin; a struct
  getter declared there emits as the swizzle it names. The walk sits in nested functions of the
  macro body: a top-level helper cannot read `Node` fields.
- **The author's functions and module constants are gathered as shady's `gatherFunction` does.**
  Each one the entry reaches is defined above `main()` once, after what it reads; a module `const`
  becomes a GLSL `const`, so its name survives into the source. A definition is known by its
  declaration (module, line, column), so an overload pair stays two GLSL overloads. Recursion, a
  module `let` and a constant initialized by a call are errors at the author's code.
- **A name GLSL already holds is renamed, as TypeGPU's strict naming does** (`resolutionCtx.ts`
  `makeUniqueIdentifier`): a keyword, a builtin, or a name another definition took gets `_1`,
  `_2`, …; a local is also kept apart from every defined name, so it never hides one it reads.
  A name GLSL cannot spell (`__`, `gl_`, a character outside letters, digits and `_`) is an error.
- **Generated GLSL lives on disk.** `tools/genShaders.ms` prints the stages and
  `scripts/regen-shaders.sh` writes them to `src/void3d/shader3dGen.glsl`, whose stages join
  `shader3d.glsl`'s for every program key; `--check` reports a stale file. Runtime modules never
  call `glsl`, so no binary carries GLSL text.
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
- **Declaration identity.** `getImpl` returns a fresh copy each call, so nodes do not compare,
  and `resolvedSym` carries `name`, `modulePath` and `symbolKind` but no `item`, `disamb`,
  `overloadIdx` or `Global` flag; a declaration's `line` and `column` tell it apart, and a
  parameter has no declaration (measured 2026-10-15, BUILD `9cf5708c`).
- **Swizzles.** `get xy()` in a struct body: `v.xy` is a value read with no heap object, and a
  receiver with side effects runs once.
- **Macro output keeps its symbols**; a local placed outside its own function is an error.
- A top-level helper cannot read flat `Node` fields; a function nested in the macro body can, and
  recurses (measured 2026-10-11, BUILD `89005562`).
- **Builtin module identity.** A literal `bindSym("name")` carries `resolvedSym.modulePath`, the
  declaring module also for an imported name (BUILD `9a4775dc`, corpus `bindSymLiteralCarriesSymbol`).
- **Signature.** `getType(entry)` is a `TypeFunction` whose parameter and return nodes answer
  `sameType` and `getTypeImpl`. The `FunctionDecl` from `getImpl` has no `typeExprs`, and its
  `fnParamTypes` are text: `resolveType` on them resolves at the expansion site, where the caller of
  `glsl` need not import the shader's types (measured 2026-10-13, BUILD `9a4775dc`, `out/shaderProbe/entry/`).
- **Field decorators.** `typExprFieldDecorators` gives `@builtin(position)` as a `MacroInvocation`
  with `macroName` and unevaluated `macroArgs`, C and JS. It carries no symbol, so the decorator is
  known by name, as the language defines field decorators. A type alias cannot mark a builtin: the
  field of `type BuiltinPosition = Vec4f` comes back as `Vec4f`.

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
- **No fetch without a sampler** (measured 2026-10-13, same shdc). `texelFetch(texture2D, …)` and
  `textureSize(texture2D, …)` need `GL_EXT_samplerless_texture_functions`, and with it shdc stops at
  `SPIRVCross exception: texelFetch without sampler was found, but no dummy sampler has been created
  with build_dummy_sampler_for_combined_images()`. So `textureLoad` and `textureDimensions` take a
  sampler here, where WGSL's take none; the parameter goes when shdc builds the dummy sampler.
- **Walls neither shdc nor self-emitting can pass**: sokol API (spec constants compile, but sokol has
  no field for them, so the default always wins; push constants; framebuffer fetch degrades to a
  texture read; bindless; indirect) and platform floors (WebGL2, WebGPU core, D3D11 SM5).
- **Precision**: the `precision mediump float;` line in shdc's ES output is only the default.
  SPIRV-Cross qualifies every variable, varying, uniform and sampler `highp`. `precision highp float;`
  in the source changes nothing. Only `precision mediump float;` in the source drops the qualifiers.

## Measured — copyFs against the hand-written stage

2026-10-13, BUILD `9a4775dc`, `sokol-tools-bin` `11d0cf6`,
`metal_macos:metal_ios:metal_sim:glsl300es:glsl430:wgsl:hlsl5`. With copyFs generated,
`src/void3d/shader3d.glsl.h` is byte-identical to main's at `5dbcb662`, where copyFs is hand-written:
the seven copy fragment sources and every other program's. So the programs the GPU receives did not
change, on any backend shdc emits.

That holds because `textureDimensions` returns `Vec2i`. Returning `Vec2u` as WGSL does, the emitted
`ivec2(uvec2(textureSize(…)))` survived as text into all seven copy fragment sources (`uint2(int2(…))`
in HLSL, two `bitcast` in WGSL). The image checks below ran on that earlier form, on base
`24183064` where copy still wrote alpha 1 (tree `f7a7b18c9183`, Windows x64, one quiet GPU window),
so they also cover the path from the generator through shdc:

- **D3D11**: `GATE_SKIP_ANDROID=1 GATE_SKIP_BENCH=1 GATE_SKIP_CHURN=1 sh scripts/gate3d.sh` exit 0,
  363 PASS, 0 FAIL; every capture row "4 frames byte-identical" to `docs/baselines3d.sha256`,
  among them the forward-preset rows that draw through Copy (`texturedCapture`, `gltfCapture`,
  `perspectiveCapture`). The two pending rows (`campfireForwardCapture`, `campfireAnchorCapture`)
  matched their held fingerprints.
- **WebGL2**: `sh scripts/web3d.sh` 17 of 17 with origin's `16a6ea60` (web runtime kept alive)
  applied to the tree; 0 of 17 without it, every run `Uncaught ExitStatus`, which is the base
  (`24183064` lacks that commit) and not the shader. All nine checks build a `ForwardRenderer`.
- **WebGPU**: the `wgpu` build of `tests/integration/renderOrder.ms` passes; no capture exists for
  it (`scripts/web3d.sh` header). Not run: GLES3 on a device, Metal.

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
- `software-mansion/TypeGPU` `1f9d89d`, typegpu 0.12.7 (clone at `~/projects/TypeGPU`):
  `packages/typegpu/src/builtin.ts`, `std/texture.ts`, docs `apis/functions/index.mdx` (entry functions
  and the builtin table).
- `floooh/sokol-tools` `0c591c3` (clone at `~/projects/sokol-tools`): `docs/sokol-shdc.md` "GLSL uniform
  blocks and C structs" and "Storage buffer content restrictions".
- Heaps HXSL: [docs/HEAPS.md](../../docs/HEAPS.md).
