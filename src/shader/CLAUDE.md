# src/shader — shaders written in MetaScript

**Goal.** A shader is an ordinary MetaScript function. A macro reads its typed body and lowers it into
the shader IR, which this module prints for every backend. The same function runs on the CPU as a
logic oracle in the native gate. Shader-tier context: [docs/SHADER.md](../../docs/SHADER.md) Tier 3;
what the IR fixes before its printers: [docs/SHADER-IR.md](../../docs/SHADER-IR.md).

**Why now.** void3d hand-writes one program per feature combination (`Program` in `src/void3d/gpu3d.ms`),
and `ProgramMap` packs at most 24 of them. void3d's feature-bit ProgramKey keys the variants, and this module
later replaces the hand-written GLSL source of each base.

## Design

- **Macro → IR → one printer per target** (the person's decision 2026-10-23: Void stops using
  sokol-shdc). The `glsl` macro family lowers the typed body into the shader IR of `ir.ms`, plain
  data with no `Node`: a Heaps-style typed expression tree (`hxsl/Ast.hx` `TExprDef`) over
  Mach-style resolved globals (`sysgpu/shader/Air.zig` `Inst.Var` with binding, group, access;
  `Builtin`, `Interpolate`, `TextureType`). Printers write GLSL 450 (today's text, the regression
  oracle), GLSL 430, GLSL ES 300, HLSL SM5, WGSL and MSL from it, one file each, as Mach's
  `codegen/*.zig`. Slots and uniform buffer layout are fixed on the IR before any printer, and that
  pass produces the `GPUShaderModuleDescriptor` reflection (Heaps `Flatten`). A program key is a
  `FeatureCondition` over feature names; per key, the IR is specialized and its unread declarations
  dropped (Heaps `Eval` + `Dce`). Own backends, once rejected because shdc wrote every target, are
  chosen because sokol is being replaced ([docs/GPU.md](../../docs/GPU.md)). sokol-shdc is on no
  build or regeneration path. Its reflection matched the committed modules on all three while
  fetches still took a sampler (2026-10-23, BUILD `4b5816aea`); it refuses every stage that
  fetches without one (see "No fetch without a sampler" below), so the goldens replaced it as the
  oracle.
  `irErrors` names each broken invariant; `src/test/shaderIrCheck.ms` builds modules by hand, also
  inside a macro.
- **Emitter = macro library, not a compiler backend.** On msc `244ef48c`, `getImpl(bindSym("frag"))`
  inside a macro returned the `FunctionDecl` with checker types on every expression (`typeKind` Float32
  on `uv.x * t`).
- **The emitter enforces the shdc dialect at the MetaScript source**, so the error points at the
  author's code: textures and samplers are separate; uniform block members are only float, int,
  vec2–4, ivec2–4, every matrix shape, and arrays only vec4, ivec4 or mat4; no recursion. A two-row
  matrix keeps WGSL's 8-byte column stride on every target, printed as vec2 columns where std140
  would stride 16. The emitter packs an
  author's struct into those types, so a uniform block's layout comes from one MetaScript struct.
- **Vocabulary is TypeGPU's** ([docs/VOCABULARY.md](../../docs/VOCABULARY.md)): `Vec3f`/`vec3f`,
  `Mat4x4f`, `textureLoad`, `select`, `@builtin(position)`, `@binding(n)`. `std.ms` declares it with
  CPU meaning; the emitter spells each declaration in GLSL, and a `std.ms` name without a GLSL
  spelling is an error, not a guess.
- **Entry convention** (TypeGPU's `vertexFn`/`fragmentFn`; approved 2026-10-13, it replaces the
  shady `out` parameter of 2026-10-10). An entry writes to nothing it was handed, so the CPU call is
  the GPU call. Its stage follows from its return: a struct with a `@builtin(position)` field is a
  vertex entry, anything else a fragment entry. Each parameter is one of three structs, at most one
  of each:
  - **the stage input**: vertex attributes, or a fragment's varyings and builtins
    (`@builtin(position)` reads `gl_FragCoord`, `@builtin(frontFacing)` `gl_FrontFacing`); a field
    marked `@feature(NORMAL_MAP)` exists only in that feature's programs, as `tangent` does;
  - **the bindings** (WGSL's `@binding(n)` on each field): a struct field is a uniform block named
    as the field, its members the struct's fields, so the C struct shdc writes keeps that name; a
    `Texture2d` or `Sampler` field is a separate texture or sampler, with `@sampleType(...)` or
    `@samplerType(...)` when WebGPU's layout needs one. Blocks at one `@binding` are the layouts a
    program key chooses between (`materialParams`, `movingMaterialParams`, …, all at 3) and may
    share member names; a reader picks one under the key's conditions (`materialOf`);
  - **the program key**: a struct whose every field is a boolean marked `@feature(CUTOUT)`, read
    only in an `if` condition, alone or joined by `!`, `&&` and `||`; it emits `#ifdef CUTOUT` or
    `#if defined(A) || defined(B)`, so one function serves every row of
    `src/void3d/programKeys.txt` (Heaps' `@const`).
  The return is the stage output: a fragment's vector is `fragColor`; a struct names each output
  `@location(n)`, and `@feature(NAME)` declares one only under that feature; `void` writes none.
  `discard()` is WGSL's. The stage and program name are the generator's (`@fs litFs`).
- **Each declaration sits under the conditions its reads run under, and an unread one is left
  out.** A uniform or texture a variant does not read is still one its draw would have to bind, and
  shdc would reflect it. The condition is the `||` of every distinct context a read runs in,
  reduced the way a reader would write it: a context another one covers is dropped, two that
  differ only in `F` and `!F` join, and a condition true under every feature set leaves the
  declaration bare. A helper is written once with no features on; its reads are replayed at each call under the
  features around the call, and the helper itself is gated the same way. A `@feature(F)` input
  exists only in F's programs, so a read of it runs under a condition whose `&&` includes F; any
  other read is refused at the read, or at the entry's call that reaches a helper's read, naming
  the field and F. Before, shdc found it at regeneration as an undeclared name.
- **Varyings match by position, so a fragment names its vertex entry** (TypeGPU's pipeline pairs
  `withVertex` and `withFragment` the same way). shdc numbers varyings in declaration order, so
  every one is declared, read or not. `glslLinked(litFs, litVs)` checks the fragment input's
  non-builtin fields against the vertex output's, by name, type and order, and fails at the
  fragment naming the first difference; `glsl` refuses a fragment that reads varyings. Measured
  2026-10-15 (BUILD `a2b3e36a`, probes `out/linkProbe/`): a swapped pair, a changed type and an
  unlinked fragment are each refused with that message. `glsl` and `glslLinked` expand to
  `glslStage`, which emits the stage.
- **Errors point at the author's node**, not at the `glsl(...)` call: a body error at its
  expression, an interface field at its first decorator (the type nodes `getType` returns sit at
  the expansion site), a field with none and a signature error at the entry's declaration. Only
  what is wired at the call stays there: `glsl` on a fragment that reads varyings, `glslLinked`'s
  pairing, `glslCompute`'s size, a compute entry passed to `glsl`. The file shown is the expansion
  site's, so a shader in another module prints its line under the caller's file
  (`~/metascript/.inbox/compiler/2026-10-16-macro-error-loses-node-file.md`). Measured 2026-10-16,
  BUILD `fd03df3e`: the `tests/refusals/` loop of `scripts/gate.sh` (each file's first line the
  expected `line:col` and message) passes 13 of 13 on this emitter, 1 of 13 (the control that must
  pass) on the emitter of tree `8f8ab730`.
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
- **Statements keep MetaScript's meaning.** A MetaScript `switch` never falls through (a case body
  that reaches its end does not compile), so each case is a braced GLSL case ending in `break`. A
  statement `match` on an integer is the same switch, an or-pattern one case's labels, `_` its
  `default`; a `break` in a match arm leaves the loop around the match, where GLSL's would leave only
  the switch, so it is refused, as is a `when` guard. Stacked labels (`case 1: case 2:`) are one case,
  in msc as in TypeScript, and one GLSL case.
  `%` is emitted for uint32 operands only, where C, JS and GLSL truncate alike.
- **Integer overflow keeps the language's meaning on the CPU.** WGSL wraps i32 and u32; on the CPU a
  uint32 wraps the same (a PCG-style hash gives the GPU's bits), and an int32 overflow traps, as
  every MetaScript int32 does (measured 2026-10-16, BUILD `5631dd3e5`, `out/wrapProbe/`: `x *
  747796405 + 2891336453` on uint32 prints `3719402245`; `65536 * 65536` on int32 panics "signed
  integer overflow"). So the oracle refuses an int32 shader that relies on wrap, where the GPU would
  return the wrapped value; write hashes and bit mixing in uint32. Only `std.ms`'s own `abs` of the
  least int32 returns it unnegated, as WGSL's does. `as uint32` takes a non-negative literal
  (`6u`); any other int32 converts by its bits through `vec2u`.
- **An author struct is a GLSL struct**, declared once before its first reader under the naming
  rule; an object literal is its constructor in field order. A field named as a GLSL word gets a
  suffix, where TypeGPU refuses the key: TypeGPU's struct is also the host's buffer layout, and a
  value struct here never reaches the interface. A struct is no attribute, varying or block member,
  and holds no texture or sampler. An integer varying is `flat` on both sides (glslang refuses it
  otherwise). An attribute, varying or fragment output is no array, refused at the field and by
  `irErrors`: WGSL's user-defined IO is a numeric scalar or vector (TypeGPU's `BaseIOData`,
  `packages/typegpu/src/core/function/fnTypes.ts:58`; naga refuses an array at `@location`, "Only
  numeric scalars and vectors are allowed"), and GLSL ES 3.00 declares no array vertex input
  (SPIRV-Cross "OpenGL ES doesn't support array input variables in vertex shader"). naga's GLSL
  front end splits an array input into one location per element; WGSL has no such source to
  accept, so the author declares one field each (2026-10-23, BUILD `4b5816aea`).
- **Generated modules live on disk.** `tools/irPrograms.ms` lowers every stage while it compiles,
  specializes it per program (the rows of `src/void3d/programKeys.txt`, its `VOID2D_PROGRAMS` and
  `GPU_COPY_PROGRAMS`) and prints each target; `scripts/regen-shaders.sh` writes the results to
  `src/void3d/programModules.ms`, `src/void2d/shader2dModules.ms` and
  `tests/integration/gpuCopyModules.ms`, and `src/void2d/shader2dSlots.h` from the void2d stages'
  GLSL 450, with each HLSL stage's DXBC from `src/shader/dxbc/` (docs/SHADER-IR.md "The DXBC
  cache"); `--check` reports a stale file. The tool refuses a row whose stages never read one of
  its features, rows of one layout that read different attribute slots, a block shared by name
  with two sizes or slots, and an emissive dissolve block that is not the caster's block and then
  `emissive` (`src/void3d/draw.ms` `applyBlockHead`); each refusal was run by breaking its input
  (2026-10-23). No derivative runs on the CPU, so a fragment that takes `dpdx`
  (void2d's `fs` and `uiFs`) is checked through its helpers and pixel goldens, not as a whole. Runtime modules never
  call `glsl`, so no binary carries GLSL text.
- **An app's own program is built while msc compiles it** (`shaderProgram` in `program.ms`, the
  person's "viết → chạy", 2026-10-18). The statement splices one declaration, `const <name>:
  int32`, initialized by `shaderBuild`: in the macro VM it joins the two lowered stages
  (`programModule`), prints and reflects them for the build's target (`programSource`), and
  returns a call of `shaderProgramRegister` on two literals, the target's
  `GPUShaderModuleDescriptor` (built as `shaderModule` builds it) and a one-buffer `DoorLayout`,
  which registers them through `doorRegisterLayouts` and `doorRegisterPrograms` of
  `src/gpu/doorGpu.ms`; no C, no `@emit`, no file written.
  Attribute locations come from the `glsl430` reflection, matched by field name. Printing runs in
  the macro, not ahead of time into a generated module, by measurement (2026-10-23, BUILD
  `4b5816aea`, Windows, `msc check src/test/shaderProgramCheck.ms` against a copy without its two
  programs): the two IR programs cost 1.9 s of compile, where sokol-shdc's cost 1.6 s; one
  program written ahead of time by `msc run` of a generator costs 5.6 to 7.3 s and a step the
  author runs. A module only a macro reaches stays out of the binary only while its top level
  runs nothing: a module `const` initialized by an array literal or a call is module init, which
  every program runs, so the printers' reserved-word tables are built per printer
  (`Printer.reserved`). With them at module level, `forwardOutlineReference.exe` (`--release`)
  was 759,808 B and the printers were emitted as C; with them per printer it is 701,440 B and no
  printer module is emitted (2026-10-24, BUILD `4b5816aea`). Its
  limits, each refused or stated: one program, so no `@feature` field in either entry
  (`tests/refusals/programFeature.ms`); one per-vertex buffer, attributes packed in declaration
  order with no padding, `@builtin` inputs skipped; `float32` and its `./std` vectors only, since
  `GPUVertexFormat` has no integer format (an `int32` or `uint32` field is refused at the statement,
  `tests/refusals/programIntAttribute.ms`). A
  fragment without an input links to a vertex entry that writes no varyings. A program the IR
  refuses stops the compile at the program's name, never skips it: the reason follows
  "shaderProgram '<name>': " (`tests/refusals/programBindingRange.ms`, a block at `@binding(9)`).
  `src/test/shaderProgramCheck.ms` reads the registered layout and masks back through
  `src/gpu/door.ms`. Its first consumer, `tests/integration/forwardOutlineReference.ms`, builds
  on the door path (2026-10-22, BUILD `afcd22f19`) and has not been drawn since; on the C path it
  passed D3D11 `forwardOutline` at framebuffer factor 1 and 2, 33 of 33 reference comparisons,
  and `scripts/web3d.sh` 27 of 27 on WebGL2 (2026-10-18, BUILD `4fe2a5eec`).
- **A helper call costs a copy of each argument.** glslang passes every argument through a
  variable, and SPIRV-Cross prints it at each call (`highp vec4 param_1 = ui_params[1];`), where
  a GLSL builtin or code at the call site costs none. Neither shady nor TypeGPU inlines, so the
  emitter keeps a helper a function. void2d's shader text counts against the default-layer size
  budget (`tests/bench/wasm.json` "delta"), so its vertex entries compute the clip distance where
  they use it, as the hand-written stages did. Measured 2026-10-18 against the hand-written
  stages: the port first grew the text by 2438 B (GLSL ES) and 1150 B (HLSL), past the budget.
- **CPU oracle within a tolerance, never pixel-exact.** GLSL allows contraction and looser ULP bounds,
  and `sin`/`exp` are implementation-defined. shady's own tests use `1e-4`. Pixel truth is
  the readback in `tests/capture3d/capture3d.c`.

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
- **A struct type names its module.** `getType` and `getTypeImpl` of a struct give a `TypeObject`
  whose `resolvedSym.modulePath` is the declaring module, so `isAuthorStruct` tells a `./std` struct
  from the author's by that path, and an author struct named like a `./std` type stays the author's
  (pinned in `shaderStatementCheck.ms`; BUILD `5631dd3e5`). An enum type node still carries no
  `resolvedSym`.
- **A macro declares module names through `SpliceMany`** (measured 2026-10-18, BUILD `4fe2a5eec`,
  `shaderProgram`). A bare macro statement returning `NodeKind.SpliceMany` with `spliceNodes`
  declares each node at module level; a `BlockStmt` scopes them instead, and a `quote` cannot
  splice a declaration's name (`const ${x}: T` does not parse), so the nodes are built by hand.
  `@emit("/*INCLUDESECTION*/#include …")` lands in the C headers section. Arguments arrive
  expanded, and only a nested macro sees an entry typed: `getType` on the identifier passed to
  the statement macro is "node has no type", so `vertexFormats` reads the signatures.
  `bindSym` resolves only a literal string (a variable gives null). Macros run at compile time
  with `std/fs` and `std/process` (`execFileResult`, `platform` "windows"/"darwin"/"linux").
- **A negated literal is a `UnaryExpr`.** Since BUILD `5631dd3e5` `-0.5` reaches the emitter as `-`
  over a `NumberLiteral`, as TypeScript parses it; the emitter writes it as one literal, `-0.5`, and
  parenthesizes only a negation of a negation, so `- -x` never becomes GLSL's `--`.

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
  with build_dummy_sampler_for_combined_images()` (again 2026-10-23, win32 shdc, on hlsl5, wgsl
  and metal_macos too). `textureLoad` and `textureDimensions` take no sampler, as WGSL's, so
  printGlsl450 writes them through that extension and only the IR printers compile them. On GL
  `bindingSlots` pairs the fetched texture with a sampler its stage already samples it through,
  else with `DUMMY_SAMPLER`, which the GL backend binds itself.
- **Walls neither shdc nor self-emitting can pass**: sokol API (spec constants compile, but sokol has
  no field for them, so the default always wins; push constants; framebuffer fetch degrades to a
  texture read; bindless; indirect) and platform floors (WebGL2, WebGPU core, D3D11 SM5).
- **The std builtins compile on all five** (measured 2026-10-15, BUILD `a2b3e36a`, probe
  `out/stdProbe/probe.glsl` from `mathProbeFs` and `shapeProbeFs` in `src/test/shaderStdCheck.ms`):
  `inverse` of mat3 and mat4 reaches HLSL, MSL and WGSL as SPIRV-Cross's `spvInverse3x3` and
  `spvInverse4x4` helpers; `fma`, `roundEven`, `trunc`, `dFdx`, `fwidth` and `uvec`/`ivec`
  conversions pass on `glsl300es` too.
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

## Measured — the lit family generated

2026-10-15, BUILD `cf18cd1d`, HEAD `90833c08`, Windows x64, one quiet GPU window (`shader-lit-gate-3`;
receipt in `out/shaderLit3/`). `litVs`, `litFs` and `shadowLitFs` are generated for all 14 program
rows that use them and their hand-written GLSL is gone. The emitted text differs from the deleted
GLSL (parentheses, renamed locals, helpers in call order), so the programs were judged by image:

- **D3D11**: `GATE_SKIP_ANDROID=1 GATE_SKIP_BENCH=1 GATE_SKIP_CHURN=1 sh scripts/gate3d.sh` exit 0,
  369 PASS, 0 FAIL, the six known skips; all 24 capture rows byte-identical to
  `docs/baselines3d.sha256`.
- **WebGL2**: `scripts/web3d.sh` with `forwardOutline` taken out of a scratch copy, 18 of 18 runs.
  `forwardOutline` does not link for the web on main either (`tests/integration/forwardOutline.ms`
  imports `std/fs`, whose natives are C-only); not shader evidence either way.
- **WebGPU**: the `wgpu` build of `tests/integration/dirShadow.ms` passes; no capture exists for it.
- **Uniform layout**: `programTable.h`'s `_Static_assert`s compare every generated block with the
  hand-written programs that share it; a deliberate `pointColor: Vec4f[3]` fails them.
- Not run: GLES3 on a device, Metal.

## Measured — the textured families generated

2026-10-15, BUILD `a2b3e36a`, HEAD `725f7d15`, one quiet GPU window (`shader-tex-gate-1`, receipts in
`out/shaderTex/`). `litTexturedVs`, `litTexturedFs`, `unlitTexturedVs`, `unlitTexturedFs`,
`shadowLitTexturedFs` and `shadowUnlitTexturedFs` are generated for every core and shadow row that
uses them, and their GLSL is gone; the lit family's text changed with them (its helpers take
values now). gate3d 369 PASS / 0 FAIL / the six known skips, all 24 capture rows byte-identical;
`scripts/web3d.sh` 20 of 20 with forwardOutline. A native build compiles `programTable.h`'s
layout asserts, the emissive-dissolve block-head assert among them.

## Measured — coverage against shady

2026-10-15, BUILD `a2b3e36a`. Every case of `~/projects/shady/tests/test_shady.nim` and the
shader-toy and compute examples (`circle`, `colors`, `flare`, `mandelbrot`, `compute1`) is written
as a Void stage in `src/test/shadyTestsCheck.ms`, `shadyExamplesCheck.ms` and `shaderComputeCheck.ms`:
its GLSL pinned, run on the CPU where it computes something, and the 14 programs plus the compute
one compiled by sokol-shdc to `glsl430:glsl300es:hlsl5:metal_macos:wgsl` (compute without
`glsl300es`, which has none). Since 2026-10-23 (BUILD `4b5816aea`) `src/test/shadyPortsCheck.ms`
prints the 19 programs and compute1 through `descriptor.ms` on every target into
`out/shadyPrograms/`: fxc accepts 39 HLSL stages, naga 39 WGSL and 77 GLSL 430 / ES 300 stages
(rewritten to Vulkan 450 for its front end); GLSL ES 3.00 refuses compute1 for its storage
resources. Where a case is written differently:

| shady | Void |
|---|---|
| `var` output parameters, `gl_FragColor.x = …` | the returned colour or output struct |
| `Uniform[T]` parameter | a field of the bindings struct's uniform block |
| `SamplerBuffer` + `texelFetch`, `ImageBuffer` + `imageStore` | a storage buffer of structs, a storage texture and `textureStore` (shdc has no buffer textures) |
| `fmod` (GLSL's floored `mod`) | `x - y * floor(x / y)`; Void's `%` is WGSL's truncated one |
| `c[i] = …` on a vector | a component write (`c.x = …`) per index |
| `array[2, uint16]` vertex attribute | refused: neither WGSL nor GLSL ES 3.00 takes an array vertex input |
| `gl_VertexID mod 2`, `div 2` | `@builtin(vertexIndex)` (uint32) with uint `%` and `/` |
| `USampler2d`, `Sampler2dArray` | `Texture2dU32`, `Texture2dArray` (WGSL's `texture_2d<u32>`, `texture_2d_array`) |
| a varying named as an attribute (`color` in, `color` out) | renamed on both sides (`color_1`), `glslLinked` passing the vertex entry |
| GLSL 4.10 / 3.30 / ES 3.0, HLSL, MSL backends | one IR, printed as GLSL 430, GLSL ES 300, HLSL SM5, MSL and WGSL |

## Rejected

- **A GLSL backend inside msc** (docs/SHADER.md Tier 3's first plan). The macro already reads the
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
