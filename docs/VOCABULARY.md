# Void's vocabulary — which reference names what

Decided with the person on 2026-10-13. Void reads four references, and each owns one layer, so two of
them never settle the same question. An app author is a TypeScript developer: where a name reaches
them, it is the name TypeGPU and WebGPU already taught them.

| Layer | Owner | What it decides |
|---|---|---|
| Platform | sokol_gfx + sokol-shdc | the GLSL 450 dialect, separate textures and samplers, uniform block types, what a backend can do |
| Engine model: `src/void3d`, `src/void2d` | Heaps, with Bevy beside it | scene, material, pass, renderer, camera, light, how shaders compose into programs, and their names |
| Author vocabulary: `src/shader`, then `src/gpu` and `src/sokol` | TypeGPU, which is WebGPU's | type names, shader std names, entry shape, GPU resource and state names |
| Shader mechanism | shady | a macro reads the typed body, gathers callees, the CPU runs the same function; no author sees it |

**When two disagree, the higher row wins**: platform, then engine model, then vocabulary, then
mechanism. A concept TypeGPU has and a row above forbids is left out, not adapted.

**Clear to the author comes before matching TypeGPU.** TypeGPU is where a familiar name is looked
for first, not a spec to conform to: its name is taken when it maps one to one and reads plainly in
MetaScript, and Void keeps or picks its own when that says more directly what the thing does. A
signature states what the platform needs (a fetch here takes its sampler) even where TypeGPU's does
not.

## Why not one reference

- **TypeGPU has no engine.** Its vocabulary stops at `root`, buffers, textures, samplers, bind
  groups, pipelines, vertex layouts, slots and shader functions
  (`apps/typegpu-docs/src/content/docs/apis/`). Nothing in it names a scene, a material, a camera, a
  light or a render phase, so void3d and void2d have nothing to migrate to.
- **Heaps has no name a TypeScript developer knows** below the engine: its GPU layer is `h3d.impl`
  drivers, and HXSL spells types and builtins the GLSL way.
- **Left out of TypeGPU, by the rows above it**: `root` and the runtime schema (`d.struct`, WGSL
  generated while the app runs), because Void generates offline and a MetaScript `struct` is already
  the schema; bind groups, because sokol binds by slot per stage and has none.

## Shader surface — HXSL beside TypeGPU

Heaps `b9aa6dcb` (`~/projects/heaps`): `hxsl/Ast.hx` (`Type`, `TGlobal`, `VarKind`), `hxsl/Checker.hx`
(the `get`/`fetch`/`size` texture methods), `h3d/shader/BaseMesh.hx`, `h3d/shader/Texture.hx`.
TypeGPU `1f9d89d`, typegpu 0.12.7 (`~/projects/TypeGPU`): `packages/typegpu/src/data/index.ts`,
`std/index.ts`, `builtin.ts`, docs `apis/functions/index.mdx`. What Void declares today is
`src/shader/std.ms`; the rows below are the map, not the inventory.

| Concept | HXSL | TypeGPU | Maps |
|---|---|---|---|
| float vector | `Vec2` `Vec3` `Vec4` | `vec2f` `vec3f` `vec4f` | one to one |
| int / uint vector | `IVec2`…; unsigned has none | `vec2i`… / `vec2u`… | one to one; TypeGPU is wider |
| matrix | `Mat3` `Mat4` `Mat3x4` | `mat3x3f` `mat4x4f` | one to one, except `Mat3x4` |
| scalar | `Float` `Int` `Bool` | `f32` `i32` `u32` `bool` | MetaScript's own `float32` `int32` `uint32` `boolean` |
| vertex attributes | `@input var input : { … }` | `vertexFn({ in: { … } })` | one to one |
| varyings | `@var`, shared by name | vertex `out` and fragment `in`, matched by name | one to one |
| stage outputs | `output.position`, `output.color` | `d.builtin.position` in `out`; the fragment's return value | one to one |
| builtin inputs | globals `FragCoord`, `VertexID`, `InstanceID`, `FrontFacing` | `d.builtin.position`, `vertexIndex`, `instanceIndex`, `frontFacing` in `in` | one to one |
| per-material value | `@param` | a uniform | one to one |
| per-frame value | `@global` | a uniform shared across draws | one to one |
| compile-time switch | `@const`, one program per value | `tgpu.slot`, filled when the shader is resolved | same idea; Void's is the program key (`src/void3d/programKeys.txt`) |
| sample | `tex.get(uv)`, texture and sampler in one `Sampler2D` | `textureSample(texture, sampler, uv)` | TypeGPU's, which is also shdc's separate pair |
| fetch / size | `tex.fetch(p)`, `tex.size()` | `textureLoad`, `textureDimensions` | one to one; Void's take a sampler (`src/shader/CLAUDE.md`) |
| math | `mix` `clamp` `saturate` `smoothstep` `normalize` `dot` `cross` | the same names | one to one |
| math, renamed | `dFdx` `dFdy` `inversesqrt` | `dpdx` `dpdy` `inverseSqrt` | TypeGPU's name |
| remainder | `mod`, emitted as GLSL `mod`: floored | `mod`, emitted as `%`: truncated (`std/operators.ts` `mod`) | **same name, two results** for a negative operand |
| composing shaders | fragments linked through shared variables (`pixelColor`, `calculatedUV`), `__init__` ordered by dependency | function calls and slots | **no map**: the engine model's, so Heaps' and Bevy's |

**A name brings its meaning.** A function declared under a WGSL name computes what WGSL defines for
it, on the CPU and in the emitted GLSL, or the name is not taken: a `mod` spelled as GLSL `mod` would
answer differently from the `mod` a WebGPU developer knows. Each builtin whose GLSL spelling differs
gets a CPU oracle case at the operand where the two definitions part (a negative operand, a tie).
TypeGPU states the CPU meaning of every std function as the `normalImpl` beside its `codegenImpl`
(`std/numeric.ts`, `std/texture.ts`), which is the reference when `src/shader/std.ms` grows. Where
TypeGPU's spelling and the WGSL specification differ, the specification is the anchor: TypeGPU is
before 1.0.

Where MetaScript's convention and TypeGPU's spelling differ, MetaScript's holds for the type name
and TypeGPU's for the constructor: `Vec4f` the struct, `vec4f(…)` the function.

## GPU layer

`src/gpu` and `src/sokol` take WebGPU's names where a concept maps one to one and the name is the
clearer one: resource creation
(`createTexture`, `createSampler`, `createRenderPipeline`), attachment load and store
(`loadOp`, `storeOp`), render state (`cullMode`, `depthCompare`, `blend`), `vertexLayout`. Until that rename lands the layer keeps the names it has; the engine layers above it
keep theirs for good.
