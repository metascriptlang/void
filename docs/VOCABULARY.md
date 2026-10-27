# Void's vocabulary — which reference names what

Decided with the person on 2026-10-13. Void reads four references, and each owns one layer, so two of
them never settle the same question. An app author is a TypeScript developer: where a name reaches
them, it is the name TypeGPU and WebGPU already taught them.

| Layer | Owner | What it decides |
|---|---|---|
| Platform | sokol_gfx + sokol-shdc | the GLSL 450 dialect, separate textures and samplers, uniform block types, what a backend can do |
| Engine model: `src/void3d`, `src/void2d` | Heaps, with Bevy beside it | scene, material, pass, renderer, camera, light, how shaders compose into programs, and their names |
| Author vocabulary: `src/shader` | TypeGPU, which is WebGPU's | type names, shader std names, entry shape |
| Shader mechanism | shady | a macro reads the typed body, gathers callees, the CPU runs the same function; no author sees it |

**When two disagree, the higher row wins**: platform, then engine model, then vocabulary, then
mechanism. A concept TypeGPU has and a row above forbids is left out, not adapted.

**Clear to the author comes before matching TypeGPU.** TypeGPU is where a familiar name is looked
for first, not a spec to conform to: its name is taken when it maps one to one and reads plainly in
MetaScript, and Void keeps or picks its own when that says more directly what the thing does. A
signature states what the platform needs even where TypeGPU's does not.

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
| fetch / size | `tex.fetch(p)`, `tex.size()` | `textureLoad`, `textureDimensions` | one to one, without a sampler as WGSL's; the size is signed (below) |
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

One exception, the person's on 2026-10-13: `textureDimensions` returns `Vec2i` where WGSL returns
`vec2u`. The value is the same; the texel coordinate it bounds is signed (`textureLoad` takes
`Vec2i`), so the unsigned type only bought a cast at every use. It also keeps the emitted GLSL
the hand-written expression, `textureSize(…)` with no conversion around it.

Where MetaScript's convention and TypeGPU's spelling differ, MetaScript's holds for the type name
and TypeGPU's for the constructor: `Vec4f` the struct, `vec4f(…)` the function.

Where WGSL has no name for what a shader needs, Void names it and takes no WGSL name for it:
`upperLeft3x3(m)` is GLSL's `mat3(m4)`, which WGSL has no constructor for. Where WGSL leaves a
result undefined, the CPU meaning refuses that operand instead of returning a plausible number:
`pow` of a negative base, or of 0 to a power ≤ 0, stops with `unreachable`.

Decided 2026-10-15 when `std.ms` grew to what shady's tests and examples use (shady `c899f7c`
`tests/test_shady.nim`, `examples/{circle,colors,flare,mandelbrot}.nim`):

- **The remainder is `%`, WGSL's truncated `x - y * trunc(x / y)`**, emitted as that expression;
  MetaScript's own `%` computes it on the CPU. Void takes no `mod`. TypeGPU's `mod` is this `%`
  (`std/operators.ts`), but HXSL's, GLSL's and shady's floor (`shared.nim` `fmod` is
  `x - y * floor(x / y)`, and its test holds `fmod(-0.5, 1.0) == 0.5`), so the name carries two
  results to the readers Void has. A port of shady's `fmod` writes `x - y * floor(x / y)`.
- **`inverse` takes GLSL's name**: WGSL and TypeGPU have no matrix inverse, so, as with
  `upperLeft3x3`, the name is Void's to give, and GLSL's is the one shady's test calls
  (HXSL has none either, `hxsl/Ast.hx` `TGlobal`).
- **Spelled apart**: `round` is `roundEven` (GLSL's `round` leaves a tie to the implementation),
  `atan2(y, x)` is `atan(y, x)`, `inverseSqrt` `inversesqrt`, `faceForward` `faceforward`,
  `saturate(x)` `clamp(x, 0.0, 1.0)`, `dpdx` `dFdx`, `dpdy` `dFdy`.
- **Refused where GLSL or Metal leave undefined what WGSL defines**, since the emitted program
  cannot promise WGSL's result there: `clamp` with low > high, `smoothstep` with low ≥ high. And
  where WGSL itself leaves it undefined: `sqrt` below 0, `inverseSqrt`, `log` and `log2` at or
  below 0, `asin` and `acos` past ±1, `atan2(0, 0)`, `normalize` of a zero vector, `inverse` of a
  singular matrix, a float outside the int32 range into an int vector.
- **Swizzles: every one WGSL spells on a float vector** (2 to 4 of `xyzw`, or of `rgba`, and the
  single `r` `g` `b` `a`), **and `xy`, `xyz` on an integer vector**. Each is a getter `msc` checks in
  every program that imports `std.ms`. Measured 2026-10-15 on BUILD `a2b3e36a`, base tree
  `70081fc2`, `msc check --time src/void3d/shader3d.ms` with the machine at 13% CPU, two runs
  each: 0.37 s at the base, 0.41 s with the new builtins and the old swizzles, 0.80 s with
  this set, 2.36 s with every swizzle on all nine vector types. Integer vectors are indexed
  and converted more than swizzled, so their full set was not worth 1.5 s on each compile.

Added 2026-10-18 for void2d's sRGB conversion, which the hand-written stage wrote as
`mix(hi, lo, lessThanEqual(c, k))`:

- **A comparison per component is TypeGPU's `le(a, b)`**, returning `Vec3b` (WGSL's `vec3<bool>`),
  and `select(f, t, cond)` takes it as WGSL's does; they emit as `lessThanEqual` and
  `mix(f, t, cond)`. Since 2026-10-26 every vector width has `eq`/`ne`/`lt`/`le`/`gt`/`ge`,
  `any`/`all`/`not` and `select`, over `Vec2b`–`Vec4b`.
- **`&` on integers** is WGSL's and C's bitwise and, so `(floor(x) as int32) & 3` is the floored
  remainder by 4 for a negative `x` too.

A shader's interface uses WGSL's attribute names as MetaScript field decorators: `@builtin(…)`,
`@location(n)` and `@binding(n)`. Two come from WebGPU's bind group layout, where a texture or
sampler states its binding type: `@sampleType(unfilterable_float)`, `@samplerType(nonfiltering)`.
One is Void's, the program key: `@feature(CUTOUT)` marks a boolean as the feature of that name,
read only as an `if` condition. That is Heaps' `@const` (one program per value) in the place
TypeGPU's slots take, since Void builds its variants offline by key.

## GPU layer

`src/gpu` and `src/sokol` keep the names of the references they port, so a port reads one to one
against its source. Resources and passes use sokol's names (`makePipeline`, `applyBindings`, `beginPass`, `commit`,
`LoadAction`). Render state uses Heaps' names: `RenderState` is `h3d.mat.Pass` (`culling`, `depthTest`, `depthWrite`), and
`Face`, `Compare`, `Blend` and `Wrap` are `h3d.mat.Data`'s. No app imports this layer directly: Neon, Lightcube and
Terminator reach it through void2d and void3d. So a WebGPU name here would teach no author anything, while
every lookup in sokol or Heaps would need a translation. The person decided this on 2026-10-21, replacing the WebGPU rename
planned on 2026-10-13.
