# Particles research: rendering, trails, and the shady GPU path

Lane 3 of the particles research. Scope: (A) the Unity Renderer, Texture Sheet Animation, Lights,
Trails and custom-vertex-stream surface mapped onto void2d and void3d; (B) what Void's shader
module (`src/shader`, "shady") can carry today, and which GPU tiers it makes possible under the
WebGL2 floor. Simulation layout, sorting algorithm and upload policy are the runtime report's
([PARTICLES-RUNTIME.md](PARTICLES-RUNTIME.md), read first, not redone); the authoring model is
[PARTICLES-AUTHORING.md](PARTICLES-AUTHORING.md) (read in its state on 2026-10-22: Unity module
vocabulary, `MinMaxCurve`/`MinMaxGradient`, Unity's velocity model, one model for 2D and 3D).

Read-only research on 2026-10-22. Every claim cites `file:line` at the stated commit. "est."
marks a number reasoned, not measured; "(mem)" marks a fact from memory of a manual, not read
this session; "verify" marks a platform behaviour that needs a probe before it is relied on.

Pins and short names:
- Void particles worktree `C:/Users/metacraft/metascript/void-wt-void2d-particles` @ `3aa1ef19`
  (paths below are relative to it unless absolute). void3d's Trail port: branch `wt/void3d-m5`
  @ `a645db6f`, `src/void3d/trail.ms` (read with `git show`), cited `trail.ms:N`.
- Unity C# reference `~/projects/UnityCsReference` @ `bf60283`: `PSE:N` =
  `Modules/ParticleSystem/Managed/ParticleSystemEnums.cs`, `PSR:N` =
  `Modules/ParticleSystem/ScriptBindings/ParticleSystemRenderer.bindings.cs`, `PSM:N` =
  `Modules/ParticleSystem/ScriptBindings/ParticleSystemModules.bindings.cs`. Unity's simulation
  and its particle shaders (`Particles/Standard Unlit`) are native or built-in and not in the
  reference: what they do is (mem).
- Heaps `~/projects/heaps` @ `b9aa6dcb`: `HT:N` = `h3d/scene/Trail.hx`, `HP:N` =
  `h3d/parts/Particles.hx`, `HG:N` = `h3d/parts/GpuParticles.hx`, `HGS:N` =
  `h3d/shader/GpuParticle.hx`, `HPS:N` = `h3d/shader/ParticleShader.hx`.
- Godot `~/projects/godot` @ `876b290` (4.5-stable): `GC:N` =
  `servers/rendering/renderer_rd/shaders/particles_copy.glsl`, `GS:N` =
  `servers/rendering/renderer_rd/storage_rd/particles_storage.cpp`, `GM:N` =
  `scene/resources/material.cpp`, `GP3:N` = `scene/3d/cpu_particles_3d.cpp`.
- bevy_hanabi `~/projects/bevy_hanabi` @ `77630ff`: `HR:N` = `src/render/vfx_render.wesl`,
  `HM:N` = `src/render/mod.rs`, `HO:N` = `src/modifier/output.rs`.
- three.js `~/projects/three.js` @ `d4ea9b9` (sparse checkout, read with `git show`):
  `GPUComputationRenderer.js`, `WebGLBackend.js`, `LineSegmentsGeometry.js`, `LineGeometry.js`,
  `SoftParticles.js`. three.js is not one of Void's four vocabulary layers (docs/VOCABULARY.md:7-12);
  it is cited only as prior art where none of Heaps, Bevy/hanabi or Godot has the mechanism.
- sokol: `deps/sokol/sokol_gfx.h` in the worktree, cited `SG:N`.
- Mesh particles (§A.2.1) add: Heaps `HMB:N` = `h3d/scene/MeshBatch.hx`, `HIB:N` =
  `h3d/impl/InstanceBuffer.hx`, `HC:N` = `hxsl/Cache.hx`, `HFB:N` = `hxd/FloatBufferLoader.hx`;
  Bevy `~/projects/bevy` @ `84e2d2c` (examples read with `git show`): `BI:N` =
  `examples/shader_advanced/custom_shader_instancing.rs`, `BW:N` = `assets/shaders/instancing.wesl`,
  `BS:N` = `crates/bevy_sprite_render/src/render/mod.rs`; hanabi `HA:N` = `src/asset.rs`. Void
  citations in §A.2.1 were read at `57c53cb1`.

---

## 0. Answer first

1. **One per-particle kernel, three executors, written once in MetaScript.** The appearance of
   a particle (size, colour, rotation over lifetime, sheet frame, flip, pivot, alignment, stretch,
   min/max screen size, camera fade) and, where the modules allow it, its motion are pure
   functions of `(age, seed, velocity, emitter params, curve LUT)`. Written over `src/shader/std`
   types they are ordinary MetaScript, so the **same function** is (a) called on the CPU to fill
   void2d's 64 B sprite instance and to produce positions for sorting and bounds, (b) emitted by
   the shady macro into void3d's particle vertex shader, and (c) the CPU oracle for both. The
   CPU result is not only a test: it is the live path for 2D and for sorting. The emitter already
   gathers an entry's helper functions once (src/shader/CLAUDE.md:79-83) and runs entries on
   the CPU (`src/test/shaderComputeCheck.ms:42-57`), so this needs **no new emitter mechanism**.
2. **Rendering tiers, all on the WebGL2 floor:**
   - **T0, GPU appearance (build first).** CPU SoA simulation (runtime report) uploads a 48 B
     state instance (position+age, velocity+invLife, rotation+start size, start colour, seed;
     §A.10); the vertex shader computes every
     appearance module. Grounded on Unity's custom vertex streams (`AgePercent`,
     `StableRandom*`, `Velocity`, `AnimFrame`/`AnimBlend`, PSE:480+), Godot's particle billboard
     that derives the sheet frame in the vertex stage (GM:1309-1350), and hanabi's vertex-stage
     orient and flipbook (HR:244-275, HO:454-499). Upload falls from 64 B (today's visual
     instance) to 48 B per particle; the larger gain is that the per-particle curve evaluations
     leave the CPU.
   - **T1, procedural motion.** When every enabled module has a closed form in age (Unity's
     procedural set, (mem) plus `proceduralSimulationSupported` in the runtime report §1.6), the
     CPU writes one spawn record per particle once and the vertex shader computes position too.
     Heaps `GpuParticles` is the reference: closed-form motion (HGS:59-72), dirty-range upload
     (HG:843-891), looping by `t % life` so a looping effect uploads nothing in steady state
     (HGS:61-63). The same motion function runs on the CPU for sorting (as HG:813-835 does) and
     for analytic bounds.
   - **T2, compute simulation: later, opt-in, not WebGL2.** sokol has compute on Metal, D3D11,
     GL 4.3, GLES3.1 and WebGPU, not WebGL2 (SG:815-830); Void's emitter already emits compute
     stages with storage buffers (`src/shader/emit.ms:285-297`, `:867-881`), but std has **no
     atomics** and the GPU door has **no compute pass or storage buffer** (§B.2). The
     reference that fits is Godot's RD process shader (fixed emission phase per slot, no
     dead list, dead slots drawn at zero scale, GC:213-216), not hanabi's atomic dead-list.
     WebGL2 runs the same `step` function on the CPU (T0). A compute effect cannot match the CPU
     run bit for bit, so it is a separate effect class with per-backend goldens; that is the
     person's call (§B.5).
3. **Trails: one ribbon program for Unity's Trails module (both modes), Heaps' `Trail` object
   and 2D.** The CPU keeps point rings (SoA) and writes a point stream (24-28 B per point); the
   vertex shader expands each segment from **four adjacent points read by binding the same
   instance buffer at four offsets** (prev, a, b, next), the polyline-with-adjacency shape,
   which needs no storage buffer and no point duplication. Grounded on hanabi's ribbon vertex
   shader that links particle i to i-1 (HR:220-268) and three.js's instanced segments
   (`LineSegmentsGeometry.js:111-116`); binding one buffer at several offsets is the Void
   variant and is the one **NEW MECHANISM** of the render plan (small, to probe: §A.8, §B.6).
   UV modes, width and colour over trail are computed on the CPU per point (Stretch needs the
   trail's total length, a reduction a vertex shader cannot do without a storage buffer).
4. **What does not fit Void today and needs a decision or a mechanism:** soft particles need a
   scene-depth texture during the alpha pass, which the forward renderer does not produce
   (`src/void3d/forwardRenderer.ms:393-399` draws opaque and alpha in one pass); the pixel-art
   preset's depth-in-MRT idiom (`src/void3d/pixelArtRenderer.ms:118-125`) is the existing model to
   extend. The Lights module is capped by void3d's 4 forward point lights
   (`src/void3d/gpu3d.ms:356`, `scene.ms:1314`). void3d's `Program` field has **one free slot**
   (15 of 16 used, `src/void3d/gpu3d.ms:46-62`, 4 bits at `gpu3d.c` `GPU3D_PROGRAM_KEY`), so the
   particle and ribbon programs need the key widened by one bit.

---

## A. Rendering

### A.1 What Void has today (the base the plan extends)

| Piece | Where | What it does |
|---|---|---|
| Plain particle program | `src/void3d/shader3d.ms:358-400`, layout `gpu3d.c:80-85` | 32 B instance (`root` = xyz + size, rgba); camera-facing square, corner from `vertexIndex % 6` (`PARTICLE_CORNERS`, `shader3d.ms:59-62`); fragment tone-maps, `CUTOUT` key discards below 0.5 (`:390-400`). |
| Visual particle program | `shader3d.ms:64-70`, `:315-356`; layout `gpu3d.c:97-102` | 64 B instance (`root`; `shape` = height, anchor xy, rotation; `tile` uv rect; rgba). Camera right/up basis with clockwise rotation (`particleVisualPoint`, `:315-323`). Shares `billboardFs` (lit by `lightParams`, `:402-456`). Keys: `PREMULTIPLIED`, `CUTOUT`, pixel-art preset (`programKeys.txt:10-15`). |
| CPU-side visual records | `src/void3d/particleVisual.ms:126-175` | Builds `ParticleVisualRecord`s (a fresh `Vec` per call, `:146`) from `writeInstances` output; frame index from a Heaps value (`:56-65`). |
| Billboard | `src/void3d/billboard.ms`, `shader3d.ms:436-456` | `AtlasTile` = Heaps `h2d.Tile.split` (`billboard.ms:21-57`); Bevy-style `Anchor` (`:59-`). Two `PENDING3D` markers in the shader (`shader3d.ms:447`, `:451`). |
| Program key | `src/void3d/gpu3d.ms:46-62`, `:76-93`; `gpu3d.c:56` | `Program` (15 values) in 4 bits, preset 2 bits, 10 feature bits; `KEY_LIMIT` 65536 with a 65536-entry index (`gpu3d.ms:97`, `:222`). |
| Phases and order | `src/void3d/material.ms:27-31`, `:126-127`; `src/void3d/passList.ms:132-160` | `Opaque/Alpha/Additive`; `Material.layer`; back-to-front sort by layer, then render order, then depth; stable insertion sort. |
| Lights | `shader3d.ms:215-221`, `gpu3d.ms:356`, `scene.ms:1314` | 4 forward point lights; a 5th is an error. |
| void2d sprite program | `src/void2d/shader2d.ms:87-165`, `src/void2d/instanceLayout.ms:22-32` | 64 B instance: affine abcd, origin+size, uv rect, colour; per-vertex unit `corner`; clip planes; premultiply. One program for every sprite. |
| void2d triangle program | `src/void2d/displayList.ms:131-136` (`Program2D.Vertex`) | CPU-built triangles (Graphics). |
| void2d blend state | `src/gpu/state.ms:54-67`, `src/void2d/batcher.c:21`, `:36` | 12 blend modes (Alpha, Add, Screen, Multiply, Erase, ...), one pipeline per program x target x blend. |
| void2d `TileGroup` | `src/void2d/node.ms:215-231`, `:1015-1100`; `src/void2d/render.ms:822-854` | Retained list of `TileCell {x, y, tile, color, scaleX, scaleY, rotation, skew}` drawn as sprite instances: already the shape of a 2D particle. |
| Heaps `Trail` port | `trail.ms:7-232` (wt/void3d-m5) | Faithful `h3d.scene.Trail`: point list with Bezier smoothing (`:109-180`), mesh rebuilt each frame into a fresh `MeshData` (`:182-232`, allocation at `:187`), `splice(0, n)` to drop old points (`:178`). |

### A.2 Render mode and alignment

Unity: `renderMode` (PSR:121; PSE:13-30: Billboard, Stretch, HorizontalBillboard,
VerticalBillboard, Mesh, None), `alignment` (PSR:66; PSE:76-88: View, World, Local, Facing,
Velocity), stretch parameters `lengthScale` (PSR:260), `velocityScale` (PSR:316),
`cameraVelocityScale` (PSR:372), `freeformStretching` (PSR:724), `rotateWithStretchDirection`
(PSR:727), `allowRoll` (PSR:720), `normalDirection` (PSR:408).

| Unity | Heaps | Godot 4.5 | hanabi | Void 3D | Void 2D |
|---|---|---|---|---|---|
| Billboard + View | `ParticleShader` camera-plane quad (HPS:39-56); `GpuParticle` camera rotation (HGS:94-96) | `BILLBOARD_PARTICLES`: inverse view basis times a per-particle Z rotation (GM:1309-1323) | `ParallelCameraDepthPlane` (HO:472) | VS: basis = camera right/up uniforms (already used by `particleVisualPoint`), rotated by the particle rotation. | CPU: affine = rotation x size into the sprite instance (`shader2d.ms:131-136` already applies abcd). |
| Billboard + Facing | none | `Z_BILLBOARD` uses `sort_direction` (GC:160-166) | `FaceCameraPosition` (HO:487) | VS: basis from `normalize(cameraPos - center)` and world up, per vertex, no CPU cost. | n/a (2D has one view) |
| Billboard + World / Local | `is3D` with a fixed `rotationAxis` (HPS:27, :49-50, :62) | `TRANSFORM_ALIGN_DISABLED` keeps the particle transform (GC:158) | none | VS: basis = identity (World) or the emitter rotation uniform (Local). Measured (`billboard_moved_*` goldens, emitter at (2, 1) turned 30 degrees counter-clockwise, particle rotation 20): View and World give the same quad, the particle's rotation seen on screen, in both simulation spaces; Local adds the emitter's turn to it (net 10 degrees counter-clockwise), in both. Unity bakes a Local-space quad around the particle's local position with offsets already in world orientation. | CPU: the node carries the emitter's transform in a Local-space system, so the writer subtracts the node's on-screen turn from View and World quads, adds nothing to a Local one, and in a World-space system adds the `update` emitter's turn to a Local one (`particles2dCheck.ms`, `billboard_moved_*`). A rotated view camera counts as node turn, so World alignment under one stays screen-aligned. |
| Billboard + Velocity | none | `ALIGN_Y_TO_VELOCITY` (GC:168-180; CPU path GP3:1175-1185) | `AlongVelocity` (HO:499) | VS: the quad's normal is normalize(velocity), as Unity bakes it: edge-on to a camera looking along the velocity (measured, `tests/unity/goldens/billboard_velocity_*`). | CPU: the sprite's x axis follows the velocity, rotation = atan2(vy, vx); a choice, since Unity's edge-on quad has no 2D image. |
| Stretch (`lengthScale`, `velocityScale`, `cameraVelocityScale`) | none (Heaps' nearest is `emitTrail`, which links consecutive particles, HP:184-260) | `Z_BILLBOARD_Y_TO_VELOCITY`: screen-projected velocity (GC:182-198) | `AlongVelocity` + size | VS: axis = screen-projected `velocity*velocityScale - cameraVelocity*cameraVelocityScale` (camera velocity a uniform). Measured (`stretch_*` goldens): direction d is the particle's total velocity, length = `size.y*lengthScale + abs(v)*velocityScale`, width = size.x, head at the particle and tail at `p - length*d`; rotation is ignored; pivot moves the head by `pivot.x*size.x` across and `2*pivot.y*size.y` along d; a still particle draws nothing. `freeformStretching`, `rotateWithStretchDirection` are uniform branches. Measured with `freeformStretching` on (`stretch_freeform*` goldens): the particle's own quad (pivot shift `pivot*size`, then rotation) is stretched about the particle along d by `(size.y*lengthScale + abs(v)*velocityScale) / size.y`, a parallelogram centred on the particle; `rotateWithStretchDirection` adds the stretch rotation `atan2(dy, -dx)` to the particle's rotation first, and with `freeformStretching` off it changes nothing. Unity's freeform quad foreshortens by the viewing angle even under an orthographic camera (area 4.4995 against 4.5 at 0.15 units off axis), which 2D has no analogue of. | CPU: a plain stretch is affine column 0 = stretched velocity, column 1 = its perpendicular x size. A freeform one is a parallelogram: the cell's `skew` (a shear between the rotation and the scale, `cellMatrix`) holds it, so it is one cell of the same tile group as every other particle and keeps its draw order. |
| HorizontalBillboard | none | none | none | VS: basis = world X, world Z (quad in the XZ plane, normal +Y). | n/a |
| VerticalBillboard | none | none | none | VS: right = camera right projected on the horizontal plane, up = world Y. | n/a |
| Mesh (`mesh` PSR:787, `SetMeshes` PSR:832, `SetMeshWeightings` PSR:905, `meshDistribution` PSR:150, PSE:33-40) | none: `Particles` (HP:19) and `GpuParticles` (HG:687-700) draw quads built from their own buffers, `MeshBatch` (HMB:20) instances a mesh but is not a particle system | multimesh of one mesh (runtime report §1.2) | one mesh per effect (`EffectAsset::mesh`, HA:325-335), each vertex expanded along the particle axes (HR:272-275) | Two vertex buffers: the mesh's own vertices in slot 0, a per-instance buffer in slot 1 stepped `SG_VERTEXSTEP_PER_INSTANCE` (SG:2666). Program-key feature `INSTANCED` on `LitTextured`/`UnlitTextured`, which selects a new vertex layout the way `SKINNED` and `NORMAL_MAP` do; instance = 3x4 affine + rgba, 64 B. `meshDistribution`: the mesh index is drawn at spawn, the CPU groups the written instances by it, one draw per mesh. Mechanism, layout and what changes: §A.2.1. | not used in 2D; skip |
| None | n/a | n/a | n/a | No draw; module side effects only (trails, lights, sub-emitters). | same |

**Decision: render mode and alignment are uniform-selected branches inside one vertex entry,
not program-key features.** They change neither the instance layout nor the varyings, the branch
is dynamically uniform (the same for every vertex of a draw), and 5 render modes x 5 alignments
as key features would multiply programs in a key whose `Program` field has one free slot.
Features stay for what changes the interface: `INSTANCED` (mesh), `SOFT`, `FLIPBOOK_BLEND`
(below). Heaps and hanabi compile a constant per mode instead (`@const is3D` HPS:32; hanabi's
pipeline key, HM:2095-2097, :2206-2208); the branch's cost is a measurement item (§D), and a
backend that shows a difference gets a constant for that mode.

### A.2.1 Mesh particles

**Verdict: the references back the plan (feature, two buffers with per-instance step, 3x4
affine + rgba, one draw per mesh), with four corrections** (the 52 B figure, the layout being
selected by the key, the binding needing an offset word, and sort order across meshes).

**What each reference does.**
- Unity: Mesh mode is `renderMode` (PSE:13-30) with `mesh` (PSR:787) or `SetMeshes`
  (PSR:832) and per-mesh weights (PSR:905); `meshDistribution` only chooses how a particle is
  assigned a mesh, `UniformRandom` or `NonUniformRandom` (PSE:33-40, PSR:122-150), so a mesh
  index is a per-particle random draw, not a sort key. `alignment` (PSE:76-88) is a property of
  the renderer, not of billboards, while `allowRoll` is billboard-only (PSR:686). Unity has two
  paths. Its default feeds the shader per-vertex streams, `Position` "in world space", `Center`,
  `Normal`, `Color`, `UV`..`UV4` ("only for meshes", PSE:482-497), so the mesh is expanded per
  vertex on the CPU (native, (mem)). With `enableGPUInstancing` it needs a shader with a
  procedural-instancing pass (PSR:651-652, :685; `supportsMeshInstancing` PSR:1427), which reads
  the particle's data once per instance, not per vertex. Void's design is the second path.
  What a mesh particle carries beyond transform and colour is the stream list: `MeshIndex`
  (PSE:572-573), `AgePercent`, `StableRandom*`, `Custom1/2` and the rest (PSE:480+), and
  `rowMode = MeshIndex` selects a sheet row by the mesh index (PSE:284-286). The native
  expansion and the instancing data layout are not in the reference ((mem)).
- Heaps: `MeshBatch` draws one primitive many times (`instanced.setMesh(primitive)`,
  HMB:76-78), with the instance count in an indirect command (`InstanceBuffer`, 20 B per
  command: index count, instance count, first index, base vertex, first instance, HIB:6-14;
  `drawInstanced`, `h3d/impl/GlDriver.hx:1664`). Per-instance data is not a vertex stream: it is
  a `Vec4` array in a uniform (or storage) buffer indexed by `instanceID` (`Batch_Buffer`,
  HC:686; offset by `Batch_Start`, the one `PerInstance(1)` attribute, HC:680-682, :946-950),
  and a model matrix is written transposed as 3 or 4 `Vec4` (`loadMatrix3x4`, HFB:39-46). The
  uniform path caps a draw at `MAX_BUFFER_ELEMENTS / paramsCount` instances (HMB:26, :266,
  :497-500). `h3d.parts` has no mesh path: `Particles` draws quads from its own buffers (HP:19,
  no primitive field) and `GpuParticles` builds `RawPrimitive`s of its own particle vertices
  (HG:687-700).
- Bevy: the custom-instancing example adds a second vertex-buffer layout to the mesh pipeline,
  `array_stride = size_of::<InstanceData>()`, `step_mode: Instance`, two `Float32x4`
  attributes at shader locations 3 and 4 after the mesh's position, normal and uv at 0-2
  (BI:261-275, instance `{position+scale, color}` BI:131-135), and the draw sets the mesh
  vertices in slot 0 and the instance buffer in slot 1, then `draw_indexed(.., 0..instances)`
  (BI:327-349); the vertex shader reads `i_pos_scale`, `i_color` beside the mesh attributes
  (BW:3-10, :19-29). Bevy's own sprite batcher is the 3-row form: stride 80, three `Float32x4`
  `i_model_transpose_col0..2`, `i_color`, `i_uv_offset_scale` (BS:240-271).
- hanabi: the particle mesh is one mesh per effect, a plane by default (HA:242-253,
  :325-335); its vertex buffer is the mesh layout only (`mod.rs:2159-2165`, `:2273`) and the
  particle is read from a storage buffer by `instance_index` (HR:180-212); each vertex is
  expanded along the particle's axes and size (`vertex_position * size`, HR:272-275). It
  shows the orient-and-scale shape but not the binding: a storage buffer is not on the
  WebGL2 floor (SG:2368, `compute` covers storage buffers), which is why Void takes
  Bevy's mechanism and not hanabi's.

**Settled mechanism.**
1. **Two buffers, per-instance step.** Slot 0 is the mesh's own interleaved vertices
   (`LIT_TEXTURED_VERTEX_STRIDE` 12 floats: position, normal, uv, colour; `meshData.ms:46`),
   slot 1 is a stream buffer stepped per instance. sokol takes this directly: a layout names a
   `buffer_index` per attribute and a `step_func` per buffer (SG:4140-4153), and computes each
   buffer's offsets and stride in attribute order (SG:25975-26000). The door already binds two
   vertex buffers (`GPU3D_BINDING_VERTEX_BUFFER`, "two", `gpu3d.h:17`; `gpu3d.c:304`), and
   `GpuMesh` already holds a `vertexBuffer` and an `instanceBuffer` side by side
   (`draw.ms:117-118`); `bindItem` picks one of them for slot 0 and writes 0 to slot 1
   (`draw.ms:1445-1447`). Slot 0 is never empty, so the WGPU and Vulkan rule at `gpu3d.c:82` holds.
2. **Instance = 64 B, `PARTICLE_MESH`.** Three `FLOAT4` rows of the world-space 3x4 affine
   (row i = `m_i0, m_i1, m_i2, t_i`), then a `FLOAT4` colour. Rows, as Bevy and Heaps lay a
   model matrix out (BS:240-271, HFB:39-46), and as the skinned path already builds its world
   matrix (`skinWorld`, `shader3d.ms:299-303`). Colour is `FLOAT4`, not the `UBYTE4N` of
   §A.10's first draft (52 B): every stream in Void is written as a `Span<float32>`
   (`gpu3dUpdateBuffer`, `gpu3d.c:247`; `draw.ms:685`) and an HDR gradient needs the range;
   the runtime report's 64 B (§3.6) agrees. A packed colour is the same measured trade as the
   billboard instances' (runtime report §3.6) and is taken for both or neither. Attribute
   locations follow the mesh's: 4, 5, 6 rows, 7 colour.
3. **World space, built on the CPU, so alignment and rotation work in all three axes.** The
   CPU composes alignment (View, World, Local, Facing, Velocity), the particle's 3D rotation,
   its 3D size and, for a Local-space system, the emitter transform into the one affine, from
   the same kernel as everything else (§0 item 1). Nothing about the orientation is limited to
   the camera plane, which is what billboard mode does in the vertex shader; this is the
   hanabi expansion (HR:272-275) done before upload, and Unity's per-vertex path
   (PSE:482-483). The vertex shader reads `modelParams.model` no longer: it builds the matrix
   from the three rows, and the normal is `skinNormal` (`shader3d.ms:306-313`), the cofactor
   with the mirror sign, correct for non-uniform size and for a negative one.
4. **One draw per mesh.** The CPU writes each particle's instance at the position its mesh
   index selects, a counting sort by mesh index over the written particles (stable, so each
   group keeps the emitter's order), so mesh k's instances are contiguous in the one stream
   buffer, written by one `gpu3dUpdateBuffer` (sokol allows one per buffer per frame,
   `GpuMesh.writtenFrame`, `draw.ms:127`). Mesh k is drawn with its own vertex buffer in
   slot 0 and the stream buffer in slot 1 at the byte offset of its group, `instances = n_k`.
   `sg_draw_ex` with a base instance is not available on GLES3 or WebGL2 (SG:228-242), so the
   offset is `vertex_buffer_offsets[1]` (SG:3309), the same choice the runtime report makes for
   shared stream buffers (runtime report §3.6). One draw per mesh is the unit every reference
   uses: Bevy draws one mesh per instance buffer (BI:327-349), hanabi has one mesh, and Heaps'
   `MeshBatch` is one primitive (HMB:76-78); a multi-mesh `meshDistribution` has no reference
   draw to copy, only this split. `MeshIndex` as a stream and as a sheet `rowMode` is then a
   per-draw constant, not an instance column.
5. **The key feature.** `INSTANCED` joins `ProgramKey` as one feature bit. The key is already
   16 bits (program 4, preset 2, ten features, `GPU3D_PROGRAM_KEY` in `gpu3d.c`, bit 15 is
   `normalMrt`) and `KEY_LIMIT` is 65536 (`gpu3d.ms:97`), so this is a 17th bit: it needs the
   key widening of §A.10 and risk 5 first, and is a reason to do that slice early. It is
   declared on `LitTextured` and `UnlitTextured`. Like `SKINNED` and `NORMAL_MAP` it changes the
   interface, so it selects a different layout row of `programKeys.txt`
   (`INSTANCED_LIT_TEXTURED`, a new `VertexLayout`, `gpu3d.ms` enum; `describeLayout` in
   `gpu3d.c`; `attributesOf` in `scripts/regen-shaders.sh`), and the regenerate script's
   `#ifdef INSTANCED` check keeps a row from naming a feature its stages never read. The
   combinations with `SKINNED` and `NORMAL_MAP` are not declared: a row that does not exist
   is already an error naming the key (`stopOnFeature`, `gpu3d.ms:107`), and a normal-mapped
   mesh particle would put `tangent` at location 4, so it is its own row when asked for.

**What it changes in Void.**
- `src/void3d/programKeys.txt` (rows), `scripts/regen-shaders.sh` (the feature, the layout's
  attribute list), `src/void3d/gpu3d.ms` (`ProgramKey.instanced`, `VertexLayout`, `of`,
  `declares`, `bits`), `src/void3d/gpu3d.c` (the layout in `describeLayout`, the key macro, the
  attribute `_Static_assert`), `src/void3d/shader3d.ms` (`TexturedAttributes` and the two
  vertex entries read the instance rows under `@feature(INSTANCED)`), `src/void3d/draw.ms`
  (`bindItem`: slot 0 and slot 1 both set for this layout; a `DrawItem` field beside `range`
  (`draw.ms:182`) naming the stream buffer's byte offset and instance count), `gpu3d.h` and
  `gpu3dApplyBindings` (`GPU3D_BINDING_LENGTH` 12 carries no vertex-buffer offsets, so one
  word is added for slot 1's, `gpu3d.c:296-313`), and the particle writer for the sort.
- A shadow caster keeps `INSTANCED` in its key (`castIn` strips features it does not need,
  `gpu3d.ms:304`), or an instanced mesh would cast from its model matrix.

**What it can regress.**
- `src/test/drawCheck.ms:194-195` asserts that `drawsQuads(layout) == layoutPerInstance(layout)`
  and `layoutFloats(layout, 1) == 0` for every layout, and `doorLayoutPerInstance` reads
  `buffers[0]` only (`door.c:355-357`). The new layout is the first with floats in slot 1 and
  per-instance data in slot 1 with a per-vertex slot 0, so both assertions and the door helper
  state the old rule; they are changed to ask about each buffer, and the new layout gets its own
  check (this is a deliberate change of an invariant, not a loosening).
- The renderer refuses a mesh whose layout differs from the program's (`renderer.ms:385-387`):
  a `LitTextured` mesh drawn with an `INSTANCED` program is `VertexLayout`, so the instanced
  mesh is registered as a mesh of the new layout (its vertices are the same bytes).
- Program count: each `INSTANCED` row is a full shdc compile for each preset and
  `PREMULTIPLIED`/`CUTOUT`/`SHADOWED`/`NORMAL_MRT` combination it is declared with; declare
  only what an effect asks for (additive and cutout first).
- Backend behaviour of a per-instance slot 1 beside a per-vertex slot 0 with a buffer offset is
  new to Void (every current layout uses slot 0 only): probe on D3D11 and a WebGL2 build
  before the layout lands (risk 12).

**What the app author sees.**
- Same as Unity: render mode, `alignment`, the 3D rotation and size, `mesh` and
  `SetMeshes` with weights, `meshDistribution`, flip and pivot (the CPU composes them), vertex
  colour times particle colour.
- Different, and the person's call: **draw order across meshes.** Unity expands all of a
  system's mesh particles in the system's sort order ((mem)); here particles are grouped by
  mesh, so with a blended material and a `sortMode` other than `None` (§A.4) a particle of
  mesh A can no longer be drawn between two particles of mesh B. For opaque and cutout
  materials (depth-tested) nothing changes. The alternative that keeps Unity's order is
  to sort first, then cut the sorted list into runs of equal mesh index and draw each run
  (draws = runs, up to one per particle in the worst case of alternating meshes). Recommended:
  group by mesh for opaque and cutout, runs for a blended sorted system, and say in the
  emitter's type which one it gets.
- Different, smaller: a mesh's second to fourth UV sets (`UV2`..`UV4`, PSE:490-497) are not
  carried, because `LitTextured` has one UV (`meshData.ms:46`); and custom streams
  (`Custom1/2`, `AgePercent`, `StableRandom*`) are optional 16 B instance columns appended after
  the colour (§A.10), read in the vertex shader, not per-vertex data.

### A.3 Pivot, flip, min/max size, normal, roll

| Unity | Reference | Void 3D | Void 2D |
|---|---|---|---|
| `pivot` Vector3, in particle sizes (PSR:537) | Void's own `Anchor` (`billboard.ms:59-`; shape.yz in `particleVisualPoint`, `shader3d.ms:319-320`); Godot and hanabi none | VS: subtract pivot.xy from the corner before scaling; pivot.z moves along the facing normal. Uniform per emitter. | CPU: folded into the affine translation (pivot semantics of `Tile.dx/dy`, docs/VOID2D.md:576). |
| `flip` Vector3, a proportion per axis (PSR:577) | none in Heaps, Godot or hanabi | VS: `stableRandom(seed, FLIP_X) < flip.x` mirrors u (y mirrors v); no instance bytes. | CPU: swap u0/u1 in the uv rect. |
| `minParticleSize` / `maxParticleSize` (PSR:452, :492) | none | VS: clamp the size so that `size * proj[1][1] / clip.w` stays in `[2*min, 2*max]`; needs only the projection uniform. Measured (`billboard_clamp_*`, `stretch_clamp_*`, orthographic camera): the unit is the viewport's width in world units (`2 * orthographicSize * aspect`; aspect 1, 0.5 and 2 and sizes 5 and 10 agree). A billboard whose larger side `max(w, h)` is above `max * width` is scaled uniformly down to it, one below `min * width` uniformly up to it, and one between is untouched. On a Stretch quad only the width takes the factor `limit / max(w, h)`; the length `size.y*lengthScale + abs(v)*velocityScale` is built from the unclamped size. | CPU, in the writer: the app passes the viewport width in the node's units to `update(dt, emitter, viewportWidth)`, and the writer applies the measured rule above. A freeform stretch quad is not clamped (not captured). Pivot offsets use the clamped width and height (not captured). |
| `normalDirection` (PSR:408) | Godot `MODELVIEW_NORMAL_MATRIX` from the billboard basis (GM:1338) | VS: lerp the facing normal toward a spherical normal from the corner; feeds `billboardFs` lighting and closes the `PENDING3D: billboard-normal-toward-camera` site (`shader3d.ms:451`). | n/a |
| `allowRoll` (PSR:720) | none | VS: View alignment takes camera up (roll follows the camera) or world up projected (no roll). Measured (`billboard_view_*_noroll`): no effect under an orthographic camera at (0,0,-10) with identity rotation; the quads equal the `allowRoll` on ones. A rolled camera was not captured. | none needed: 2D has one fixed up. |
| `shadowBias` (PSR:410) | none | Particles cast no shadows by default (`castShadows` exists, `material.ms:128`). Out of scope for the first milestone. | n/a |

### A.4 Sorting

Unity: `sortMode` (PSR:203; PSE:44-62: None, Distance, OldestInFront, YoungestInFront, Depth,
DistanceReverse, DepthReverse), `sortingFudge` (PSR:413), and the Renderer base class's sorting
layer and order (not in the particle files; (mem)). The algorithm is the runtime report's (§3.4:
LSD radix of `(key, index)`, order-keeping storage makes age orders free); this table is only
where each key and bias lands.

| Unity | Reference | Void 3D | Void 2D |
|---|---|---|---|
| None | Heaps `SortMode.Back` default; Godot `DRAW_ORDER_INDEX` | emission order (order-keeping storage) | same |
| OldestInFront / YoungestInFront | Heaps Front/Back (HP:107-127); Godot `LIFETIME` | write forward or backward, no sort | same; this is the useful 2D order |
| Distance / DistanceReverse | Heaps camera `z/w` (HP:161-171) | key = squared distance to the camera position; descending or ascending | equal to Depth in 2D (one plane); Unity says the same for orthographic cameras (PSE:50-51) |
| Depth / DepthReverse | Godot `dot(sort_direction, origin)` (GC:89-90) | key = `dot(cameraForward, p)`, 3 multiplies | by the particle's z if the 2D emitter keeps one, else draw order |
| `sortingFudge` | none | added to the emitter's depth in `Phase.Alpha`'s list (`passList.ms:132-160` sorts by `depths`); never applied per particle, as Unity documents (runtime report §1.6) | n/a: 2D order is the display list |
| sorting layer / order | Heaps `Pass.layer` | `Material.layer` (`material.ms:126-127`) and the list's render order (`passList.ms:146-150`) | node order in the display list (void2d draws in tree order) |
| sorted procedural (T1) | Heaps `GpuParticles`: CPU evaluates each closed form, sorts, rewrites the buffer (HG:813-835) | the shared motion function runs on the CPU for the keys; the stream is rewritten in sorted order that frame | n/a |

### A.5 Soft particles and camera fade

Unity's are properties of its built-in particle shaders (`_SoftParticlesNearFadeDistance`,
`_CameraNearFadeDistance`, (mem)), not of the Renderer module.

| Feature | Reference | Void plan | 2D |
|---|---|---|---|
| Camera fade (near/far) | Godot `distance_fade` `ALPHA *= smoothstep(min, max, length(VERTEX))` (GM:1850-1880) | VS: alpha factor from view distance, passed in the colour varying. Per vertex is exact enough for a quad (est.); no depth texture. | n/a |
| Soft particles | Godot `proximity_fade` reads `depth_texture` (GM:1086-1087, :1840-1846); three.js `softParticles` with a contrast curve over view-space depth delta (`examples/jsm/tsl/utils/SoftParticles.js`, "Soft Particles" white paper) | Feature bit `SOFT` on the particle program: FS fades by `saturate((sceneViewZ - fragViewZ) / distance)`. **Needs a scene depth readable in the alpha pass**, which void3d does not have: the forward renderer draws opaque and alpha in one pass (`forwardRenderer.ms:393-399`), and WebGL2 refuses sampling an image that is attached to the current pass. Extend the existing idiom, not a new one: the pixel-art preset already exposes depth to a later pass, either packed into the normal MRT or by sampling the stored depth attachment (`pixelArtRenderer.ms:118-125`; `StoreAction.Store` for a depth read, `src/gpu/door.ms:77-79`). For the forward preset: when a `SOFT` material is in the frame, end the pass after the opaque list with depth stored, copy depth to a sampled target in one fullscreen draw, and run the alpha list in a second pass that loads colour and depth. Cost: one extra pass and one fullscreen read, only in frames with soft particles. | n/a |

### A.6 Texture Sheet Animation

Unity (PSM:11853-12376): `mode` Grid/Sprites (PSE:209-252), `timeMode` Lifetime/Speed/FPS
(PSE:255-266), `fps`, `speedRange`, `numTilesX/Y`, `animation` WholeSheet/SingleRow
(PSE:269-276), `rowMode` Custom/Random/MeshIndex (PSE:279-288), `rowIndex`, `frameOverTime`
and `startFrame` (`MinMaxCurve`), `cycleCount`, `uvChannelMask`, sprite list.

| Unity | Heaps | Godot | hanabi | Void 3D (VS) | Void 2D (CPU) |
|---|---|---|---|---|---|
| Grid, WholeSheet | `GpuParticle`: frame from life x repeat, uv from `frameDivision` (HGS:75-83) | frame = `floor(custom.z * total)`, loop or clamp, uv from h/v frames (GM:1340-1350) | `FLIPBOOK`: uv from `sprite_index` and row count (HR:244-249) | frame = `startFrame + frameOverTime(age) * tiles * cycleCount`, uv from tiles; no uv rect in the instance. | same function on the CPU writes the sprite instance's uv rect |
| SingleRow + rowMode | none | none | none | row = `rowIndex`, or `stableRandom(seed, ROW)`, or the mesh index | same |
| timeMode Speed / FPS | none | `anim_speed` x time (GP3:1093) | none | Speed: `abs(velocity)` through `speedRange`; FPS: `age / invLife * fps`. Both from the instance. | same |
| frame blending (Unity's `AnimBlend` stream, PSE:480+) | `frameBlending` mixes two frames in the FS (HGS:76-78, :113) | none | none | feature `FLIPBOOK_BLEND`: two uv varyings and a blend factor, two samples in the FS | off by default (one more sample per pixel) |
| Sprites mode | Heaps frames list (`AtlasTile.split`, `billboard.ms:46-57`) | none | none | per-frame rects in a uniform `Vec4f[N]` (block arrays are vec4 only, src/shader/CLAUDE.md:20-22) or a LUT row; N bounded, stated | the rect array on the CPU |
| `uvChannelMask` | none | none | none | only UV0 exists; refuse other masks | same |

### A.7 Lights module

Unity (PSM:12464-13151): `ratio`, `useRandomDistribution`, `light` template, `useParticleColor`,
`sizeAffectsRange`, `alphaAffectsIntensity`, `range`, `intensity`, `maxLights`. None of Heaps,
Godot's CPU particles or hanabi has particle lights.

Void plan: the CPU picks `min(maxLights, round(ratio * alive))` particles (first by emission
order, or by `stableRandom(seed)` when `useRandomDistribution`), and writes point lights for the
frame with colour, range and intensity from the module. The binding limit is void3d's forward
light budget: 4 point lights per draw (`gpu3d.ms:356`), and a 5th is an error
(`scene.ms:1314`). So particle lights take what the scene leaves and the module states that cap;
a real particle-light count needs clustered or tiled lighting, a separate arc. 2D has no
lighting; the module does not exist there.

### A.8 Trails module and the Trail object

Unity (PSM:13224-14118): `mode` PerParticle/Ribbon (PSE:666-672), `ratio`, `lifetime`,
`minVertexDistance`, `textureMode` Stretch/Tile/DistributePerSegment/RepeatPerSegment/Static
(PSE:676-688), `textureScale`, `worldSpace`, `dieWithParticles`, `sizeAffectsWidth`,
`sizeAffectsLifetime`, `inheritParticleColor`, `colorOverLifetime`, `widthOverTrail`,
`colorOverTrail`, `generateLightingData`, `ribbonCount`, `shadowBias`, `splitSubEmitterRibbons`,
`attachRibbonsToTransform`; the Renderer's `trailMaterial` (PSR:649) and trail vertex streams
(PSR:1248-1423).

**References.**
- Heaps `h3d.scene.Trail` (object trail, Unity's `TrailRenderer`): points sampled from the
  object's transform with Bezier smoothing (HT:93-160), a strip rebuilt every frame into a
  dynamic primitive, normal and `u = age / duration` per point (HT:195-246), buffers sized to a
  power of two of `duration * fps` (HT:252-256). Void's port is `trail.ms` (wt/void3d-m5).
- Heaps `Particles.emitTrail`: consecutive particles in list order form one strip (HP:184-260):
  this is Unity's **Ribbon** mode.
- Godot GPU trails: each particle is simulated `trail_size` times against a frame-param history
  (GS:1117-1200, history sized `trail_lifetime * fixed_fps`, GS:1472-1503); the copy pass writes
  one transform per trail section, interpolated by velocity (GC:148-154), used as bone poses of
  a ribbon or tube mesh (`trail_bind_poses`, GC:201-204). Compute only.
- hanabi ribbons: particles sorted by `(RIBBON_ID, AGE)` (HM:4736-4741) and drawn one quad per
  instance linking particle i to i-1 read from the storage buffer, discarding when the ribbon id
  changes (HR:220-268). Storage buffer in the vertex stage: WebGPU only.
- three.js wide lines: instanced segments with `instanceStart`/`instanceEnd` in one interleaved
  buffer (`LineSegmentsGeometry.js:111-116`), a polyline converted by duplicating each inner
  point (`LineGeometry.js:50-61`).

**Void plan.** One ribbon program serves the Trails module (both modes), the Trail object and
(later) 2D.

| Concern | Plan | Reference |
|---|---|---|
| Point storage, PerParticle | per particle a ring of K points in SoA columns (`x y z t` + width + colour index), K = `ceil(lifetime / minimum sample interval)`, fixed at create; a new point when the head moved more than `minVertexDistance` | Godot's fixed history (GS:1478-1481); replaces `trail.ms`'s `splice(0, n)` (`:178`) and per-frame `MeshData` (`:187`) |
| Point storage, Ribbon | none: the particles are the points, in emission order, which order-keeping storage gives for free (runtime report §3.3); `ribbonCount` = particle index mod N, one chain each (mem for the exact Unity rule) | Heaps `emitTrail` (HP:184-260); hanabi has to sort for it (HM:4736-4741) |
| Point stream (GPU input) | per point: position + width (FLOAT4), colour (UBYTE4N, HDR: HALF4), u (FLOAT), chain id (UINT): **28 B**, 32 with HDR colour (est. from the field list) | hanabi's ribbon id (HR:233-239) |
| Segment expansion | VS: instance i reads points i, i+1, i+2, i+3 = (prev, a, b, next) by **binding the same buffer in four vertex-buffer slots at offsets 0, s, 2s, 3s** (s = stride; `vertex_buffer_offsets`, SG:3308-3309; 8 slots, SG:2182). Each chain is written with its first and last point duplicated, so an end segment's tangent is well defined, and a segment whose a and b carry different chain ids collapses to zero area. Miter from the prev/next tangents, width across `cross(tangent, toCamera)` (View alignment, Unity's default for trails, (mem)) or across the transform's axis (Heaps' `angle`, HT:196-216). 4 attributes from slot a/b, 1 each from prev/next: 10 of 16 attributes, stride 28 of 255. | hanabi links i to i-1 (HR:228-268); three.js segments (`LineSegmentsGeometry.js:111-116`) without its duplication (`LineGeometry.js:50-61`). **NEW MECHANISM** in Void: one buffer bound in several slots at overlapping offsets. Verify sokol's validation accepts the same buffer in two slots, on every backend. |
| `textureMode` | CPU writes u per point. Stretch: cumulative length / total length (needs the whole chain: a reduction); Tile: cumulative length x `textureScale.x`; DistributePerSegment: index / (n-1); RepeatPerSegment: index; Static: length from the trail's birth, so u does not slide | Heaps writes `u = age` (HT:220-221); Unity semantics from PSE:676-688 |
| `widthOverTrail`, `colorOverTrail`, `colorOverLifetime`, `inheritParticleColor`, `sizeAffectsWidth` | CPU per point, folded into width and colour (one curve sample each, per point not per vertex); or VS from a LUT row and u when the point count is large: measured choice | Heaps lerps width by age (HT:212-213) |
| `lifetime`, `sizeAffectsLifetime`, `dieWithParticles` | CPU ring logic; a dead particle's ring either drains (points expire by time) or is dropped | Godot stops trails on a restart (GS:1159-1170) |
| `worldSpace` | points in world space, or in the emitter's space with the emitter matrix as the draw's model uniform | Heaps uses world space (HT:98-101) |
| `generateLightingData` | the VS writes the ribbon normal to the existing lit varyings (`billboardFs`) | Heaps writes `n` (HT:209-224) |
| Trail object (TrailRenderer, Heaps `Trail`) | `trail.ms` sampling logic kept as the Heaps oracle; its output becomes a point stream for the ribbon program instead of a `MeshData` | `trail.ms:109-180` |
| 2D | first: CPU triangles through `Program2D.Vertex` (the Graphics path, `displayList.ms:131-136`), which is what Heaps does in 3D; a `Program2D.Ribbon` running the same VS later if a measurement asks | HT:195-260 |

### A.9 Custom vertex streams and custom shaders

Unity: `SetActiveVertexStreams` / `GetActiveVertexStreams` (PSR:1239-1244), trail streams
(PSR:1418-1423), stream vocabulary (PSE:480+: Position, Normal, Tangent, Color, UV..UV4,
AnimBlend, AnimFrame, Center, VertexID, SizeX/XY/XYZ, Rotation, Rotation3D, RotationSpeed,
Velocity, Speed, AgePercent, InvStartLifetime, StableRandomX..XYZW, VaryingRandomX..XYZW,
Custom1X..XYZW, Custom2X..XYZW, NoiseSum..., MeshIndex, ...).

Void plan: **the stream list is the vertex entry's input struct.** A particle shader written as
a shady vertex entry declares the streams it reads as fields of its stage input; the generator
packs the instance layout from those fields (program.ms already packs attributes "in declaration
order with no padding", src/shader/CLAUDE.md:126-127) and the CPU writer fills exactly those
columns. hanabi generates its particle layout from the attributes the effect uses (runtime report
§1.4, HM:1956, :2068); Unity lets the author pick streams by hand. Two extensions, no new
mechanism: `shaderProgram` must accept a per-instance buffer (today it registers one per-vertex
buffer, `src/shader/program.ms:117-132`), and the stream names become a fixed `ParticleStreams`
vocabulary so the writer knows what each field means. `Custom1/2` come from the Custom Data
module (PSM:14127-), `StableRandom` is recomputed from `seed` in the shader (no bytes),
`VaryingRandom` is `hash(seed, frame)` (no bytes).

### A.10 Instance formats, programs and key bits

Byte counts are from the field lists (est.), to be held by a layout check like
`src/test/instanceLayoutCheck.ms` once built (docs/VOID2D.md:156-170 is that idiom).

**3D streams**

| Stream | Attributes | Bytes | Used by |
|---|---|---|---|
| `PARTICLE_STATE` (T0) | a0 FLOAT4 position.xyz, age01; a1 FLOAT4 velocity.xyz, invLife; a2 FLOAT2 rotation, startSize; a3 UBYTE4N startColor (HALF4 when the effect is HDR); a4 UINT seed | **48** (52 HDR) | CPU-simulated billboards; appearance in the VS |
| optional columns | FLOAT4 size3D + rotation, FLOAT4 or HALF4 quaternion (Rotation3D), FLOAT4 Custom1, FLOAT4 Custom2 | +16 each | only when a module or a custom shader reads them (A.9) |
| `PARTICLE_SPAWN` (T1) | a0 FLOAT4 spawn position, spawn time; a1 FLOAT4 start velocity, lifetime; a2 FLOAT4 start rotation, angular velocity, start size, spare; a3 UBYTE4N start colour; a4 UINT seed | **56**, written on spawn only | procedural effects |
| `PARTICLE_MESH` | slot 0 (per vertex): the mesh's own layout, 48 B for `LitTextured`; slot 1 (per instance): 3 x FLOAT4 world-space affine rows + FLOAT4 colour (A.2.1) | **64** per instance (+16 per custom column) | Mesh render mode, feature `INSTANCED` |
| `RIBBON_POINT` | FLOAT4 position, width; UBYTE4N colour; FLOAT u; UINT chain id | **28** (32 HDR) | trails, both modes, and the Trail object |
| today: `PARTICLE`, `PARTICLE_VISUAL` | `gpu3d.c:80-102` | 32, 64 | kept for the Heaps-compatibility front end the authoring report proposes, retired with it |

Today's visual instance carries appearance already evaluated on the CPU (64 B, `particles.ms:198`);
`PARTICLE_STATE` carries what appearance is computed *from*. The byte saving is modest (48 vs
64 B, 25%); the larger gain is CPU time, because the curve evaluations per particle per frame
that the runtime report lists as cost item 2 (`particles.ms:669-727`) leave the CPU.

**Programs and key.** Two program bases: `ParticleSystem` (one vertex entry serving `STATE`
and, under a `PROCEDURAL` feature, `SPAWN`; fragment = `billboardFs` grown by `SOFT` and
`FLIPBOOK_BLEND`) and `Ribbon` (vertex entry over four `RIBBON_POINT` taps, same fragment). Mesh
particles are a feature `INSTANCED` on `LitTextured`/`UnlitTextured`. Lighting stays a uniform
switch, as `billboardFs` already does (`shader3d.ms:473`, `billboard.y != 0.0`), which is the
precedent for A.2's uniform branches. Consequences in the key:
- `Program` has 15 values in 4 bits (`gpu3d.ms:46-62`, `gpu3d.c:56`): adding two bases needs a
  5th bit, unless `Particle` and `ParticleVisual` retire first.
- Three or four new feature bits (`INSTANCED` among them, A.2.1) move the key from 16 to about 20 bits. `KEY_LIMIT` is 65536
  with a dense index of that many entries (`gpu3d.ms:97`, `:222`); at 20 bits the dense index is
  1M entries (4 MB est.), so widening the key also means replacing the dense index with a sorted
  table of the declared rows (`programKeys.txt` has 256 rows). Existing mechanism, a measured
  change.

**2D** needs no new program for particles: the 64 B sprite instance (`instanceLayout.ms:22-32`)
takes every appearance module computed on the CPU by the shared functions (rotation, stretch and
pivot in the affine, sheet frame and flip in the uv rect, colour), and the particles batch with
sprites by texture and blend (runtime report §3.6). `TileGroup`'s `TileCell` is already a 2D
particle's draw record (`node.ms:215-223`); a 2D particle node is a `DrawKind` beside it writing
the same instances straight from SoA columns, without a `TileCell` per particle. A 2D GPU tier
(a `Program2D.Particle` running the 3D `ParticleSystem` vertex entry with an orthographic camera)
is taken only when a measurement shows the CPU instance write is the 2D bottleneck.

---

## B. The shady shader module and the GPU path

### B.1 What the emitter supports today

`src/shader/emit.ms` (1830 lines), `src/shader/std.ms` (1924), `src/shader/program.ms` (228);
design and measurements in `src/shader/CLAUDE.md`; tiers in `docs/SHADER.md:5-47`.

| Capability | State | Evidence |
|---|---|---|
| Vertex and fragment entries; stage from the return type | yes, used by every void3d and void2d program | src/shader/CLAUDE.md:30-45; docs/SHADER.md:37 |
| Helper functions gathered once, callable from CPU code and from entries | yes; module consts become GLSL consts; recursion refused | src/shader/CLAUDE.md:79-83 |
| CPU run of an entry as oracle, within a tolerance | yes; "never pixel-exact"; pixel truth is the capture readback | src/shader/CLAUDE.md:147-149; shady's own claim, `~/projects/shady/README.md:3` |
| Program-key features (`#ifdef`) | yes, `@feature(NAME)` booleans in `if` conditions | src/shader/CLAUDE.md:46-56 |
| Per-instance attributes and `vertexIndex` / `instanceIndex` | builtins yes (`emit.ms:991-992`); per-instance layout is the C side's (`gpu3d.c:80-102`); the write-run `shaderProgram` registers one per-vertex buffer only | `src/shader/program.ms:117-132`; src/shader/CLAUDE.md:120-127 |
| Texture fetch in a vertex entry | `textureLoad` (texelFetch, with a sampler) yes; `textureSample` refused outside a fragment, as are derivatives | `emit.ms:1525-1530`, `:1504-1506`; std `textureLoad` `std.ms:1804-` |
| Uniform blocks | author struct packed into float/int/vec/mat members; arrays only vec4, ivec4, mat4 | src/shader/CLAUDE.md:19-23 |
| uint32 hashing | wraps on CPU as on GPU, so a PCG hash is bit-identical; int32 overflow traps on the CPU | src/shader/CLAUDE.md:95-102 |
| Compute entries | yes: `glslCompute(entry, [x, y, z])`, compute builtins, workgroup a multiple of 32, entry returns nothing | `emit.ms:285-300`, `:433-437`, `:1008`, `:1811-1824`; `src/test/shaderComputeCheck.ms:59-76` pins the GLSL |
| Storage buffers | yes, an unsized array of an author struct per binding; `readonly` unless `@access(read_write)`, which only a compute entry may use; a read-only one is accepted in a vertex entry | `emit.ms:867-881`, `:1781-1782`; `std.ms:1744-1753` |
| Storage textures | compute only; 8 formats | `emit.ms:883-904`; `std.ms:1775-1797` |
| Atomics, barriers, workgroup shared memory | **absent** from std (0 matches for atomic/barrier/shared in `std.ms`); GLSL names only reserved (`emit.ms:81-89`). shdc compiles them on every backend but ES300 (src/shader/CLAUDE.md:204-207) | grep of `std.ms` |
| A compute entry run on the CPU | yes, by calling the entry with an invocation id (`shaderComputeCheck.ms:42-57`); shady's `runComputeOnCpu` loops the whole dispatch and writes a CPU image next to the GPU one (`~/projects/shady/examples/compute1.nim:124-126`, `compute1_output_cpu.png` / `compute1_output_gpu.png`) | |
| Backends | one GLSL 450 through sokol-shdc to Metal, HLSL5, GLSL 4.3, GLSL ES 3.0, WGSL; compute everywhere except `glsl300es` | src/shader/CLAUDE.md:7-8, :204-207; docs/SHADER.md:7-21 |

### B.2 What the runtime supports today

| Capability | State | Evidence |
|---|---|---|
| Compute pass, compute pipeline, dispatch | **none** in the GPU door, `src/sokol`, void2d or void3d (no `sg_dispatch`, no `.compute` pass) | grep of `src/gpu/*.c`, `src/gpu/*.ms`, `src/sokol/bridge.c` |
| Storage buffers | **none**: buffers are vertex or index, optionally dynamic | `src/gpu/draw.c:15-17`; `src/void3d/gpu3d.c:213-270` |
| sokol's compute matrix | Metal, D3D11, GL 4.3, GLES 3.1, WebGPU; **not** WebGL2, macOS GL or iOS GLES3; storage buffers have the same restriction | SG:815-830 |
| Indirect draw, readback | none in sokol | docs/SHADER.md walls via src/shader/CLAUDE.md:217-219; runtime report §3.8 |
| Float render targets | `Rgba16f` only (`src/gpu/door.ms:61-69`, `door.c:75-84`); sokol detects `EXT_color_buffer_float` on GL/WebGL2 (SG:10675-10676) | |
| Vertex attribute formats | FLOAT..FLOAT4, INT/UINT 1-4, BYTE4(N), UBYTE4(N), SHORT2/4(N), HALF2/4, 10_10_10_2 | SG:2619-2647 |
| Limits on the web floor | 16 attributes, 8 vertex buffer slots, no `base_instance` on GLES3, 255 B stride | SG:2180-2182, SG:238-239; docs/VOID2D.md:139-147 |

### B.3 Can one MetaScript function be the CPU update and the shader?

**Yes, for a per-particle pure function over std types, and that is the unit to share.** The
emitter gathers every author function an entry reaches and defines it once above `main()`
(src/shader/CLAUDE.md:79-83); the same function, being ordinary MetaScript, runs on the CPU with
std's CPU meaning (docs/SHADER.md:37; shady README:3). What is shared is the body
`(particle, params, lut) -> result`; the loop around it belongs to each executor: the CPU's SoA
loop (runtime report §3.1-3.3), the vertex shader's per-vertex call, or a compute/fragment
invocation per slot. Sketch (illustration, not code in the tree):

```ts
// particleKernel.ms: ./std types only, so glsl() can emit it and the CPU can call it.
export struct ParticleIn {
	position: Vec3f; age: float32; velocity: Vec3f; invLife: float32;
	rotation: float32; startSize: float32; startColor: Vec4f; seed: uint32;
}
export struct Look { size: Vec2f; rotation: float32; color: Vec4f; uv: Vec4f; }

export function look(p: ParticleIn, m: EmitterParams, lut: Texture2d, s: Sampler): Look {
	const size = p.startSize * curveAt(lut, s, m.sizeRow, p.age);      // textureLoad x2 + mix
	const color = p.startColor * gradientAt(lut, s, m.colorRow, p.age, stableRandom(p.seed, 3u));
	const frame = sheetFrame(m, p.age, length(p.velocity), p.invLife, p.seed);
	return { size: vec2f(size), rotation: p.rotation, color, uv: sheetUv(m, frame, p.seed) };
}
// CPU, void2d: for each alive i, look(row(i), ...) fills the 64 B sprite instance.
// GPU, void3d: particleSystemVs calls look(input, b.emitter, b.lut, b.lutSampler).
```

Constraints the shared function must meet, each already enforced by the emitter at the author's
code: no `Vec`, `Result`, closures or recursion; uniform arrays only `vec4`/`mat4`; hashing in
uint32 (src/shader/CLAUDE.md:95-102); in a vertex entry `textureLoad` not `textureSample`
(`emit.ms:1528-1530`), so curves are read with two `textureLoad`s and a `mix`, which on the CPU
is the same arithmetic on the same texels (std `Texture2d` holds `texels: float32[]`,
`std.ms:1760-1764`). Randoms are bit-identical CPU to GPU (uint32 PCG, then an exact scale);
`sin`/`cos`/`pow` differ by implementation, so CPU and GPU agree within a tolerance, which is the
oracle contract the module already has (src/shader/CLAUDE.md:147-149).

Not reusable as is: `src/void3d/particleNoise.ms` is written over `math3d` `Vec3` and
`Math.floor` (`particleNoise.ms:8-15`), not std types; it is a straight re-expression over
`Vec3f`/`floor`/`fract` to make turbulence emit-able (it was transcribed from Godot's GLSL in the
first place, `:1-6`).

Open cost: std's vector types are structs with operator functions (`std.ms:1144-1265`) and its
`sqrt`, `normalize`, `pow` carry refusal checks (docs/VOCABULARY.md:99-103). Whether a CPU loop
over them compiles to code as tight as the runtime report's scalar column loops is unmeasured;
it is the first measurement (§D.1). If it is slower, the CPU keeps scalar column code for the
hot simulation and shares the kernel only for appearance (2D writes) and the oracle.

### B.4 The three GPU tiers against the WebGL2 floor

| | T1 procedural vertex shader | T2b compute simulation | T2a fragment-pass simulation | T3 GPU trails |
|---|---|---|---|---|
| What runs on the GPU | motion and appearance as closed forms of age; CPU emits spawn records | stateful update per slot, render reads state from a storage buffer | stateful update per slot as a fragment entry over state textures (ping-pong), render reads state by `textureLoad` in the VS | segment expansion from point streams (with T0/T1); history simulation (with T2) |
| Needs | per-instance attributes, uniforms, VS texel fetch | compute, storage buffers RW, (atomics for dead lists) | float render targets (RGBA32F + `EXT_color_buffer_float` on WebGL2), MRT up to 4, VS texel fetch | T0/T1 path: vertex buffers at offsets; T2 path: history buffers or textures |
| WebGL2 | **yes** (16 attributes, 56 B stride, VS texture units core in WebGL2 (mem)) | **no** (SG:815-830) | yes where the float-target extension exists (sokol detects it, SG:10675-10676; coverage (mem): near-universal on desktop, common on mobile) | yes for the CPU-point path; no for compute history |
| Emitter today | yes: vertex entry, `textureLoad`, uniforms (§B.1) | partly: compute entry and RW storage buffers yes; atomics, barriers, shared memory no (`std.ms`) | yes: fragment entry with an MRT output struct (src/shader/CLAUDE.md:42-45 `@location(n)`), `textureLoad` | yes (vertex entry) |
| Runtime today | yes after the new layout and program (§A.10) | no: compute pass, pipeline, dispatch and storage buffers absent from the door (§B.2) | mostly: render passes and targets exist; add `Rgba32f` (`door.ms:61-69`) | yes, plus the multi-offset binding (§A.8) |
| Spawn / kill without atomics | CPU | Godot's fixed emission phase per slot (runtime report §1.2, `particles.glsl:389-410`); dead slots drawn at zero scale (GC:213-216) | the same slot-phase rule, one texel per slot | n/a |
| Draw count | live spawn records | capacity (no indirect draw in sokol) | capacity | points |
| Sorting | CPU evaluates motion for keys, rewrites the stream (HG:813-835) | GPU bitonic (Godot `sort.glsl`, runtime report §1.2) needs compute | none, or fragment-pass bitonic (prior art outside the four references, (mem)) | chain order from the CPU |
| CPU vs GPU result | same function; per-frame tolerance only (no state carried) | trajectories diverge over frames: tolerance per step only, no runtime comparison (no readback) | same as T2b | T0/T1 path: exact points from the CPU |
| Reference | Heaps `GpuParticles` + `GpuParticle` (HG:323-441, :843-891; HGS:59-114); Unity procedural mode (runtime report §1.6) | Godot RD particles (process + copy + sort); hanabi for the general shape (runtime report §1.4) | three.js `GPUComputationRenderer` (ping-pong render targets per variable, `GPUComputationRenderer.js:23-26`, `:251-289`) + Godot's slot-phase emission | hanabi ribbons (HR:220-268); Godot trail history (GS:1117-1200, :1472-1503) |
| New mechanism for Void | no (a program and a layout) | door compute support is sokol's API wrapped, an extension; atomics in std is an extension of the std vocabulary (WGSL names) | **NEW MECHANISM**: GPU-resident particle state in textures, simulated by a fragment pass; reference is three.js only, none of Heaps, Bevy/hanabi or Godot does it | the multi-offset binding (§A.8) |

### B.5 Tier recommendation

1. **Build T0 (CPU simulation, GPU appearance) first, with the kernel shared as in B.3.** It is
   the only tier every effect can use, it runs unchanged on WebGL2, and it makes the shady
   emitter carry Unity's render modules once for 2D (CPU) and 3D (VS).
2. **Then T1 (procedural) as an automatic upgrade per emitter**, when the enabled modules are
   all closed-form (gravity, constant force, start speed, velocity-over-lifetime and
   size/colour/rotation curves of age via LUTs that store the curve's integral for position, no
   noise, no collision, no sub-emitters, no limit-velocity; the exact Unity list is (mem) and
   must be checked against `proceduralSimulationSupported`). Unity decides this per system the
   same way (runtime report §1.6). The CPU keeps the motion function for sorting, bounds and the
   oracle. Looping emitters upload nothing in steady state (HGS:61-63).
3. **Defer any stateful GPU simulation (T2) until a measurement shows T0 cannot reach the
   count target** (runtime report §3.9 estimates 200k-500k unsorted native, 100k-250k wasm at
   2 ms). When it is needed, the decision for the person is between:
   - **T2a fragment-pass simulation** (NEW MECHANISM, three.js prior art): one GPU path on every
     backend including WebGL2, so no backend falls back to a different executor; costs: float
     render targets, capacity-sized draws, no scatter (no sub-emitters, no GPU dead list), GPU
     sort only by fragment passes.
   - **T2b compute** (Godot RD shape): faster primitives (scatter, atomics, bitonic sort), but
     WebGL2 and macOS GL run T0 instead, so the same effect has two executors with different
     results; Godot keeps this as a separate node type (`GPUParticles` beside `CPUParticles`),
     and so should Void.
   Either way the result cannot be bit-identical to the CPU and is held by per-backend goldens
   (runtime report §3.8 item 1).
4. **T3**: build the ribbon program on CPU points now (A.8); GPU-simulated trails only with T2.

### B.6 Which reference backs each piece

| Piece | Backed by | Kind |
|---|---|---|
| Unity module and field vocabulary for rendering, sheet, lights, trails, streams | Unity C# (PSE, PSR, PSM lines above) | authoring reference |
| Appearance in the vertex stage from age, seed, velocity | Unity custom vertex streams (PSE:480+); Godot particle billboard and sheet frame (GM:1309-1350); hanabi orient and flipbook (HO:454-499, HR:244-275) | existing mechanisms ported |
| Closed-form motion, dirty-range spawn upload, looping without upload | Heaps `GpuParticles` (HG:843-891, HGS:59-72) | ported |
| One function on CPU and GPU, CPU as oracle | shady (README:3, `examples/compute1.nim:124-126`); Void's emitter (src/shader/CLAUDE.md:79-83, :147-149) | existing |
| Curves as LUT textures read in the shader | Heaps colour gradient texture (HGS:22, :108, :112); Godot curve textures in the process material (`cpu_particles_3d.cpp:814-821` samples baked curves, runtime report §3.3) | ported |
| Render modes and alignment as uniform branches | Void's own `billboardFs` lighting switch (`shader3d.ms:473`) | existing Void idiom; differs from Heaps/hanabi constants (A.2) |
| Soft particles | Godot `proximity_fade` + `depth_texture` (GM:1086-1087, :1840-1846); depth exposed to a later pass as the pixel-art preset does (`pixelArtRenderer.ms:118-125`) | extension of the forward preset |
| Ribbon from consecutive particles | Heaps `emitTrail` (HP:184-260); hanabi ribbons (HR:220-268) | ported |
| Point rings for per-particle trails | Godot history (GS:1472-1503) on the CPU | ported |
| Segment instance with neighbours from one buffer at four offsets | three.js instanced segments (`LineSegmentsGeometry.js:111-116`); sokol `vertex_buffer_offsets` (SG:3308-3309) | **NEW MECHANISM** (small) |
| Layout from the streams a shader reads | hanabi `ParticleLayout` (runtime report §1.4) | ported |
| Compute simulation without atomics | Godot slot-phase emission and zero-scale dead slots (GC:213-216) | ported, when T2b is chosen |
| Fragment-pass GPU state | three.js `GPUComputationRenderer` (`:23-26`, `:251-289`) | **NEW MECHANISM**, only if T2a is chosen |

---

## C. Risks

| # | Risk | Why it matters | Mitigation or trigger |
|---|---|---|---|
| 1 | VS cost of appearance: 6 vertices per particle each re-run `look()` (curve LUT `textureLoad` x2 per curve, sheet frame, alignment basis) | the per-particle work moves from 1 CPU evaluation to 6 GPU evaluations; on mobile and WebGL2 vertex texture fetch is slower than fragment fetch (mem) | measure (D.3); if it shows, index-draw 4 vertices (`vertexIndex % 4` with an index buffer) or move curve reads to a per-instance CPU column for that backend |
| 2 | float32 precision of procedural time (T1): `now - spawnTime` loses resolution after hours of uptime (est.: 2^24 s is about 194 days at 1 s, but at 1 ms resolution the limit is about 4.6 h) | jitter in long-running editors and idle games | rebase the epoch per emitter when it passes a threshold and rewrite the spawn stream once (the dirty-range upload already exists in the Heaps shape, HG:843-891) |
| 3 | CPU speed of std vector types for the shared kernel (B.3) | the kernel may be slower than scalar column loops; 2D appearance then costs more than today | D.1 decides; fall back to sharing only the oracle |
| 4 | helper argument copies (src/shader/CLAUDE.md:140-146) inflate the emitted GLSL and the wasm text for a large kernel | compile time per program and web download size | count emitted lines per program in the program-key check; budget against today's `billboardFs` |
| 5 | key widening (A.10): a 5th `Program` bit and a sparse index | touches every void3d program and its key table | do it in its own slice, gated by the existing key tests, before particle programs land |
| 6 | shdc and sokol on ES300 with vertex texture fetch and a dummy sampler (src/shader/CLAUDE.md:212-214) | the T0 VS reads the LUT in the vertex stage; WebGL2 allows it (MAX_VERTEX_TEXTURE_IMAGE_UNITS >= 16 in ES 3.0, (mem)) but Void has never bound a VS texture | first probe of the milestone (D.2), on WebGL2 and WebGPU builds |
| 7 | one buffer bound to several vertex-buffer slots at different offsets (ribbon taps, A.8) | sokol validation and backend behaviour unverified; it is the one NEW MECHANISM in the base plan | probe (D.5); fallback is duplicating neighbour data into a 64-112 B segment instance (est.) |
| 8 | 4 forward point lights (`gpu3d.ms:356`, `scene.ms:1314`) | Unity's Lights module with `maxLights` > 4 cannot map; a 5th light is an error | Lights module picks at most the free slots per frame and says so in its type; a clustered light list is outside this arc |
| 9 | soft particles need a scene-depth texture, which the single forward pass does not expose (`forwardRenderer.ms:393-399`) | adds a depth copy or a depth-prepass per frame when any soft emitter is visible | only pay it when a `SOFT` program is in the frame; measure (D.6) |
| 10 | T2 has no bit-exact CPU match and no readback | goldens per backend instead of one; a red cannot be bisected against the CPU | the person's decision (B.5 item 3) before any T2 work |
| 11 | sort with T1: the CPU must evaluate motion to sort, so sorted procedural emitters keep a CPU cost per particle (HG:813-835) | sorted alpha effects gain less from T1 | document per emitter; additive and cutout effects need no sort |
| 12 | mesh particles (A.2.1): the first layout with a per-instance slot 1 beside a per-vertex slot 0, drawn at a `vertex_buffer_offsets[1]` | every current layout uses slot 0 only, `drawCheck.ms:194-195` and `doorLayoutPerInstance` state the one-slot rule, and `INSTANCED` is the 17th key bit | probe the layout and the offset on D3D11 and WebGL2 with sokol validation on before the layout lands; change the two assertions to per-buffer ones in the same slice; do the key widening (risk 5) first |

## D. Measurement plan

All runs in a named BEGIN/END quiet window, one GPU run at a time, on the backends listed;
numbers recorded beside the bench (`docs/TESTING.md` bench idiom). Counts 10k, 100k, 1M where the
backend survives them.

| # | Question | Setup | Backends | Decides |
|---|---|---|---|---|
| D.1 | CPU speed of the shared kernel over std types vs scalar columns | one emitter with size, colour, sheet, rotation curves; time `look()` loop vs the runtime report's column loop | native D3D11 build, wasm | whether CPU and GPU share the kernel or only the oracle (B.3, risk 3) |
| D.2 | VS texture fetch works and its cost | T0 program reading a 256x8 RGBA16F LUT in the VS; frame time vs the same program with curves as constants | D3D11, Metal, WebGL2, WebGPU | risk 6; LUT vs uniform curves |
| D.3 | T0 vs today's CPU-baked 64 B visual instance | same effect both ways; CPU ms, upload bytes, GPU ms | all four | that T0 replaces the visual path |
| D.4 | uniform branch vs constant per render mode / alignment | one entry with the switch vs a specialised entry per mode | all four | A.2's decision; a backend that loses gets a constant |
| D.5 | ribbon four-tap binding | one `RIBBON_POINT` buffer at offsets 0, s, 2s, 3s vs a duplicated segment instance | all four, with sokol validation on | the NEW MECHANISM in A.8 or its fallback |
| D.6 | soft-particle depth copy | frame time with one soft emitter on screen vs none | all four | whether SOFT ships in the first milestone |
| D.7 | T1 steady-state upload | looping emitter at 100k: bytes uploaded per frame under T0 vs T1 | D3D11, WebGL2 | T1's value per effect type |
| D.8 | particles reached in 2 ms (sim + upload + draw) | T0 and T1 at rising counts until 2 ms | all four | whether T2 is ever needed (B.5 item 3) |
