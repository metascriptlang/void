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
