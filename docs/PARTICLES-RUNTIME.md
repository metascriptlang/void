# Particles: runtime performance research (Void)

Scope: simulation data layout, update loop, spawn/death, sorting, culling, instance upload,
CPU vs GPU simulation, determinism. Authoring fields are out of scope (another agent).
Read-only research on 2026-10-22. Every claim cites `file:line` at the stated commit; anything
taken from docs or memory says so. Byte counts marked "est." are computed from field lists,
not from `sizeof`; throughput numbers marked "est." are reasoning, not measurements.

Commits read: Bevy `84e2d2c` (sparse), bevy_hanabi `77630ff`, Godot `876b290` (sparse: no
`drivers/gles3`), Heaps `b9aa6dcb`, Mach `4be8e50f`, Void particles worktree
`C:/Users/metacraft/metascript/void-wt-void2d-particles` at `3aa1ef19`.

---

## 1. References

### 1.1 Heaps (structure reference) — `h3d/parts`, `h2d/Particles`

**h3d.parts.Particles / Emitter (CPU path).**
- Storage: a doubly linked list of heap objects. `Particle` is a class with `x,y,z,w,r,g,b,a,
  frame,size,ratio,rotation,prev,next,time,lifeTimeFactor,dx..dz,fx..fz,randIndex,randValues:
  Array<Float>` (`h3d/parts/Particle.hx:3-39`). One object per particle plus its own
  `randValues` array: AoS, pointer-chasing, two allocations per particle the first time.
- Pool: dead particles go on a singly linked free list `pool` (`Particles.hx:131-138` `kill`)
  and are reused by `emitParticle` (`Particles.hx:94-106`). Spawn and kill are O(1) and keep
  order: Front/Sort/InvSort push at head, Back appends at tail (`Particles.hx:107-127`).
- Update: `Emitter.update` walks the list once (`Emitter.hx:68-97`); `updateParticle` evaluates
  each `Value` curve per particle per frame through `p.eval` (`Emitter.hx:177-205`) — a
  switch per curve per particle. Dead particles are unlinked mid-walk (`Emitter.hx:180`).
- Sort: only for `Sort`/`InvSort`. Every draw computes `w = z/w` of the particle through the
  camera matrix, 8 multiplies (`Particles.hx:161-171`), then `haxe.ds.ListSort.sort` (a linked
  list merge sort with a closure comparator, `Particles.hx:140-146`). O(n log n) every frame.
- Upload: no instancing. Every draw writes **4 vertices per particle** (`Particles.hx:290-358`,
  four repeated `p.x` writes) of 10 floats, 14 with colour (`Particles.hx:368-385`): **224 B per
  particle** with colour. A fresh buffer per frame: `Allocator.get().ofSubFloats(...)`
  (`Particles.hx:386`, `hxd/impl/Allocator.hx:54-57`), drawn with `renderQuadBuffer` and
  disposed (`Particles.hx:392-393`). One draw per `Particles` object.
- Culling: none at the particle level. Threading: none.

**h2d.Particles.** Each particle is an `h2d.SpriteBatch.BatchElement` (`h2d/Particles.hx:67`)
in the batch's doubly linked list (`h2d/SpriteBatch.hx:97-98`, `:263-280`). Per-particle update
is a virtual `update(et)` with `Math.pow` calls for speed increase and size growth
(`h2d/Particles.hx:83-138`); an `emitLoop` particle is re-initialised in place instead of being
killed (`:128-133`). `PartSortMode.Dynamic` exists but is documented as "not used anywhere"
(`h2d/Particles.hx:3-16`). Upload: `SpriteBatch.flush` writes 4 vertices × 8 floats (XY, UV,
RGBA; `hxd/BufferFormat.hx:335-337`) = **128 B per particle**, and **reuses the GPU buffer when
it is large enough** (`SpriteBatch.hx:430-441`), else disposes and recreates it.

**h3d.parts.GpuParticles (the GPU path, no compute).** Particles are closed-form: the CPU emits
a particle once with a start position, velocity, life and time offset (`GpuParticles.hx:323-441`
`emitPart`), and the vertex shader evaluates position from `time` (`PFORMAT` at `:455-463`:
position, normal (= velocity), uv, time, life, init, delta). 14 floats × 4 vertices = **224 B per
particle**, but uploaded **only when the CPU list changes**: `syncGroup` tracks the dirty index
range `firstPart..lastPart` and uploads that range alone (`:843-891`, upload at `:887-890`;
`uploadedCount` exposes it, `:489-491`). Sorting forces a full rewrite: when `sortMode != None`
the CPU recomputes each closed-form position, sorts the singly linked list with
`ListSort.sortSingleLinked`, and marks the buffer for sync (`:813-835`). Bounds are analytic
per group from emit parameters (`updateBounds`, `:271-320`). This is the one reference GPU path
that needs **no compute and no storage buffer**, so it would run on WebGL2.

### 1.2 Godot 4.5 — `CPUParticles2D/3D` and the RD GPU path

**CPUParticles3D.**
- Storage: `Vector<Particle> particles` of fixed size `amount` (`cpu_particles_3d.h:112`),
  AoS. A `Particle` holds a `Transform3D` (48 B with `real_t`=float), colour, 4 customs,
  velocity, `active`, 4 random floats, start colour, two `double` times, base colour and a seed
  (`cpu_particles_3d.h:87-103`): est. ~170 B.
- **No spawn or kill at all.** Slot `i` owns a fixed emission phase `i / amount`
  (`cpu_particles_3d.cpp:760`), jittered by `randomness_ratio` and squashed by
  `explosiveness_ratio` (`:762-775`). A slot restarts when the system clock crosses its phase
  (`:778-809`); an inactive slot is skipped (`:751-753`). So there is no free list, no
  compaction, no order change: the "pool" is the emission schedule itself.
- Upload: `_update_particle_data_buffer` writes **every slot, alive or not**, 20 floats each:
  3×4 transform, rgba, 4 customs = **80 B per slot** (`:1281-1318`); a dead slot gets a zero
  transform (`memset`, `:1299-1300`). The whole `particle_data` goes to the multimesh with
  `multimesh_set_buffer` on the render thread's `frame_pre_draw` (`:1340-1347`), guarded by a
  mutex (`:1231`, `:1343`). Cost is proportional to `amount`, not to the live count.
- Sort: `DRAW_ORDER_INDEX` writes in slot order; `LIFETIME` and `VIEW_DEPTH` fill an index
  array and sort it with `SortArray` (Godot's introsort) by `time` or by `dot(axis, origin)`
  (`:1245-1272`, comparators at `cpu_particles_3d.h:116-130`). The view-depth key is a 3-multiply
  dot along the camera's z axis, not a projection.
- Bounds: the multimesh AABB is computed by the server from the instance data; a custom AABB is
  only set to read it back (`cpu_particles_3d.cpp:561-562`).
- Threading: none in the simulation (one loop, `:747`); the only concurrency is the
  render-thread handoff.

**CPUParticles2D.** Same design; the instance is `MULTIMESH_TRANSFORM_2D` with colour and custom
(`cpu_particles_2d.cpp:80`), **16 floats = 64 B** per slot (`:1184-1192`), and `SortArray` for
lifetime order (`:1151`).

**GPUParticles (RenderingDevice).**
- Storage: one `ParticleData` per slot: `xform[16], velocity[3], active, color[4], custom[4]` =
  **96 B** (`particles_storage.h:63-69`), plus userdata.
- Process: compute shader, 64 threads per group (`particles.glsl:7`). Emission uses the same
  fixed-phase scheme as the CPU node (`particles.glsl:389-410`); sub-emitters use an atomic
  emission buffer (`:204-207`, `:343-348`).
- Sort: a separate copy pass fills `vec2(depth, index)` pairs, depth = `dot(sort_direction,
  origin)` (`particles_copy.glsl:89-90`), then `sort_effects->sort_buffer` runs a **GPU bitonic
  sort** (`particles_storage.cpp:1306`, `effects/sort.glsl:81`), then the copy pass writes
  instances through the sorted index (`particles_copy.glsl:104-106`, `:218-224`). Sorted or not,
  instances are written by the GPU into a storage buffer — impossible on WebGL2.
- Culling: the AABB is author-supplied (`gpu_particles_3d.cpp:138-140`
  `set_visibility_aabb`); `particles_get_current_aabb` reads the buffer back for the editor's
  "generate AABB" (`particles_storage.cpp:635-683`).
- The compatibility (GLES3) renderer's particle path is not in this checkout (**not read**). From
  memory it uses transform feedback; sokol has no transform feedback (no match for
  `transform_feedback` in `deps/sokol/sokol_gfx.h`), so that route is closed for Void anyway.

### 1.3 Bevy (performance reference) — sprites, instance buffers, phases

- Instance format: `SpriteInstance` = transposed 3×4 affine + colour + uv offset/scale, all f32,
  `#[repr(C)] Pod` (`bevy_sprite_render/src/render/mod.rs:378-402`): **80 B**. Void's sprite
  instance (64 B) is already smaller, because it ships a 2D affine.
- Upload: `RawBufferVec<T>` is a CPU `Vec<T>` plus a GPU buffer (`buffer_vec.rs:40-48`). Each
  frame it is `clear`ed and refilled (`sprite_render/render/mod.rs:584`), then `write_buffer`
  does **one `queue.write_buffer` of the whole live range** (`buffer_vec.rs:175-186`). The GPU
  buffer is recreated only when the count exceeds capacity (`reserve`, `:156-168`); the CPU `Vec`
  keeps its capacity across frames, so the steady state allocates nothing.
- Batching: queue → sort → prepare walks the sorted phase and extends the current batch while
  the image stays the same (`render/mod.rs:592-671`); a batch is one `draw_indexed(0..6, 0,
  range)` over instances (`:834`). Batch breaks are image changes in sort order.
- Sorting: `SortedPhaseItem::sort` defaults to `sort_unstable_by_key` (`render_phase/mod.rs:
  2195-2219`, comment: unstable is the best CPU/GPU balance; stable "if the same type is
  batched"). `Transparent2d` and `Transparent3d` override with **stable** `sort_by_key`
  (`core_2d/mod.rs:369-371`, `core_3d/mod.rs:441-443`). Sprite sort key is `FloatOrd(z)`
  (`render/mod.rs:504`). Bevy sorts **items** (one per sprite entity), never particles.
- Culling: per-entity `Aabb` maintained only on change (`bevy_sprite/src/lib.rs:102-135`
  `calculate_bounds_2d`, filters `Changed`/`AssetChanged`); the frustum test itself is in
  `bevy_camera` (**not read**, not in the sparse checkout).
- GPU preprocessing is capability-gated with a CPU fallback: "No GPU preprocessing is supported
  on WebGL because of the lack of compute shader support" (`batching/gpu_preprocessing.rs:
  107-119`); `no_gpu_preprocessing.rs:24-29` is the CPU path with the same buffer data type.
  This is the precedent for "CPU path everywhere, compute as an optional accelerator with the
  same output type".
- Parallelism: `par_iter` splits work into `thread_count * batches_per_thread` batches, clamped
  to limits (`bevy_ecs/src/batching.rs:94-106`, `query/par_iter.rs:105-117`); with one thread it
  falls back to serial (`par_iter.rs:106`).

### 1.4 bevy_hanabi (GPU particles on Bevy)

- Storage: per-effect "slices" in a shared `ParticleSlab` per particle layout
  (`render/effect_cache.rs:34-37`, `:181-191`). The particle layout is generated from the
  attributes the effect's modifiers use (`ParticleLayout`, `render/mod.rs:1956`, `:2068`): only
  the used attributes are stored. Effects in one slab are **batched into one dispatch**; a
  thread finds its effect by binary search over slab offsets (`vfx_init.wesl:41`, `:104-112`).
- Spawn/kill on GPU: a dead-index stack and an alive counter. Init pops a dead index with
  `atomicAdd(alive_count)` (`vfx_init.wesl:145-148`); update pushes a dying index with
  `atomicSub` (`vfx_update.wesl:171-183`) and appends survivors to a ping-pong indirection list
  with `atomicAdd(instance_count)` (`:184-189`), which is also the indirect draw's instance
  count. Order is therefore **nondeterministic** frame to frame (atomic append order).
- Sort: GPU merge sort of key/value pairs (moderngpu block sort, 1024 items per workgroup in
  12 kB shared memory, `vfx_sort.wesl:39-69`), used for ribbons/trails; the changelog records
  making it parallel "dramatically improves performance when using ribbon effects"
  (`CHANGELOG.md:34`). No per-particle alpha depth sort is listed among features
  (`README.md:140-200`).
- Culling: "AABB culling is not currently available. Only boolean ON/OFF visibility is used"
  (`src/asset.rs:70-71`).
- Web: compute on wasm "only through WebGPU" (`README.md:20`); no WebGL2 path.
- CPU side: the CPU computes spawn counts per spawner and uploads small per-effect params; it
  never touches particles. Its own README says it lacks "performance / usability polish"
  (`README.md:18`). **Lesson:** its mechanisms (dead stack, indirection, indirect draw) all
  require storage buffers + atomics + indirect draw, none of which WebGL2 has.

### 1.5 Mach

No particle system: no `.zig` file in `C:/Users/metacraft/projects/mach` (`4be8e50f`) mentions
"particle".

### 1.6 Unity (authoring reference) — documented vs inferred

Fetched from docs.unity3d.com on 2026-10-22; pages are not versioned in the quote, so treat them
as "current Unity 6 docs".

Documented:
- Renderer `Sort Mode`: None, By Distance, Oldest in Front, Youngest in Front, By Depth
  ("distance from the camera's near plane"). `Sorting Fudge` biases the **system** against other
  transparent objects and "does not perform sorting on individual particles within a system"
  (Manual/PartSysRendererModule). So particles sort **within** a system; systems sort as whole
  items among other transparents.
- `Enable Mesh GPU Instancing` (Mesh render mode only) needs shader target 4.5, and the system
  "writes all its instance data to a single large buffer"; it "offers a large performance boost
  compared with CPU rendering", no figures (Manual/PartSysInstancing).
- Main module: `Max Particles` cap; `Culling Mode` Automatic / Pause and Catch-up / Pause /
  Always Simulate, where catch-up "can cause performance spikes"; `Ring Buffer Mode` recycles
  the oldest when the cap is reached; `Auto Random Seed` off gives "exactly the same every time
  it is played" (Manual/PartSysMainModule). Determinism-by-seed is part of the authoring
  contract.
- Procedural mode: when every module used is in a supported subset, Unity can "know the state
  ... for any point in time" and "calculate the bounding box ... more efficiently"; a
  non-procedural system "is unpredictable" (ScriptReference/ParticleSystem-
  proceduralSimulationSupported). This is Heaps' closed-form idea promoted to an engine
  property.
- C# job access: `ParticleSystemJobData` exposes per-particle arrays — positions, velocities,
  aliveTimePercent, inverseStartLifetimes (stored as `1/lifetime`), randomSeeds, rotations,
  sizes, startColors, customData1/2, meshIndices, count (ScriptReference/ParticleSystemJobs.
  ParticleSystemJobData). Custom jobs run after the built-in update job is scheduled
  (ScriptReference/MonoBehaviour.OnParticleUpdateJobScheduled). `GetParticles` "only gets the
  particles that are currently alive" and is allocation-free with a preallocated array.
- A particle is destroyed "when the lifetime drops below zero" (Particle-remainingLifetime).

Inferred or from memory (**not documented on the pages fetched**):
- `ParticleSystemNativeArray3` holds separate `x`, `y`, `z` arrays, i.e. Unity stores particle
  state SoA per component; the doc page only says "a container to hold x, y, and z-axis data".
- Unity removes dead particles by moving the last particle into the hole (swap-remove), so
  "None" sort order is not emission order once particles die; that is why Oldest/Youngest in
  Front exist as explicit sorts. No fetched page states the order. **If the authoring agent
  needs "None == emission order", it must be confirmed in Unity itself.**
- Each particle carries a per-particle random seed (documented: `randomSeeds`) and curves "random
  between two curves" are resolved from that seed, not from a stream drawn in update order
  (inferred from the field's existence).

---

## 2. Void today (`src/void3d/particles.ms`, particles worktree at `3aa1ef19`)

### 2.1 Bytes per particle

| What | Where | Bytes |
|---|---|---|
| `Particle` struct: 3 × `Vec3` (12 B each, `math/math3d.ms:12-16`), 2 × `float64`, 4 × 32-bit, rgba, 2 × `int32` | `particles.ms:144-160` | ~96 est. (36 + 4 pad + 16 + 16 + 16 + 8) |
| per-particle random slots, 13 × `float32` | `:196`, `:329` | 52 |
| `order` + `scratch` (`int32`) + `depth` (`float32`) | `:331-338` | 12 |
| **resident per capacity slot** | | **~160 est.** |
| instance, plain (`root` + rgba) | `:197`, `:933-942` | 32 |
| instance, visual (root, shape, tile, rgba) | `:198`, `:943-955` | 64 |

All of it is sized at `create` (`:327-338`), so the steady state allocates nothing **by design**
(comment `:844`). Not verified: whether passing a `ParticleValue` by value (`:268`, `:369`,
`:379-384`) copies the `Vec<float32>` a `Poly` holds; the comment at `:444-445` says a *local*
copy would. One allocation counter around `updateEmitter` on a `Poly` curve settles it.

### 2.2 Per-frame work and what will not scale

1. **Order-keeping compaction moves whole particles** (`updateEmitter` `:793-800`,
   `moveParticle` `:751-757`): every survivor after the first death is copied, 96 B struct +
   13 scalar random copies. With `SortMode.Back` (the default, `:233`) the oldest particles sit
   at the front and die first, so in steady emission nearly **every** survivor moves **every**
   frame: ~148 B × n of copying on top of the update. At 100k that is ~15 MB/frame.
2. **Curves are interpreted per particle per frame.** `stepParticle` makes ~12 `particleValue`
   calls (`:669-727`), each a `match` on the curve kind (`:268-277`) plus a read-modify-write of
   `randomIndex`/`randomsDrawn` in the AoS struct (`:386-394`). Force and gravity are evaluated
   at the **emitter's** time (`cycle`, `:668-672`), so for a non-random curve every particle
   computes the same value: hoistable to once per frame.
3. **Colour keys** are found by a linear scan per particle (`colorAt` `:632-647`).
4. **Turbulence** calls the curl-noise `noiseDirection` per particle (`:689-697`): the most
   expensive per-particle term and the first candidate for a cheaper field or a lower rate.
5. **Depth sort** (`writeOrdered` `:906-912`, `sortByDepth` `:845-871`): depth is a full
   `vec4 × Mat4` per particle (`depthKey` `:962-966`, 16 mul) plus a second `Mat4` for local
   emitters (`placeOf` `:839-842`); the sort is a bottom-up stable merge with **indirect** key
   loads `depth[order[..]]` and a full copy-back per pass (`:868`): ⌈log2 n⌉ passes × n. At
   100k that is 17 passes of random-access loads. Heaps' key is 8 multiplies
   (`Particles.hx:166`), Godot's a 3-multiply dot along the camera axis
   (`cpu_particles_3d.h:124-129`).
6. **Visual write validates twice.** `writeOrdered` walks all particles once only to check
   finiteness (`:913-929`) and re-validates every frame tile (`:895-897`) before the write loop
   (`:930-956`) reads them again; when sorted, that loop reads the AoS through `order[i]`, i.e.
   random access.
7. **One stream, one update, one draw per emitter.** `writeStream` copies the caller's span with
   one `updateBuffer` (`void3d/draw.ms:710`), refuses a second write in a frame
   (`:706-709`, mirroring sokol's `VALIDATE_UPDATEBUF_ONCE`, `sokol_gfx.h:5199`), and has a fixed
   `instanceCapacity` (`:694`). The campfire wires one stream mesh per emitter
   (`examples/campfireScene.ms:1021-1037`). N emitters = N buffers, N uploads, N draws, and on
   WebGPU at least 256 B of uniform buffer per `sg_apply_uniforms` (VOID2D.md "Web and WebGPU").
8. **Per-particle `float64` time and life factor** (`:148-149`) exist for oracle parity with
   Heaps (VOID3D.md:383 records the measured drift with `float32`). That is 16 of the 96 bytes
   and every age update is a double op.
9. **Single-threaded**, no culling, no bounds.

What already holds and should be kept: deterministic xorshift by seed (`:162-165`, `:254-261`),
no per-frame allocation, explicit refusal of non-finite input (`:719-722`, `:921-927`), stable
sort, a capacity fixed at create.

---

## 3. Recommended runtime architecture

Summary: **one CPU simulation, SoA columns, fused or column-pass update with order-keeping
compaction, hash randoms from a per-particle seed, radix sort only when the material asks for
it, per-emitter bounds computed in the update, instances written straight into one growing
per-frame stream (void2d's sprite instance for 2D), and no compute path now.** A closed-form
vertex-shader tier (Heaps `GpuParticles`, Unity "procedural") is the only GPU tier that runs on
WebGL2, and the one worth building later.

### 3.1 Storage: SoA `Vec` columns per emitter

- Columns as `Vec<float32>` / `Vec<uint32>`, handed to passes as `Span<T>`. This is the measured
  rule in `docs/SCENE-SCALE.md` (design rule 2: "Columns are `Vec<T>`; passes take `Span<T>`";
  `Vec` 2.6x faster than `Array<T>`, a 1M sweep 0.64 ms median under load), and its line 100
  names particles as the case it was written against. Existing idiom, no new mechanism.
- Columns (3D), est. bytes: `px py pz` (12), `vx vy vz` (12), `age` normalized 0..1 (4),
  `invLife` (4), `seed` uint32 (4), `size` (4), `rotation` (4), colour 4 x f32 (16) or computed
  at write time from curves (0). By module: `dir` (12, Heaps' speed curve), angular velocity,
  frame, custom. **~44-60 B resident** against ~160 B today. 2D drops z.
- Allocate only the columns the emitter's modules use (hanabi generates its `ParticleLayout`
  from the used attributes, `render/mod.rs:1956`, `:2068`).
- Capacity fixed at create, as today (`particles.ms:327-338`) and as Unity's `Max Particles`.

### 3.2 Randoms: a per-particle seed, not 13 stored draws

One `uint32` seed per particle; the k-th random of a particle is `hash(seed, k)`. Godot does
this (`idhash(_seed)`, `cpu_particles_3d.cpp:770`), hanabi too (`pcg_hash(particle_index ^
spawner.seed)`, `vfx_update.wesl` near `:159`), and Unity exposes `randomSeeds` per particle.
It removes the 52 B random block, the lazy-draw bookkeeping (`particles.ms:386-394`) and its
compaction copies; it is stateless (chunkable, GPU-portable) and deterministic by seed.
**Decision for the person:** it breaks the Heaps draw-order parity the oracle checks
(VOID3D.md:383, `tests/oracle/particles3d.cases`), because Heaps draws from one stream in update
order. Under "authoring compatible with Unity" the per-particle seed is the Unity model; the
oracle cases would become declared divergences or be retired.

### 3.3 Update loop

- **Hoist per-frame constants.** Curves evaluated at emitter time (force, gravity,
  `particles.ms:668-672`) once per frame unless `Random`; module flags and the `match (kind)`
  once per pass, not per particle.
- **Life curves.** Keep `Const`/`Linear` exact (2 ops); bake `Pow`/`Sin`/`Cos`/`Poly` and colour
  gradients into a per-emitter LUT (e.g. 256 samples, linear interpolation) at create or on
  change. Godot samples baked curves (`curve_parameters[...]->sample`,
  `cpu_particles_3d.cpp:814-821`). This also replaces the colour-key scan (`particles.ms:632-647`).
  The LUT is still evaluated on the CPU, so the result is identical on every backend.
- **Loop shape.** One fused loop per emitter (one read and one write per column per particle)
  or several column passes (`age`, `integrate`, `size over life`), each a tight loop clang can
  vectorize. Which is faster in msc's C is a measurement, not a guess (SCENE-SCALE overturned
  its own "hoisting" rule by measuring).
- **Death and order.** Fuse compaction into the update. In SoA the update already rewrites
  every mutable column of every live particle, so writing to slot `kept` instead of `i` costs
  only the copies of read-only columns (`seed`, `invLife`, `dir`): stable order almost free,
  against ~148 B of copies per particle today. With constant life, deaths are always the oldest
  (a prefix), so a ring head kills with zero moves. Swap-remove is not recommended: O(1) per
  death, but it turns "Oldest/Youngest in Front" into a sort and drops the stable order Void's
  tests already hold.
- **Spawn.** Append at `count` (order = emission order). Shape sampling uses
  `sin/cos/acos/sqrt` (`particles.ms:540-616`), est. 50-150 ns per spawn: a 10k burst ~1 ms,
  acceptable; add a per-frame spawn budget only if measured.
- **Time precision.** Keep `float64` for emitter clocks (one per emitter). Per particle store
  normalized `age` and `invLife` in `float32` (Unity stores `1/lifetime` too) after measuring
  the death-frame drift VOID3D.md:383 found, on the new representation.

### 3.4 Sorting

- Only when the material needs it (alpha-blended + a sort mode); additive and alpha-tested
  never sort (Unity `None`; Godot `DRAW_ORDER_INDEX`, `cpu_particles_3d.cpp:1242`).
- "Oldest/Youngest in Front" are free with order-keeping storage: write forward or backward.
- View depth key: `dot(cameraForward, p)`, 3 multiplies (Godot `SortAxis`,
  `cpu_particles_3d.h:124-129`), or view-space z; not a full projection (today 16 mul,
  `particles.ms:962-966`).
- Algorithm: **LSD radix sort** of `(uint32 key, uint32 index)`, float key bit-flipped to sort
  as unsigned, 3 passes of 11 bits, two preallocated scratch arrays. O(n), stable, branch-free,
  est. 2-4 ns/particle native, 100k ~0.3 ms. Insertion sort below ~64 elements. Stability keeps
  equal depths in emission order, which the current merge sort guarantees and the tests check.
  Instances are then written by gathering SoA columns through the sorted index.
- **Temporal coherence** is worth one measurement: last frame's order is nearly sorted, so an
  insertion pass is O(n + inversions); fast cameras degrade it, radix does not.
- Across emitters: emitters are items in the existing `Phase.Alpha` list sorted by distance
  (Unity sorts systems, never particles across systems; Bevy `Transparent3d` uses a stable
  `sort_by_key`, `core_3d/mod.rs:441-443`).

### 3.5 Bounds and culling

- Fuse min/max of position into the update (6 compares per particle) and pad by the max size:
  an exact per-emitter AABB every frame at near-zero cost. Godot gets it from the multimesh
  (`cpu_particles_3d.cpp:561-562`); hanabi has none (`asset.rs:70-71`).
- Cull the emitter's **draw** against the frustum (3D) or viewport rect (2D); never per
  particle (no reference does; the GPU clips).
- Simulation culling (Unity `Culling Mode`) needs bounds while not simulating: last simulated
  bounds grown by max speed x elapsed, or author-given bounds. Cap catch-up steps (Unity warns
  "Pause and Catch-up" causes spikes).

### 3.6 Instance format and upload

**2D: reuse the void2d sprite instance, 64 B measured** (VOID2D.md "Instance sizes";
`src/void2d/instanceLayout.ms:21-32`: affine 4, origin/size 4, uv 4, colour 4 floats). Godot's
2D particle instance is the same 64 B (`cpu_particles_2d.cpp:1184-1192`). Particles write into
void2d's **one growing per-frame vertex buffer** (`src/void2d/batcher.c:23-40`, growth
`:309-321`) at the sprite instance base and batch with sprites by texture and blend. No new
pipeline, buffer or mechanism.

**3D billboards:** keep the existing 32 B plain and 64 B visual layouts. Packing visual to 48 B
(rgba `HALF4` to keep HDR, uv `USHORT4N`) is taken only on a measured upload bottleneck, the rule
VOID2D.md applied to the UI instance. **Mesh particles:** 3x4 affine + rgba = 64 B per instance
(Bevy's sprite instance is 80 B with uv, `render/mod.rs:381-386`; Godot's 3D slot 80 B).

**Upload, Bevy's pattern** (`RawBufferVec`: clear, push, one `write_buffer` of the live range,
GPU buffer recreated only on growth, `buffer_vec.rs:156-186`): write instances directly into one
staging `Vec<float32>` per frame, one shared stream buffer per layout per frame grown by void2d's
max(2x, next power of two) policy. Each emitter `sg_append_buffer`s its range and gets the offset
(`sokol_gfx.h:5540`); its draw uses `vertex_buffer_offsets`, since GLES3 has no `base_instance`.
This lifts the one-update-per-buffer-per-frame rule (`sokol_gfx.h:5199`) that forces one stream
per emitter today (`void3d/draw.ms:706-709`). Upload live particles only (Godot uploads dead
slots zeroed, `cpu_particles_3d.cpp:1299-1300`: avoid). Consecutive emitters with the same
pipeline and bindings apply uniforms once (each apply is >=256 B on WebGPU). sokol's GL path is
`glBufferSubData` into one of `SG_NUM_INFLIGHT_FRAMES` = 2 buffers (`sokol_gfx.h:12803-12838`,
`:2177`); on WebGL2 that is a JS copy, so bytes per particle cost most on the web.

### 3.7 Threading

MetaScript's std has actors (`~/.metascript/std/actor/index.cms`, Erlang-style message passing);
no shared-memory parallel-for over a `Span` was found in `~/.metascript/std`. Wasm threads also
need SharedArrayBuffer and cross-origin isolation (from memory, not verified here).
Recommendation: **single-threaded now**, structured so a split is mechanical later: emitters are
independent (parallel by emitter first); within an emitter, chunks update and compact locally
and are concatenated by a prefix sum of kept counts. Copy Bevy's batch rule when that day comes
(`bevy_ecs/src/batching.rs:94-106`: n / (threads x batches_per_thread), clamped; serial at one
thread, `query/par_iter.rs:106`). Upload stays on the render thread. A thread pool is a NEW
MECHANISM for the recompiler/runtime, not Void's to build.

### 3.8 GPU paths

1. **Compute simulation (hanabi, Godot RD): not now.** It needs storage buffers and atomics,
   which WebGL2 lacks, so WebGL2 would run the CPU path for the same effect. A compute result
   cannot be bit-identical to the CPU path (evaluation order, FMA contraction, transcendental
   precision per backend), which breaks "same pixels on every backend". sokol has no readback,
   so bounds would be author-given (Godot `visibility_aabb`, `gpu_particles_3d.cpp:138-140`).
   Bevy's precedent is a capability-gated accelerator with a CPU fallback of the same output
   type (`batching/gpu_preprocessing.rs:107-119`), which works because preprocessing is exact
   data movement; particle simulation is not. If ever built, it is a separate effect class
   (Godot's `GPUParticles` beside `CPUParticles`), not a silent accelerator, with its own
   goldens per backend.
2. **Closed-form vertex-shader tier: the GPU tier worth building later** (Heaps `GpuParticles`,
   `h3d/parts/GpuParticles.hx:455-463`, `:743-891`; Unity procedural mode). The CPU writes one
   spawn record per particle (start position, velocity, spawn time, life, seed) into a ring;
   the vertex shader computes position, size and colour from time. Runs on WebGL2 (per-instance
   attributes only), uploads only the dirty range (Heaps tracks `firstPart..lastPart`,
   `:887-890`), bounds are analytic (`updateBounds`, `:271-320`). Limits: only modules with
   closed forms (gravity, constant force, analytic drag, curves of age); no turbulence,
   collision, sub-emitters; sorting needs the CPU to evaluate positions (Heaps does,
   `:813-835`). Risk to "same pixels": shader transcendentals differ per backend; keep the
   shader polynomial + LUT texture and hold it with per-backend goldens.

### 3.9 Expected costs (estimates; the bench in 3.10 replaces them)

Basis: SCENE-SCALE's measured 1M `Vec` sweep at 0.64 ms (~0.6 ns per element per simple column
op, under load). A particle update touches ~8-12 columns with a few multiply-adds and 2-4 LUT
lookups.

| Step | Native C (est.) | wasm (est., ~1.5-2x native) |
|---|---|---|
| update, SoA, no turbulence | 3-8 ns/particle, 100k ~0.3-0.8 ms | 0.5-1.5 ms |
| update, today's AoS + compaction | est. 20-50 ns/particle; measure first | - |
| radix sort (key + index) | 2-4 ns, 100k ~0.2-0.4 ms | 0.4-0.8 ms |
| merge sort today, 100k | est. 3-8 ms (17 indirect passes + copy-back) | - |
| instance write, 64 B | 1-2 ns, 100k ~0.1-0.2 ms | 0.2-0.4 ms |
| upload 64 B x 100k = 6.4 MB/frame | driver-dependent | WebGL2 JS copy; measure |

A 2 ms CPU particle budget then carries roughly **200k-500k unsorted particles native, 100k-250k
on wasm** (est.). 1M stateful CPU particles at 60 fps is out of budget single-threaded (~5-10 ms
plus 64 MB/frame upload): that is the closed-form tier's job.

### 3.10 Measurement plan

Each scene as a headless CPU microbench (no GPU) and as a rendered run. Record per frame (median
and p90 over >=300 frames after warm-up): update, sort, instance write, upload time; bytes
uploaded; draws; `sg_apply_uniforms` calls; allocations (must be 0).

| Scene | Counts | Variants |
|---|---|---|
| 2D sprite particles, additive, one emitter | 10k / 100k / 1M | unsorted |
| 2D alpha | 10k / 100k | age order (free) vs depth radix |
| 3D billboards, additive | 10k / 100k / 1M | turbulence on/off |
| 3D billboards, alpha, view-depth sort | 10k / 100k (1M CPU only) | merge (today) vs radix vs coherent insertion |
| many emitters | 1000 x 100 | per-emitter streams (today) vs one appended stream |
| burst | 0 to 50k in one frame | spawn cost |

Backends: D3D11 native (this machine), Metal (Mac), WebGL2 and WebGPU (both wasm builds of
`scripts/build-web.sh`). Order: (1) baseline today's `particles.ms` at 10k/100k, sorted and
unsorted, CPU only, so every later number has a control; (2) SoA update + fused compaction
alone against it; (3) radix vs merge on identical keys; (4) appended stream vs per-emitter
streams on WebGPU and WebGL2. Benches run in the existing BEGIN/END quiet windows.

---

## 4. Risks and what to measure first

1. **Codegen of SoA loops in msc's C.** The design assumes `Span` column loops compile to tight,
   vectorizable C (no per-element bounds check that blocks vectorization, no DRC traffic per
   element). Measure first: one 100k update pass, SoA vs today's AoS, and read the emitted C of
   the hot loop. A per-element check or refcount op there is a compiler card, not a Void
   workaround.
2. **Hidden copies of curve values** (`ParticleValue` holding a `Vec` passed by value):
   count allocations per `updateEmitter` with a `Poly` curve.
3. **Heaps oracle parity vs Unity semantics.** Per-particle seeds and `float32` age change the
   random sequence and maybe death frames: the person's call (3.2), drift measured, not assumed.
4. **Unity's "None" order is undocumented** (1.6). If authoring parity needs it, confirm in Unity
   before choosing order-keeping vs swap-remove (this report recommends order-keeping anyway).
5. **Web upload bandwidth.** 64 B x 100k per frame through WebGL2 `bufferSubData` is the likeliest
   web bottleneck; measure before packing instances to 48 B.
6. **"Same pixels on every backend" for any GPU tier.** Shader-evaluated motion can differ per
   backend through transcendentals; a compute tier cannot match the CPU path at all.
7. **Sort cost in alpha-heavy scenes.** Today's merge sort is the largest known per-frame cost at
   100k; replace it first once measured.
8. **Many small emitters.** Per-emitter streams, uploads, draws and uniform applies dominate long
   before particle counts do; measure 1000 x 100 on WebGPU.
