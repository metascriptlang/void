# Particles — design

One particle system for void2d and void3d. Authors write Unity's ParticleSystem modules, the engine
is shaped like Heaps, and performance is measured against Bevy and bevy_hanabi. Trails are part of
the system. This doc records the decisions and why they were made. Evidence lives in four research
reports, each carrying `file:line` citations into the pinned reference checkouts:

| report | owns |
|---|---|
| [PARTICLES-AUTHORING.md](PARTICLES-AUTHORING.md) | the Unity modules mapped against Heaps, Godot and void3d; `MinMaxCurve`/`MinMaxGradient`; YAML import; the velocity model; the `EmitterState` mapping |
| [PARTICLES-RUNTIME.md](PARTICLES-RUNTIME.md) | the SoA layout, hash randoms, update loop, sorting, bounds, upload, cost estimates |
| [PARTICLES-RENDER.md](PARTICLES-RENDER.md) | render modes, texture sheets, trails/ribbons, the shady kernel, GPU tiers T0–T3 |
| [PARTICLES-SIM.md](PARTICLES-SIM.md) | emission, shapes, collision, triggers, sub-emitters, forces, noise, stepping, determinism |

Reference pins (all on this machine under `~/projects`): UnityCsReference `bf60283` (sparse,
`Modules/ParticleSystem*`), heaps `b9aa6dcb`, godot `876b290` (sparse), bevy `84e2d2c` (sparse),
bevy_hanabi `77630ff`, mach `4be8e50f` (has no particles). The Unity simulation is native code and
is not in the reference. A Unity behaviour the reports mark **(mem)** comes from memory of the
manual and stays an assumption until a Unity capture measures it.

## Decisions

**Authoring is Unity's.** Each module is a struct with an `enabled` flag, and it uses Unity's field
names, defaults and enums. The only animatable types are `MinMaxCurve` and `MinMaxGradient`, with
four modes each and a stable random factor per particle. Unity's serialized names map 1:1, so a
`.prefab` importer reduces to a field rename plus a curve converter, and a Unity-style inspector
ports module for module. Why: adoption, and existing tools and UI port as they are
(AUTHORING §0, §3).

**The engine structure is Heaps'.** The caller owns the emitter, state is kept separate from the
simulation, randoms are seeded and deterministic, and a writer fills an instance stream. Heaps'
`Data.Value` vocabulary stops being an authoring type. Every curve it can express is also a Unity
curve. Unity's per-particle two-mode random cannot be expressed in Heaps' `VRandom`
(AUTHORING §0).

**Velocity follows Unity's model.** A stored velocity (`direction * startSpeed`, plus forces and
gravity) is combined with an animated velocity that is not stored. Godot uses the same model.
Heaps' `speed` curve lowers to `startSpeed` + `velocityOverLifetime.speedModifier`, which is exact
when no force acts (AUTHORING §5.3).

**One model covers 2D and 3D.** A `space2D` flag zeroes z in the integrator, following Godot's
`PARTICLE_FLAG_DISABLE_Z` (`scene/2d/gpu_particles_2d.cpp:164-166`), so there is no second type
family (AUTHORING §4). For 2D, instances go into void2d's 64 B sprite instance through a new
DrawKind. For 3D, all emitters share one stream per frame.

**`EmitterState` becomes a Heaps compatibility front end.** `fromHeaps(state)` lowers it into the
new asset. The Heaps oracle `tests/oracle/particles3d.cases` runs through that lowering
(AUTHORING §5.5). The person chose per-particle hash randoms over Heaps' single stream on
2026-10-23, for performance and the Unity ecosystem. The oracle cases that depend on Heaps'
draw order become declared divergences. The cases without randoms still prove the lowering.

**Only Unity modules are authored.** The person decided on 2026-10-23 to keep no Godot or Heaps
extras beside them, because each extra duplicates a Unity module. That decision removes
`turbulence`, `linearDamping`, `directionalSpeed`, `angleCurve` and `HeapsCone`. `fromHeaps`
lowers onto the nearest Unity module:
- Heaps' cone becomes a Unity cone with radius 0;
- the angle curve becomes angular velocity, its derivative;
- damping becomes `limitVelocity.drag`;
- Godot turbulence becomes Noise.

Where that lowering is not exact, the case is a declared divergence. As a result, the campfire and
card-table effects are re-tuned on the Unity modules and no longer match URG's turbulence.

**Gradients carry a `colorSpace`.** The importer reads it from the Unity project's colour space,
a hand-written asset defaults to Linear, and `fromHeaps` sets sRGB. The person decided this on
2026-10-23. It changes only the LUT bake.

**Runtime.** The CPU simulation stores SoA columns per emitter, about 44–60 B per particle. Each
particle carries one `uint32` seed, and its k-th random is `hash(seed, k)`; Godot and hanabi do
the same. That seed replaces the 52 B block of stored draws. Compaction happens inside the update
and keeps order. Radix sort runs only when the material sorts. Bounds are per emitter and are
computed during the update. There is no compute path for now (RUNTIME §3).

**One kernel, written once.** The appearance function `look(particle, params, lut)` is ordinary
MetaScript. On the CPU it fills void2d's instances and serves as the oracle. The shady macro emits
the same function as void3d's particle vertex shader. The emitter already gathers an entry's
helpers and runs entries on the CPU, so this needs no new emitter mechanism (RENDER §0, §B.3).
`textureSample` is refused outside fragment stages (`src/shader/emit.ms:1528`), so LUTs are read
with `textureLoad` plus a mix.

**Tiers, all on the WebGL2 floor except T2** (RENDER §B.5):

| tier | what | when |
|---|---|---|
| T0 | CPU simulation; appearance computed in the vertex shader from a 48 B state instance | first; every effect can use it |
| T1 | procedural: closed-form motion in the vertex shader; a looping emitter uploads nothing in steady state (Heaps `GpuParticles`) | automatic per emitter when every enabled module is closed-form |
| T2 | GPU-stateful simulation | only after a bench shows T0 misses the count target; the T2a/T2b choice goes to the person |
| T3 | ribbon trails over CPU point rings: Unity Trails (both modes), Heaps `Trail`, 2D | with T0 |

**Simulation.** It uses a fixed step `h = 1/60` that carries a remainder, at most 8 sub-steps, with
the frame dt clamped to 0.1. Emission uses Unity/hanabi floor carry (Heaps uses ceil). Bursts split
across a loop boundary into two spans. Collision starts with Unity Planes, then Godot's analytic
colliders (sphere, box, heightfield; capsule is an addition), then an app hook batched over
columns. Collision is swept, with one hit per step. An asset's `World` collision resolves to those
colliders, because Void has no physics. Triggers keep a bitmask of which particles are inside.
Sub-emitters spawn children in the same update: parents run first, the child seed is a hash, and a
cycle is refused when the tree is built. Orbital velocity uses Godot's exact rotation. Limit
Velocity applies drag first, then the clamp. Unity Noise uses Godot's curl source with Unity's parameters. ForceField
ships Godot's attractor plus the Unity names that map 1:1. SkinnedMesh shape waits until void3d
exposes CPU skinned positions, because sokol has no readback. The fixed 15-step order is in
SIM §6.3.

**Determinism contract.** Every column is a pure function of the asset, the seed, the per-update
inputs and the fixed step. That holds across frame rates and across native and emcc. A
cross-target column hash pins it (SIM §6.4).

## As built

The simulation lives in `src/particles/` and depends only on `src/math/math3d`. Its writers are
`src/void2d/particles2d.ms` (a TileGroup cell per particle, trails as Graphics strips) and
`src/void3d/particleWriter.ms` (ParticleVisual instances, trails as segment quads). Assets come from
code, from `importUnityPrefab` (AUTHORING §3) or from `fromHeaps`.

The Heaps-port CPU emitter (`src/void3d/particles.ms`, `particleVisual.ms`) is retired. `EmitterState` and its
value and shape types live in `src/void3d/fromHeaps.ms` as the input of `fromHeaps`; `Program.Particle`
instances are written by `writeParticlePoints` and `Program.ParticleVisual` instances by `writeParticles`
(both in `particleWriter.ms`), and the instance strides are in `gpu3d.ms` beside `VertexLayout`.

Measured facts that shaped the code:
- A dead particle's slot takes the last live particle, which then updates in that slot, as Unity
  does. Slot order is therefore not emission order, so Ribbon trails order particles by age.
- Reading a module through `const asset = sys.asset` copied the whole asset once per particle:
  497 ms per step at 100k particles. Reading in place, or through a `Borrow`, brought it to
  4.5 ms; swap-remove brought it to 2.46 ms (about 25 ns per particle; 1.83 ms with no modules
  enabled). These are light probes on Windows with clang thin-LTO, not the bench. Without LTO the
  math3d operators are not inlined across modules: 7.6 ms against 4.5 ms before swap-remove.
- `ParticleSystem` holds its asset and compiled curves by value, so creating one is stack-heavy:
  on wasm32 at `-O2`, `ParticleSystem.create` takes 27 KB of frame, `compileCurves` 25 KB and
  `ParticleSystemAsset.defaults` 14 KB. A caller that builds an asset and creates a system needs
  about 88 KB, past emscripten's 64 KB default stack, and the overflow corrupted the heap instead of
  trapping (web3d "memory access out of bounds" in a gradient's free). `src/host/gpu.wms` links
  the browser builds with a 1 MB stack, the native Windows main-thread size. Part of the frame is a
  deep copy of `compiled.value` that the compiler would move at its last read
  (`.inbox/compiler/2026-10-24-field-last-read-in-sink-copies-where-reference-moves.md`).
- The CPU bench (`tests/bench/benchParticles.ms`, docs/TESTING.md "Particle bench") on
  2026-10-23, Windows, clang thin-LTO, one run each. The machine sat at 22-30 % load from other
  sessions throughout, so these are provisional; the A/B verdict needs a window under 25 %.
  Milliseconds per step:

  | | 10k | 100k | 1M |
  |---|---|---|---|
  | update, SoA | 0.28 | 2.68 | 27.2 |
  | update, the retired AoS emitter (d76e89bd) | 0.38 | 3.91 | 38.3 |
  | sort, merge (AoS and SoA alike) | 0.56 | 8.3-9.2 | 120-199 |
  | sort, radix | 0.10 | 1.24-1.34 | 100-108 |
  | write, SoA (16 floats) | 0.10 | 0.90-1.08 | 11.4-12.7 |
  | write, AoS | 0.05 | 0.55 | 10.0 |

  The sort row is the sorted write less the unsorted one, so it holds the key, the sort and the
  gather in draw order. A probe of the radix passes alone gives 0.35 ms at 100k and 4.2 ms at
  1M, so at 1M the row is the gather: 64 MB of instances read in draw order is bound by memory
  latency, and writing rows in slot order before permuting them measured no faster. Sorted
  particles past about 100k per system are where the T2 GPU sort is first needed.

  Rerun on 2026-10-26 on main 5f6c6212 (msc f2debffda) in a quiet window: load 22-23 %, no other
  GPU, bench or WSL gate job, three runs each. Update, SoA: 0.25-0.33 / 2.53-2.85 / 25.9-27.6 ms;
  sort, radix: 0.06-0.07 / 1.09-1.12 / 101-103 ms (one run of each larger count was an outlier,
  4.4 and 142); write, SoA: 0.12-0.13 / 1.17-1.33 / 12.3-15.7 ms. The provisional rows hold: SoA
  updates 30-35 % faster than the AoS arm at 100k and 1M, which was measured only on 2026-10-23
  since it is retired. Unsorted update and write at 100k cost about 3.7 ms, so 2 ms covers about
  54k particles on one thread, a quarter to a tenth of RUNTIME §3.9's 200k-500k estimate.

Parity:
- `tests/unity/goldens` through `src/test/particleUnityCheck.ms`, with the tie cases in
  `tie_*` as counts and remaining time. Unity splits a step into `ceil(dt/0.03)` equal sub-steps
  and keeps its clock in float32; a rate spawns from a float32 carry of `rate * (t1 - t0)` per
  sub-step; a burst fires in the sub-step with `t0 <= time < t1`, its first occurrence placed at
  its time and its repeats and later cycles at the start of the sub-step; prewarm is one duration
  in `ceil(duration/0.03)` steps; a World-space spawn sits at the step end moved back by the
  emitter velocity. A particle that reaches its lifetime exactly stays alive. Still pending: four
  `tie_death` cases (life 0.1 at 60 and 120 Hz, 0.3 at 100 Hz, 1.0 at 120 Hz) where Unity removes
  a particle one frame before every float32 age or remaining chain tried does, and the three
  goldens that depend on that death (prewarm_rate10_life1, ring_pause_until_replaced_max4,
  texture_sheet_4x4_wholesheet, which also has a frame tie). `tests/unity/AgeProbe.cs` captured
  why, on 2026-10-26: Unity keeps a normalized age (the AgePercent vertex stream) and reads
  remaining as `L * (1 - age)` (680 of 682 frames bit-exact), and in all four cases its age passes
  1 a step early because it runs a few ulps ahead of `age += dt / L` (life 1.0 at 120 Hz: 0.99166733
  at step 119 against 0.9916661). The increment itself is not reproduced: against the previous
  captured age, `dt * (1 / L)` gives the next one in 488 of 682 steps and misses by one ulp
  otherwise, under no rounding, sub-step, clock or double model tried. Storing a normalized age
  in Void would not close the cases (counts 894 of 903 against 895 for seconds), so the
  seconds model stays.
- `tests/oracle/particles3d.cases` through `fromHeaps`. A case declares what it cannot match with
  `carries=`: `EmissionCeil`, `SpawnAge`, `GradientSampled`, `RandomStream` (Heaps draws from one
  stream, Void from a hash per particle) and `OneShotClock`.
- `scripts/gate3d.sh` captures. Moving the campfire's snow and embers onto the particle system
  re-baselined `m11particles_*` and re-held the 0.3.0 fingerprints of `m14forward_*` and
  `m16anchor_*`, all four frames each. Measured on main 075e0660: the scene without particles
  stayed byte-identical to `before_*`, and each particle frame differs from it in 1756 to
  1768 pixels, the snow and the embers. Emitting on Unity's float32 sub-step clock moved frames
  1 and 11 of all three again (measured on deb0fe55 over main 4e94dd3d): the scene without
  particles still byte-identical, the particle frames 1740 to 1776 pixels from it, frames 6 and
  16 unchanged.

Ceilings, each with what lifts it:
- An event sub-emitter child emits only time-0 bursts; anything else is
  `EffectErrorKind.ChildEmission`. Lifted by giving a per-event rate a meaning.
- All systems of an effect share the effect's world matrix; a child system cannot be placed apart.
- World colliders are given in the system's simulation space.
- Collision is swept with one hit per step.
- InheritColor multiplies the child's start colour by the parent's colour at the event.
- A full trail ring drops its oldest point. A ribbon that splits into sub-emitter children is
  refused (`ParticleSystemError.SplitSubEmitterRibbons`).
- 3D trails are one view-facing quad per segment, with no mitre at the joints and one colour per
  segment. Lifted by the ribbon program below.
- 2D trails are mitred strips (mitre limit 4) with no antialiasing fringe, drawn under the
  particles. The Tile and repeat texture modes need the tile to be the whole texture.
- Noise follows a curl field with Unity's parameters, not Unity's own pattern.

## New mechanisms

| item | adds | can regress |
|---|---|---|
| Ribbon neighbour taps: one instance buffer bound at four vertex slots with different offsets (three.js instanced segments) | trails with no storage buffer and no duplicated points | the shape of the vertex-buffer binding in the void3d door; a probe on every backend comes first |
| `Program` key widened by one bit (15 of 16 slots are used, `src/void3d/gpu3d.ms:46-62`) | the particle and ribbon programs | every program table: regenerate, never hand-merge |
| T2a fragment ping-pong simulation | GPU state on WebGL2 | not built; raised only if T2 is needed |

Soft particles need a scene depth texture during the alpha pass, which the forward renderer does
not produce yet. The idiom to extend is the pixel-art preset's depth-in-MRT
(`src/void3d/pixelArtRenderer.ms:118-125`). The Lights module is capped by void3d's four forward
point lights.

## Measurement plan

The cost table in RUNTIME §3.9 is an estimate: 200k–500k unsorted particles in 2 ms native,
100k–250k on wasm. The bench replaces it. Each tier is benched at 10k, 100k and 1M against today's
AoS simulation, with update, sort, write and upload timed separately, on native and emcc.

Oracles (SIM §8):
- unit oracles per module on the CPU simulation with a fixed `h`;
- frame-rate independence: byte-equal columns at frame dt 1/30 and 1/144;
- the cross-target column hash;
- the Heaps oracle through `fromHeaps`;
- the shady kernel's CPU result against the GPU result within tolerance.

Unity parity comes from capture scenes run on this machine's Unity 6000.6.6f1 through the
`unity` CLI in batch mode. They record per-module numbers that are committed as goldens together
with the Unity version. Until a formula has its capture, it is documented as "Unity-shaped".
