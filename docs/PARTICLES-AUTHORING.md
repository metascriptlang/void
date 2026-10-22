# Particles research: the authoring data model

Lane 1, authoring. Scope: what an author writes (module by module), the value types, Unity's
serialization, 2D vs 3D, and a recommended model for Void with a mapping from today's
`EmitterState`. The runtime layout and rendering are the other report's
([PARTICLES-RUNTIME.md](PARTICLES-RUNTIME.md)).

Sources and pins (read from disk unless marked):
- Unity C# reference `~/projects/UnityCsReference` @ `bf60283`. The checkout is sparse: it has
  `Modules/ParticleSystem*` but **not** `Runtime/Export` (no `AnimationCurve`, `Keyframe`,
  `Gradient`). Simulation is native C++ and not in the reference at all. Cited as
  `PSM:N` = `Modules/ParticleSystem/ScriptBindings/ParticleSystemModules.bindings.cs:N`,
  `PSS:N` = `Modules/ParticleSystem/Managed/ParticleSystemStructs.cs:N`,
  `PSE:N` = `Modules/ParticleSystem/Managed/ParticleSystemEnums.cs:N`,
  `PSR:N` = `Modules/ParticleSystem/ScriptBindings/ParticleSystemRenderer.bindings.cs:N`,
  `UI/<File>:N` = `Modules/ParticleSystemEditor/ParticleSystemModules/<File>`,
  `SMC:N` = `Modules/ParticleSystemEditor/SerializedMinMaxCurve.cs:N`,
  `SMG:N` = `Modules/ParticleSystemEditor/SerializedMinMaxGradient.cs:N`.
- Unity serialized YAML: two real prefabs fetched from GitHub with `gh api`
  (`Nanousis/MobileUIButtons SmokeParticle.prefab` blob `ad56f98`, ParticleSystem
  `serializedVersion: 8`; `MyroG/Portable-Panel ThrowablePanel.prefab` blob `5ed8b71`, for a
  burst and a `ParticleSystemRenderer`). Cited `YAML-smoke:N` / `YAML-panel:N`. Copies were not kept.
- Unity manual pages: WebFetch returned short paraphrases or 404 for most module pages. Where a
  semantic below is not in the C# and not in the YAML it is marked **(mem)**: from memory of the
  Unity manual/behaviour, not read this session. Everything (mem) about simulation order must be
  measured against a running Unity before a parity claim.
- Heaps `~/projects/heaps` @ `b9aa6dcb`: `h3d/parts/{Data,Emitter,Particles,GpuParticles}.hx`,
  `h2d/Particles.hx`. Cited `HD:N` (Data.hx), `HE:N` (Emitter.hx), `HG:N` (GpuParticles.hx),
  `H2:N` (h2d/Particles.hx).
- Godot `~/projects/godot` @ `876b290` (4.5-stable): `PPM:N` =
  `scene/resources/particle_process_material.cpp`, `PPMh:N` = its `.h`, `CP2:N` =
  `scene/2d/cpu_particles_2d.{h,cpp}`, `GP2:N` = `scene/2d/gpu_particles_2d.cpp`.
- bevy_hanabi `~/projects/bevy_hanabi` @ `77630ff`: `src/modifier/*`, `src/graph/expr.rs`,
  `src/spawn.rs`, `src/asset.rs`, `src/attributes.rs`.
- Mach `~/projects/mach` @ `4be8e50f`: **no particle system** (no `.zig` file mentions
  "particle").
- Void's port: `~/metascript/void-wt-void2d-particles` @ `3aa1ef19` (same tree as main's tip):
  `src/void3d/particles.ms` (`VP:N`), `particleNoise.ms`, `particleVisual.ms`,
  `docs/VOID3D.md` "M11 as built" (`:380-425`) and "M38 as built" (`:2533-2566`).

---

## 0. Answer first

- **Take Unity's module vocabulary and field names as the data model**, one struct per module
  with an `enabled` flag, and Unity's two value types (`MinMaxCurve`, `MinMaxGradient`) as the
  only animatable value types. Unity's serialized names (`InitialModule.startLifetime.scalar`,
  `minMaxState`, …) map 1:1 onto it, so a `.prefab` importer is a field rename plus a curve
  converter, and a Unity-style inspector can be ported module for module.
- **Keep Heaps' engine structure** (emitter as a value the caller owns, state separate from the
  simulation, deterministic seeded random, a `writeInstances` step that fills a stream) and
  **retire Heaps' `Data.Value` vocabulary** (`VLinear/VPow/VSin/VCos/VPoly/VRandom+Converge`) as
  the authoring type: every one of them is expressible as a Unity curve, but Unity's two-mode
  random (constant pair / curve pair, chosen once per particle) is not expressible in Heaps'
  `VRandom` (one draw, span shaped by `Converge`), and Heaps' `VRandom` is not expressible in
  Unity except `Converge.No`. Keep `ParticleValue` as an internal *compiled* form only if the
  runtime lane wants it.
- **The biggest conflict is the velocity model.** Heaps moves a particle by
  `direction * speed(life)` (a displacement curve, never stored) plus an accumulated force
  (`HE:187-197`); Unity stores `velocity = direction * startSpeed` at birth, accumulates forces
  and gravity into it, and adds an *animated* velocity (Velocity over Lifetime) that is not
  stored, then scales by `speedModifier` (mem). Godot is Unity's model
  (`VELOCITY` + `controlled_displacement`, `PPM:1055`). Recommendation: Unity's model;
  Heaps' `speed` curve becomes `startSpeed` + `velocityOverLifetime.speedModifier` (exact when
  forces are zero, see §5.3).
- **One model for 2D and 3D**, as Unity has (one `ParticleSystem` for both; 2D is a choice of
  shape, gravity source, collision mode and renderer sorting), with a `space2D` (Godot's
  `DISABLE_Z`) flag that zeroes z in the integrator rather than a second type family.
- **What breaks**: every `EmitterState` literal (campfire, card table, `particlesCheck.ms` 345
  tests, `particleVisualCheck.ms`, two integration tests) and the Heaps oracle
  `tests/oracle/particles3d.cases` (9 cases, 1 declared divergence) stop describing the new
  model. Proposed: keep `EmitterState` as a *Heaps-compatibility* front end compiled into the
  new model for one milestone, so the oracle keeps proving the Heaps cases, then move the tests.
  Details in §5.5.

---

## 1. Every Unity module, against Heaps, Godot and void3d

Legend. **Type**: `MMC` = `MinMaxCurve`, `MMG` = `MinMaxGradient` (both §2). **Default**: Unity's
default for a new component; `(yaml)` means seen in `YAML-smoke`, which is a saved prefab, so the
value may have been edited; `(mem)` means from memory. **YAML** is the serialized key under the
module's block, taken from the editor's `GetProperty(...)`, which reads the serialized path. The
**void3d** column describes `src/void3d/particles.ms` today as has / partial / missing.

Curve time axis. Curves on Main-module start values, Emission rates, burst counts and Shape's
animated speeds take the **system's normalized time** (`age / duration`): the editor scales that
x axis by duration (`UI/InitialModuleUI.cs:156`, `UI/ShapeModuleUI.cs:426`). Every *over Lifetime*
curve takes the **particle's normalized age**. Every *by Speed* curve takes
`clamp01((speed - range.x) / (range.y - range.x))` (mem).

### 1.1 Main (`MainModule`, PSM:22; YAML: component root + `InitialModule`)

| Field | Type | Default | YAML | Semantics |
|---|---|---|---|---|
| duration | float | 5 | `lengthInSec` (root) | one system cycle, s |
| loop | bool | true | `looping` (root) | |
| prewarm | bool | false | `prewarm` (root) | start as if one cycle already ran |
| startDelay | MMC, constants only (`UI/InitialModuleUI.cs:173`) | 0 | `startDelay` (root) | |
| startLifetime | MMC (PSM:273) | 5 (mem) | `InitialModule.startLifetime` | sampled at spawn on system time |
| startSpeed | MMC signed (PSM:340) | 5 (mem) | `startSpeed` | stored into velocity along the shape direction |
| startSize3D, startSize/X/Y/Z | bool, MMC (PSM:453-675) | false, 1 | `size3D`, `startSize`, `startSizeY`, `startSizeZ` | `startSize` is X |
| startRotation3D, startRotation/X/Y/Z | bool, MMC signed, **radians stored**, degrees shown (`UI/InitialModuleUI.cs:203-208`) | false, 0 | `rotation3D`, `startRotation` (=Z), `startRotationX/Y` | |
| flipRotation | float 0..1 (PSM:1115) | 0 | `randomizeRotationDirection` | fraction mirrored |
| startColor | MMG (PSM:1159) | white | `startColor` | `RandomColor` samples the gradient at a random t (PSS:845-860) |
| gravitySource | Physics3D/Physics2D (PSE:441) | 3D | `gravitySource` | |
| gravityModifier | MMC signed (PSM:1198) | 0 | `gravityModifier` | multiplier of global gravity |
| simulationSpace | Local/World/Custom (PSE:364) | Local | `moveWithTransform`, `moveWithCustomTransform` (root) | |
| simulationSpeed, useUnscaledTime | float, bool | 1, false | root | |
| scalingMode | Hierarchy/Local/Shape (PSE:386) | Local (mem) | `scalingMode` (root) | |
| playOnAwake | bool | true | root | |
| emitterVelocityMode, emitterVelocity | Transform/Rigidbody/Custom (PSE:429), Vector3 | Rigidbody (mem), 0 | root, `customEmitterVelocity` | feeds Inherit Velocity and rate over distance |
| maxParticles | int | 1000 (yaml) | `maxNumParticles` | live cap |
| stopAction, cullingMode | PSE:399, PSE:413 | None, Automatic | root | |
| ringBufferMode, ringBufferLoopRange | PSE:706, Vector2 | Disabled, (0,1) | root | at the cap, particles are replaced instead of dying of age |
| useAutoRandomSeed, randomSeed | bool, uint32 | true, 0 | `autoRandomSeed`, `randomSeed` | |

- **Heaps** (`HD:76-170`) has `loop`, `maxParts`, `life` (evaluated on emitter cycle time, `HE:174`),
  `globalLife` (equivalent to duration), `globalSpeed` (a Value, where Unity's simulationSpeed is a
  constant), `globalSize` (a draw-time scale with no Unity equivalent), `emitLocal` and `delay`.
  Heaps' `size`, `rotation` and `ratio` are **over-life** curves: Heaps has no separate start stage.
- **Godot** has `lifetime`, `amount`, `one_shot`, `preprocess` (seconds), `speed_scale`,
  `explosiveness` (no Unity equivalent), `randomness`, `lifetime_randomness` (`PPM:594`), `seed`,
  `fixed_fps`, `local_coords`, `initial_velocity`, `angle`, `scale`, `color` +
  `color_initial_ramp` (equivalent to Unity's `RandomColor`), and `gravity` as a **vector**.
- **void3d** is partial. It has loop, maxParts, life, size and rotation (both over life),
  `initialSpeed` (Godot-backed startSpeed, `VP:130-133`), scalar gravity along −Y (`VP:672`),
  emitLocal, globalLife, globalSpeed and a caller seed. It is missing startDelay, prewarm, startColor,
  3D size/rotation, flip, scaling mode, stopAction, culling, ring buffer and auto seed.
- **Conflict**: Heaps' `globalSpeed` curve has no field in Unity. Both evaluate the life curve on
  system time, so they agree there.

### 1.2 Emission (PSM:1603; YAML `EmissionModule`)

`rateOverTime` is an MMC on system time (PSM:1673, default 10 (mem)). `rateOverDistance` is an MMC
counting particles per unit the emitter moves (PSM:1758). `bursts[]` holds at most 8 entries
(`UI/EmissionModuleUI.cs:18`), serialized as `m_Bursts`. Each burst has `time` in **seconds**,
`count` as an MMC (`countCurve`), `cycleCount` (serialized as `m_RepeatCount = cycles-1`,
PSS:404-416), `repeatInterval` (must be > 0) and `probability` (serialized as `m_InvProbability`,
PSS:437-455).

- **Heaps** has `emitRate` (a Value on cycle time) and `bursts {time, count:Int}`, where `time` is
  **normalized cycle time** (`HE:79-81`). It has no repeat, no probability and no random count. The
  h2d particles have no rate: they keep a fixed pool of `nparts` that respawns at death
  (`H2:132-137`).
- **Godot** has `amount`/`lifetime` plus `explosiveness`, and no list of bursts.
- **hanabi** has one `SpawnerSettings {count, spawn_duration, period, cycle_count, ...}` per effect,
  with `CpuValue Single|Uniform` (`src/spawn.rs:82-92, 219`).
- **void3d** is partial: `emitRate` and Heaps-style bursts (`VP:78, 780-788`).
- **Conflict**: the **unit of burst time** (normalized vs seconds). Recommend seconds. Import from
  Heaps multiplies by `globalLife`.

### 1.3 Shape (PSM:1984; YAML `ShapeModule`)

- **Shape types** (`type`, PSE:130-179): Sphere 0, Hemisphere 2, Cone 4, Box 5, Mesh 6,
  ConeVolume 8, Circle 10, SingleSidedEdge 12, MeshRenderer 13, SkinnedMeshRenderer 14, BoxShell 15,
  BoxEdge 16, Donut 17, Rectangle 18, Sprite 19, SpriteRenderer 20. Values 1, 3, 7, 9 and 11 are
  obsolete shell variants that `radiusThickness` replaced. The default is Cone.
- **Fields**: `radius {value, mode, spread, speed}`, where mode is Random/Loop/PingPong/BurstSpread
  (PSE:692) and speed is an MMC (PSM:2382). `radiusThickness` runs from 0 (surface) to 1 (volume).
  `angle` is in degrees (25 (mem)). `length` (5) applies to ConeVolume. `boxThickness` is a Vector3.
  `arc {value (degrees, 360), mode, spread, speed}`. `donutRadius` (0.2). The shape's own transform
  is `m_Position`, `m_Rotation` (degrees) and `m_Scale`.
- **Direction and position**: `alignToDirection`, plus `randomDirectionAmount`,
  `sphericalDirectionAmount` and `randomPositionAmount`.
- **Mesh and sprite sources**: `m_Mesh*`, `placementMode` (Vertex/Edge/Triangle), `m_MeshSpawn.*`,
  `meshMaterialIndex`, `useMeshColors`, `normalOffset`, `m_Sprite`, `m_SpriteRenderer`.
- **Texture mask/tint**: `m_Texture`, clip channel and threshold, colour/alpha affect flags,
  bilinear filtering, UV channel.

Other engines:
- **Heaps** has `SLine`, `SSphere`, `SCone(radius, angle)` (angle in **radians**, default π/4,
  `HD:144`), `SDisc` and `SCustom` (`HD:20-26`), plus `emitFromShell` (thickness 0 or 1, nothing in
  between) and `randomDir`. Shape Values are evaluated per spawn on emitter time (`HE:112-138`), so a
  Heaps radius can be animated; Unity's cannot. Heaps' cone is a **spherical sector**: the spawn
  position lies along the spread direction (`HE:125-135`). Unity's cone emits from a base disc, with
  directions spread by `angle` and a volume of depth `length`. **The two shapes share a name but are
  different shapes.**
- **h2d** has Point/Cone/Box/Direction with `emitDist/emitDistY/emitStartDist/emitAngle`
  (`H2:21-37, 487-491`).
- **Godot** has Point, Sphere, SphereSurface, Box, Points, DirectedPoints and Ring (`PPMh:81-89`),
  with `direction`/`spread`/`flatness` kept separate. CPUParticles2D adds Rectangle (`CP2:70-77`).
- **hanabi** has `SetPosition{Circle,Sphere,Cone3d,Box}` with `ShapeDimension Surface|Volume`;
  velocity is set by separate modifiers.
- **void3d** is partial: Line, Sphere, Cone (Heaps' sector), Disc, Point, Box (Godot half-extents),
  Ring (Godot), plus `emitFromShell` and `randomDir` (`VP:47-76`). It is missing Unity's Cone,
  Hemisphere, Donut, Rectangle, Circle+arc, Edge, mesh/sprite/texture sources, fractional thickness,
  arc, multi-modes, the shape transform, align and the direction/position amounts.
- **Conflicts**:
  - The cone is a different shape (see above). Recommend that the name `Cone` means Unity's cone,
    and that Heaps' sector survives only as `HeapsCone` in the compatibility front end.
  - Angles are degrees in Unity and radians in Heaps.
  - Box is a scaled unit box in Unity (mem) but half-extents in void3d.
  - Godot's Ring matches neither Unity's Donut nor its Circle exactly.

### 1.4 Velocity over Lifetime (PSM:2593; YAML `VelocityModule`)

`x/y/z` are signed MMCs (PSM:2713-2829) for linear velocity that is **added but not accumulated**
(animated velocity). `space` is Local/World (`inWorldSpace`). There are also `orbitalX/Y/Z`
(PSM:3071-3217), `orbitalOffsetX/Y/Z` (PSM:3235-3251), `radial` (PSM:3334) and `speedModifier`
(PSM:3386, default 1), which multiplies speed along the direction of travel (mem). Heaps only has
`speed(life)` along the spawn direction (`HE:193-197`). Godot has directional, orbit and radial
velocity, summed into an unstored `controlled_displacement` (`PPM:1055`); this is the same split as
Unity's. hanabi uses expressions. void3d has Heaps' speed curve (`VP:686-708`). **Major conflict**,
see §5.3.

### 1.5 Limit Velocity over Lifetime (PSM:3500; YAML `ClampVelocityModule`)

Fields: `separateAxes` (`separateAxis`), `limit` (`magnitude`, PSM:3898, 1), `limitX/Y/Z`
(`x`, `y`, `z`), `space`, `dampen` (0..1, the fraction of the **excess over the limit** removed;
PSM:3984), `drag` (MMC, PSM:4086), and `multiplyDragByParticleSize` / `multiplyDragByParticleVelocity`
(true in the yaml). Heaps has none. Godot has `velocity_limit_curve`, a hard clamp of the final speed
(`PPM:1057-1060`), and `damping`, a linear loss of `damping*dt` (`PPM:993-1011`), with a quadratic
friction variant (`PPM:1000-1002`). hanabi has `LinearDragModifier`. void3d has Godot's linear
damping (`VP:736-742`). **Conflict**: Godot damping, Unity dampen and Unity drag are three different
laws. Godot's limit curve equals Unity's `limit` with `dampen = 1`. Recommend Unity's fields plus a
named, off-by-default `linearDamping` (a Godot import) for URG scenes (`VOID3D.md:2545`), rather than
hiding damping inside `drag`.

### 1.6 Inherit Velocity (PSM:4238; YAML `InheritVelocityModule`)

`mode` is Initial or Current (PSE:451, `m_Mode`); `curve` is an MMC fraction (PSM:4383, `m_Curve`).
Godot has `inherit_velocity_ratio`. Heaps and hanabi have none. void3d is **missing** it, and
`updateEmitter` has no emitter velocity (`VP:762-766`). It needs either the previous world matrix or
a caller value.

### 1.7 Lifetime by Emitter Speed (PSM:4439)

`curve` (`m_Curve`, PSM:4552) multiplies startLifetime, with `range` (`m_Range`, (0,1)). It exists
only in Unity. void3d is missing it, and it has the same dependency as 1.6.

### 1.8 Force over Lifetime (PSM:4617; YAML `ForceModule`)

`x/y/z` are signed MMCs (PSM:4692-4766), accumulated into velocity over **particle age**. There are
also `space` (`inWorldSpace`) and `randomized` (`randomizePerFrame`, which re-draws the random factor
every frame). Heaps' `force` is accumulated too, but **evaluated on emitter cycle time**
(`HE:186-191`). Godot has linear, radial and tangential accel (`PPM:565-567`) plus a gravity vector.
hanabi has `Accel`, `RadialAccel` and `TangentAccel`. void3d has Heaps' version (`VP:669-684`).
**Conflict**: the time axis. The compatibility front end keeps emitter time; the Unity model uses
age. Godot's radial and tangential accel have no Unity field: they belong in an External-Forces-like
module, or in Void-named extras.

### 1.9 Color over Lifetime (PSM:4921; YAML `ColorModule.gradient`)

An MMG (PSM:5012) that **multiplies** startColor. The UI allows only the gradient modes
(`UI/ColorModuleUI.cs:34-35`). Heaps uses rgb keys (`colors`) × a greyscale `light` Value, with
`alpha` as a separate Value (`HE:217-250`). Godot has `color_ramp`, `alpha_curve`, `emission_curve`
and `hue_variation`. hanabi has `ColorOverLifetimeModifier {gradient, blend}`. void3d has Heaps' form
(`VP:622-655, 723-725`). **Conflict**: Heaps' keys plus a piecewise-linear alpha become a Unity
gradient exactly, up to 8 keys per track. `light` × keys is piecewise-quadratic, so lowering it is
lossy. Keep `light` only in the compatibility front end.

### 1.10 Color by Speed (PSM:5020)

`color` (an MMG, `gradient`) and `range`. Only Unity has it. void3d is missing it.

### 1.11 Size over Lifetime (PSM:5166; YAML `SizeModule`)

`separateAxes`, then `size`/`x` (`curve`), `y` and `z`, all MMCs that **multiply** startSize. Heaps
has one `size` curve that is the size itself, plus `ratio` and a draw-time `globalSize*0.1`
(`HE:198-199, 273`). Godot has `scale_min/max` × `scale_curve`. hanabi has `SetSize` and
`SizeOverLifetime`. void3d has Heaps' form. **Mapping**: Heaps'
`VRandom(a, l, Converge.Start)` equals Unity's TwoCurves with min `a` and max `a + l·t` (both are
`a + l·t·r` with r drawn once), so it is **exact**. `Converge.End` is exact the same way, with
`a + l·(1−t)`.

### 1.12 Size by Speed (PSM:5675)

`separateAxes`, `x/y/z`, `range`. Godot has `scale_over_velocity` (`PPM:1131`). void3d is missing it.

### 1.13 Rotation over Lifetime (PSM:6296; YAML `RotationModule`)

`separateAxes`, then `z` (`curve`), `x` and `y`: **angular velocity**, stored in rad/s and shown in
deg/s (`UI/RotationModuleUI.cs:47-50`). Heaps' `rotation` is the **angle** over life (`HE:200`).
h2d has `rotSpeed`, `rotInit` and `rotAuto` (`H2:292-304`). Godot has both, an angle curve and an
angular velocity (`PPM:1072-1079`). void3d has Heaps' angle curve (`VP:718`). **Conflict**: angle vs
angular velocity. Converting an angle curve to an angular velocity is exact only when life is
constant. Keep Heaps' angle in the compatibility front end. Optionally add Godot's `angleOverLifetime`
as a named Void extra.

### 1.14 Rotation by Speed (PSM:6675)

`separateAxes`, `x/y/z` (angular velocity) and `range`. Only Unity has it; h2d's `rotAuto` is a
different feature. void3d is missing it.

### 1.15 External Forces (PSM:7103)

`multiplierCurve` (PSM:7227), `influenceFilter`, `influenceMask` and `influenceList`. The forces come
from scene `ParticleSystemForceField` components (shapes Sphere/Hemisphere/Cylinder/Box). Godot's
equivalent is attractor nodes (`PPM:2262`), hanabi's is `ConformToSphere`, and Heaps has none.
void3d is missing it. It needs a new scene-side force-field object; the module itself is only a
filter and a multiplier.

### 1.16 Noise (PSM:7648; YAML `NoiseModule`)

- **Strength**: `strength/Y/Z` (MMC, over life, 1) and `separateAxes`.
- **Field shape**: `frequency` (0.5), `scrollSpeed` (MMC), `damping` (bool, true), `octaves` (1),
  `octaveMultiplier` (0.5), `octaveScale` (2), and `quality` Low/Medium/High, meaning 1D/2D/3D noise
  (PSE:617).
- **Remap**: `remapEnabled`, `remap/Y/Z`.
- **Targets**: `positionAmount` (1), `rotationAmount` (0), `sizeAmount` (0).

Godot has curl-noise turbulence that **steers** the velocity direction (`PPM:1048-1053, 2288-2296`).
void3d has Godot's turbulence (`VP:95-107`). **Conflict**: the two use different algorithms and
cannot be lowered into each other. Recommend Unity's Noise as the authored module, and keep Godot's
turbulence as a separately named module (URG needs it, `VOID3D.md:2535`).

### 1.17 Collision (PSM:9586; YAML `CollisionModule`)

- **Type and targets**: `type` Planes/World and `collisionMode` 3D/2D; `m_Planes`.
- **Response**: `m_Dampen`, `m_Bounce` (1) and `m_EnergyLossOnCollision`, all MMCs without curves
  (`UI/CollisionModuleUI.cs:284-290`); `minKillSpeed`/`maxKillSpeed` (0/10000).
- **World query**: `radiusScale`, `collidesWith`, `collidesWithDynamic`, `maxCollisionShapes`
  (256), `quality`, `voxelSize` (0.5), `interiorCollisions`.
- **Outputs**: `collisionMessages`, and `colliderForce` with three multiply flags.

Heaps has `collide`, `collideKill`, `bounce` and a `Collider` that reflects the direction
(`HE:203-213`); it is unported. Godot has Disabled/Rigid/HideOnContact, friction, bounce and
use_scale against collision nodes. hanabi has kill volumes only. void3d is missing it. Planes and
kill volumes are within reach; World mode needs a collider source that Void lacks
(`VOID3D.md:424`).

### 1.18 Triggers (PSM:10372)

`inside/outside/enter/exit` each take Ignore/Kill/Callback (PSE:311). There are also
`colliderQueryMode`, `radiusScale` and `primitives`. Only Unity has this (hanabi has kill only).
void3d is missing it. A callback is an output event list.

### 1.19 Sub Emitters (PSM:11248; YAML `SubModule.subEmitters[]`)

Each entry has `{emitter, type Birth/Collision/Death/Trigger/Manual, properties
InheritColor|Size|Rotation|Lifetime|Duration, emitProbability}` (PSE:629-662). Godot has a single
sub-emitter with modes Constant/AtEnd/AtCollision/AtStart (`PPM:2303-2309`). hanabi has
`EmitSpawnEventModifier` + `InheritAttributeModifier`. Heaps has none: its `emitTrail` is a
different feature (`HE:87-88`). void3d is missing it. The child's own bursts define how much it
emits per event (mem).

### 1.20 Texture Sheet Animation (PSM:11810; YAML `UVModule`)

- **Layout**: `mode` Grid/Sprites, `tilesX/Y`, `animationType` WholeSheet/SingleRow, `rowMode`
  Custom/Random/MeshIndex, `rowIndex`.
- **Timing**: `timeMode` Lifetime/Speed/FPS; `frameOverTime` (MMC **stored as a 0..1 fraction**,
  shown in frames, `UI/UVModuleUI.cs:126-141`); `startFrame` (constants); `fps` (30);
  `speedRange`; `cycles`.
- **Other**: `uvChannelMask`, `sprites[]`, `flipU/V`.

Heaps uses a `frame` Value with `%1 × count` (`HE:254-258`). h2d uses a frame grid (`H2:326-339`).
Godot has anim speed and offset. hanabi has `FlipbookModifier`. void3d is partial (`VP:127-128,
726-731`). Heaps' wrap-around maps to Unity's `cycles`.

### 1.21 Lights (PSM:12406)

`ratio`, `randomDistribution`, `light`, `color` (bool), `range` (bool), `intensity` (bool),
`rangeCurve`, `intensityCurve` and `maxLights` (20). **YAML trap**: `range` and `intensity` are the
bools; the curves are stored under `rangeCurve`/`intensityCurve` (`UI/LightsModuleUI.cs:52-61`).
Only Unity has this module. void3d is missing it.

### 1.22 Trails (PSM:13176; YAML `TrailModule`)

- **Mode and emission**: `mode` PerParticle/Ribbon, `ratio` (1), `lifetime` (MMC), `minVertexDistance`
  (0.2), `ribbonCount` (1).
- **Texture**: `textureMode` Stretch/Tile/DistributePerSegment/RepeatPerSegment/Static,
  `textureScale`.
- **Behaviour flags**: `worldSpace`, `dieWithParticles`, `sizeAffectsWidth`, `sizeAffectsLifetime`,
  `inheritParticleColor`, `splitSubEmitterRibbons`, `attachRibbonsToTransform`.
- **Appearance**: `colorOverLifetime`, `widthOverTrail` and `colorOverTrail` (MMC/MMG),
  `generateLightingData`, `shadowBias`.

Godot has `trail_enabled/lifetime`. hanabi has ribbon attributes. Heaps has none. void3d is missing
it here; `trail.ms` is arriving with void3d-m5.

### 1.23 Custom Data (PSM:14127)

There are 2 streams (`UI/CustomDataModuleUI.cs:14`). Each has `mode` Disabled/Vector/Color, up to 4
`vector{i}_{j}` MMCs or one `color{i}` MMG, and labels. They feed renderer vertex streams. hanabi's
equivalent is `F32_0..7`. void3d is missing it. It is only useful with custom particle shaders.

### 1.24 Renderer (`ParticleSystemRenderer`, PSR:66-729)

- **Render mode**: Billboard, Stretch, HorizontalBillboard, VerticalBillboard, Mesh (up to 4 meshes
  with weights) or None.
- **Alignment and sorting**: alignment View/World/Local/Facing/Velocity; sortMode
  None/Distance/OldestInFront/YoungestInFront/Depth/DistanceReverse/DepthReverse; `sortingFudge`.
- **Size and stretch**: min/max particle size (screen fraction), `lengthScale`, `velocityScale`,
  `cameraVelocityScale`.
- **Geometry**: `normalDirection`, `pivot`, `flip`, `allowRoll`, `freeformStretching`,
  `rotateWithStretchDirection`.
- **Other**: `maskInteraction`, `trailMaterial`, GPU instancing, vertex streams (a hex byte string),
  sorting layer/order.

Heaps' `SortMode` Front/Back/Sort/InvSort (`HD:65-70`) maps onto Youngest/Oldest/Distance/
DistanceReverse. Godot has `draw_order` and `transform_align`. hanabi has `OrientModifier`. void3d
is partial. The other report covers this module in depth.

### 1.25 Coverage summary

| Module | Heaps h3d | Godot | hanabi | void3d |
|---|---|---|---|---|
| Main | partial | yes | partial | partial |
| Emission | partial | partial | partial | partial |
| Shape | sector cone etc. | 7 shapes | 4 | 7 (Heaps+Godot), Unity's missing |
| Velocity over Lifetime | speed curve | yes | expr | speed curve |
| Limit Velocity | no | clamp + damping | drag | Godot damping |
| Inherit Velocity | no | ratio | no | missing |
| Lifetime by Emitter Speed | no | no | no | missing |
| Force over Lifetime | yes (cycle time) | yes | yes | yes (Heaps) |
| Color over Lifetime | keys × light + alpha | yes | yes | yes (Heaps) |
| Color by Speed | no | no | no | missing |
| Size over Lifetime | size + ratio | yes | yes | yes (Heaps) |
| Size by Speed | no | yes | no | missing |
| Rotation over Lifetime | angle | angle + ang. vel | expr | angle |
| Rotation by Speed | no | no | no | missing |
| External Forces | no | attractors | conform | missing |
| Noise | no | turbulence | no | Godot turbulence |
| Collision | collider | yes | kill | missing |
| Triggers | no | no | kill | missing |
| Sub Emitters | no | yes | events | missing |
| Texture Sheet | frame curve | anim | flipbook | partial |
| Lights | no | no | no | missing |
| Trails | no | yes | ribbons | m5 trail.ms |
| Custom Data | no | shader | attributes | missing |
| Renderer | partial | yes | yes | partial |

---

## 2. Value types

### 2.1 Unity `MinMaxCurve`

The modes are Constant 0, Curve 1, TwoCurves 2 and TwoConstants 3 (PSE:93). A curve is serialized
as `{minMaxState, scalar, minScalar, maxCurve, minCurve}` (YAML-smoke). `scalar` serves as both the
max constant and the curve multiplier; `minScalar` is the min constant. Curves are stored
normalized: when the author switches to a curve mode, the editor moves the sign and magnitude into
the keys and the scalar (`SMC:264-273`). Evaluation (`PSS:520-533`):

```
Constant     -> scalar
TwoConstants -> lerp(minScalar, scalar, r)
Curve        -> maxCurve(t) * scalar
TwoCurves    -> lerp(minCurve(t), maxCurve(t), r) * scalar
```

`r` is a per-particle random value. It is drawn natively from the particle's `randomSeed`
(uint32, PSS:994), with a different stream per property, and stays **stable for the particle's
whole life** (mem). Force over Lifetime with `randomized` re-draws it every frame. Some fields
forbid curves (startDelay, collision, burst count is fine). The editor also offers a "procedural"
optimization that evaluates a curve of up to a few keys as a polynomial (`SMC:280-321`); this is a
runtime detail, not a different authored value.

### 2.2 Unity `MinMaxGradient`

The modes are Color 0, Gradient 1, TwoColors 2, TwoGradients 3 and RandomColor 4 (PSE:112). The
serialized fields are `{minMaxState, minColor, maxColor, maxGradient, minGradient}`.
Evaluation (`PSS:845-860`): Color gives maxColor; Gradient gives maxGradient(t); TwoColors gives
lerp(min, max, r); TwoGradients gives lerp(minG(t), maxG(t), r); RandomColor gives
maxGradient(r), sampled once.

A `Gradient` has at most 8 colour keys and at most 8 alpha keys, on **separate** time tracks. Its
mode is Blend (linear in the stored colour space) or Fixed (step), and newer versions add
PerceptualBlend (mem). Times are serialized as uint16 out of 65535.

### 2.3 `AnimationCurve`

A key is `{time, value, inSlope, outSlope, tangentMode, weightedMode, inWeight, outWeight}`.
Segments are cubic Hermite built from the slopes. When a segment is weighted, it becomes a cubic
Bezier whose handles sit at `weight × Δt` (the default weight is 1/3, which makes it equal to
Hermite). `tangentMode` is editor-only (Free/Linear/Constant/Auto/ClampedAuto, encoded in bits);
a Constant tangent is stored as an infinite slope, which makes the segment a step.
`m_PreInfinity`/`m_PostInfinity` select Clamp 2 (the default), Loop or PingPong, and particle curves
always clamp in practice. The `AnimationCurve` source is **not read** (sparse checkout), so the
weighted-Bezier solve must be checked against Unity before claiming parity. Void already has a
cubic Hermite in `src/void3d/gltfCurve.ms` (`GltfCurveMode CubicSpline`), which is the unweighted
case exactly.

### 2.4 Heaps `Data.Value` and void3d `ParticleValue`

Heaps (`HD:3-18`) has `VConst(v)`, `VLinear(start, len)`, `VPow(start, len, pow)`, `VSin/VCos(freq,
ampl, offset)`, `VPoly(values, points)`, `VRandom(start, len, converge)` and `VCustom`. Evaluation is
in `HD:185-203`. void3d ports everything except VCustom (`VP:9-35`), using 13 per-particle retained
random slots (`VP:196, 379-395`).

Mapping into Unity:
- **Exact**: VConst becomes Constant. VLinear becomes a 2-key linear Curve. VRandom with
  `Converge.No` becomes TwoConstants. VRandom with `Converge.Start/End` becomes TwoCurves (see 1.11).
- **Approximate**: VPow, VSin, VCos and VPoly become a Curve **sampled** to keys. This is lossy;
  the error is bounded by the key count, so an importer chooses N keys for a tolerance.
- **Unity → Heaps**: TwoCurves with arbitrary curves has no Heaps form, and neither does a Hermite
  key with tangents.

So Unity's set is a superset in practice, and the authoring type should be Unity's.

### 2.5 Godot and hanabi

Godot has min/max plus an optional curve texture per parameter. That equals Unity's `TwoConstants`
× curve, which Unity cannot write exactly: Unity's `TwoCurves` can express it only with two scaled
copies of the curve, which is exact. Godot draws its random values once at spawn in a fixed order
(`PPM:564-600`), the same rule as Unity. hanabi has `CpuValue Single|Uniform` for the spawner and an
expression graph for attributes (`expr.rs`). The graph is more general, but it is not an inspector
model.

### 2.6 Evaluation rules the Void model must pin

1. **The x axis per field**: system time, particle age or speed (see the top of §1).
2. **Random draws**: one stable draw per particle per property, from a per-particle seed. This
   matches the recorded divergence `particle-random-per-life` (`VOID3D.md:385`), which already
   agrees with Unity.
3. **Units**: radians internally and degrees in the editor, as Unity does. Frame values are stored
   as a 0..1 fraction. Burst times are in seconds.
4. **Gradients**: evaluated in the stored colour space. Unity blends in gamma space unless the
   project is Linear (mem). Void's `void2d/gradient.ms` (`GradientSpace`, Oklab) can hold this as a
   per-gradient space field.

---

## 3. Unity YAML serialization: can Void import it?

- **Structure**: a prefab is a stream of YAML documents `--- !u!198 &<fileID>` (198 =
  ParticleSystem, 199 = ParticleSystemRenderer), linked by `{fileID, guid, type}`. A ParticleSystem
  carries `serializedVersion` (8 in YAML-smoke). Its root holds the system-level fields listed in
  1.1, then one block per module (`InitialModule`, `ShapeModule`, `EmissionModule`, `SizeModule`,
  `RotationModule`, `ColorModule`, `UVModule`, `VelocityModule`, `InheritVelocityModule`,
  `LifetimeByEmitterSpeedModule`, `ForceModule`, `ExternalForcesModule`, `ClampVelocityModule`,
  `NoiseModule`, `SizeBySpeedModule`, `RotationBySpeedModule`, `ColorBySpeedModule`,
  `CollisionModule`, `TriggerModule`, `SubModule`, `LightsModule`, `TrailModule`,
  `CustomDataModule`). Every block is present even when its module is disabled, with `enabled: 0`.
- **Curves**: `maxCurve: serializedVersion 2, m_Curve: [{serializedVersion 3, time, value,
  inSlope, outSlope, tangentMode, weightedMode, inWeight, outWeight}], m_PreInfinity: 2,
  m_PostInfinity: 2, m_RotationOrder: 4`.
- **Gradients**: `key0..key7 {r,g,b,a}`, `ctime0..7`, `atime0..7` as uint16, `m_Mode`,
  `m_NumColorKeys`, `m_NumAlphaKeys`. Unused key slots still hold values; the counts decide.
- **Renderer** (199): `m_RenderMode`, `m_SortMode`, `m_MinParticleSize`, `m_MaxParticleSize`,
  `m_LengthScale`, `m_VelocityScale`, `m_RenderAlignment`, `m_Pivot`, `m_Flip`, `m_VertexStreams`
  (a hex byte string such as `00010304`, one byte per stream id), `m_Mesh..m_Mesh3`, `m_Materials`
  (asset guids), and sorting layer/order (YAML-panel:5481+).
- **Traps**:
  - Rotations are radians in the file.
  - `frameOverTime` is a fraction.
  - Bursts store `cycleCount`, `repeatInterval` and `probability` under those names, beside a
    `countCurve` MinMaxCurve (measured in `tests/unity/prefabs/fountain.prefab`, Unity
    6000.6.6f1). The C# bindings' `m_RepeatCount` and `m_InvProbability` (PSS:404-455) never
    reach the file.
  - The Lights `range`/`intensity` keys are bools.
  - `moveWithTransform` holds the simulation space enum: 0 Local, 1 World, 2 Custom.
  - Shape `radius`/`arc` are sub-objects.
  - Obsolete shape types 1/3/7/9/11 appear in old files and map to their base shape with
    `radiusThickness = 0`.
  - Field defaults differ per `serializedVersion`: the importer must refuse a version it was not
    written against rather than guess.

**Verdict**: an importer is a straightforward rename-and-convert, provided the Void model uses
Unity's fields: about one line per field, plus a curve converter and a gradient converter.
References (materials, meshes, sub-emitter systems, textures) need an asset map, so a first importer
can refuse what it cannot resolve. Unity's own fields are documented only by the C# bindings and the
saved files; there is no public schema.

**Built**: `importUnityPrefab` in `src/particles/unityPrefab.ms` reads version 8 only, requires
every field it maps, and returns a `PrefabError` naming the YAML path of anything the asset cannot
hold (custom simulation space, force field and trigger collider references, nested prefab
overrides, and the rest listed by the `Unsupported` sites). Its fixtures come from
`tests/unity/PrefabExport.cs` (`tests/unity/README.md`).

---

## 4. 2D vs 3D

- **Unity** uses **one** `ParticleSystem` for both. A 2D system differs only by choice: Sprite or
  SpriteRenderer or Rectangle or Circle shapes, `gravitySource = Physics2D` (PSE:441),
  `collisionMode = Collision2D` (PSE:301), the renderer's sorting layer/order and `maskInteraction`,
  and an orthographic camera. The simulation is always 3D, and 2D content lives at z = 0 with
  billboards facing the camera (mem).
- **Godot** has two node families, but `GPUParticles2D` **reuses the 3D `ParticleProcessMaterial`**
  with `DISABLE_Z` forced and default gravity (0, 98, 0) for y-down (`GP2:164-166`).
  `CPUParticles2D` is a separate class typed in `Vector2` (gravity (0, 980) y-down, `CP2 h:185`;
  direction (1, 0), `h:160`; Rectangle shape).
- **Heaps** has two unrelated implementations: `h3d.parts` (Z-up, full module set above) and
  `h2d.Particles` (a fixed looping pool, a reduced flat parameter set, y-down, `gravityAngle`,
  `H2:7-371`). They share no type.
- **hanabi** has one asset with `z_layer_2d` (`asset.rs:272-326`).
- **Void**: void3d is Y-up right-handed, void2d is y-down (h2d's convention, `void2d/draw.ms`).
  Unity is Y-up left-handed, so importing a 3D Unity system flips Z; a 2D Unity system flips Y when
  it is drawn in void2d.

**What a shared model needs**:
1. One authoring type, with `Vec3` fields everywhere.
2. A `space2D` flag (Godot's `DISABLE_Z`) that zeroes z of position, velocity and forces in the
   integrator and limits 3D-only choices: rotation becomes Z only, shapes become 2D-valid, and
   mesh render mode is refused.
3. Gravity as a **world vector supplied by the scene** (2D: +y down in void2d coordinates; 3D: −Y)
   times Unity's `gravityModifier`, so the same asset falls correctly in both.
4. Shape validation by space: a 3D-only shape (Sphere, Hemisphere, Box, Cone volume, Mesh) in a 2D
   system is an **error at authoring time**, not a silent projection.
5. Rendering split by layer: void2d draws the stream in its batcher; void3d draws billboards or
   meshes. The authoring model does not own that split.

Refuse a second 2D type family (Heaps' h2d path): it doubles every module, and Unity and Godot
both show that one material works.

---

## 5. Recommendation for Void

### 5.1 The model

`ParticleSystemAsset` is a plain struct, owned by the caller as Heaps does it. It holds:
- `main` (1.1)
- one struct per Unity module, each with `enabled` (1.2–1.23)
- `renderer` (1.24, the render report's fields)
- `space2D`
- named Void extras, each off by default: `turbulence` (Godot, URG), `limitVelocity.linearDamping`
  (Godot), and possibly `rotationOverLifetime.angleCurve` (Godot / Heaps angle)

The only animatable value types are `MinMaxCurve` and `MinMaxGradient`, with Unity's modes, Unity's
serialized field shape (`scalar`, `minScalar`, `maxCurve`, `minCurve`) and an `AnimationCurve` of
Hermite keys plus optional weights. Units match Unity's storage (radians, seconds, frame fraction),
so the importer is a rename. The editor converts to degrees and frames for display, as Unity's
inspector does.

### 5.2 Take and refuse

**Take**:
- Unity's module list, field names, defaults, enums and value types.
- Unity's per-particle seeded random and Unity's burst struct.
- Heaps' ownership and structure: emitter state separate from the simulation, deterministic seed,
  a step function, and a stream writer.
- Godot's `DISABLE_Z` trick for 2D, and Godot's turbulence and damping as named extras.
- hanabi's idea of a spawner value (`CpuValue`). It is already covered by `MinMaxCurve`
  TwoConstants.

**Refuse**:
- Heaps' `Data.Value` as an authored type (keep it only as a front-end input).
- Heaps' normalized burst times.
- Heaps' `light` multiplier and its emitter-time force axis, except in the compatibility front end.
- Heaps' `globalSize*0.1` draw scale. void3d already diverged here: `particle-size-world-units`.
- A second 2D type family.
- hanabi's expression graph as the authoring model. It is not inspector-shaped; it could later be
  the shady path for Custom Data.
- Unity's World collision and External Forces until Void has a collider and force-field source.
  Planes and kill volumes are fine.

### 5.3 The velocity model (the major conflict)

Unity integrates, per step (mem; order to be measured against Unity):

```
v_stored += (gravity * gravityModifier + force(age)) * dt      // accumulated
v_stored  = limitVelocity(v_stored) ; drag                     // Limit Velocity
v_anim    = velocityOverLifetime(age) + orbital/radial + noise * positionAmount
pos      += (v_stored + v_anim) * speedModifier(age) * dt
```

Heaps does `pos += dir * speed(t) * dt + f * dt`, where `f` accumulates force and gravity
(`HE:186-197`). With startSpeed `s0` and speedModifier `m(t)`, Unity's first term is
`dir * s0 * m(t)`. Setting `s0 = 1` and `m = speed` reproduces Heaps **exactly when there is no
force**. With forces, Unity also scales the accumulated part by `speedModifier` (mem), while Heaps
does not, so they diverge. The front end must lower Heaps' `speed` to Velocity over Lifetime
**along the spawn direction**. Unity lacks that field (its x/y/z are axis-fixed), so the lowering
has to target a dedicated compatibility term rather than `speedModifier`. Two consequences:

- Recommend the Unity order above as the authored semantics. The Heaps front end lowers `speed` to
  `startSpeed = 0` plus a compatibility term `directionalSpeed(age)` (Godot has the same thing:
  `directional_velocity`, PARAM_DIRECTIONAL_VELOCITY). This is a Godot field, so it is not a new
  mechanism.
- void3d's `initialSpeed` (Godot-backed) becomes Unity's `startSpeed` directly.

Whether `speedModifier` scales the stored velocity is the first parity question to measure in Unity.
The Unity manual text available here is ambiguous.

### 5.4 Heaps-vs-Unity conflicts and decisions

| # | Conflict | Heaps | Unity | Recommend |
|---|---|---|---|---|
| 1 | velocity | speed curve displacement | stored velocity + animated | Unity; Heaps via `directionalSpeed` (Godot) |
| 2 | force time axis | emitter cycle time (`HE:186-191`) | particle age | Unity; front end keeps cycle time by resampling only when life is constant, else keeps a `forceOnSystemTime` flag in the front end |
| 3 | burst time | normalized | seconds | seconds |
| 4 | size | one curve, no start | startSize × curve | Unity; Heaps' VRandom+Converge is exact as TwoCurves |
| 5 | rotation | angle over life | angular velocity | Unity; Heaps' angle as the `angleCurve` extra |
| 6 | colour | rgb keys × light, alpha Value | rgba gradient × startColor | Unity; `light` only in the front end (lossy otherwise) |
| 7 | random | VRandom + Converge, one draw | per-property stable draw | Unity (already matches `particle-random-per-life`) |
| 8 | cone | spherical sector, radians | base disc + angle (deg) + length | Unity's `Cone`; Heaps' sector as `HeapsCone` in the front end |
| 9 | globalSpeed | curve | constant simulationSpeed | Unity; refuse a curve here (an author can animate it from code) |
| 10 | globalSize ×0.1 | draw scale | none | refuse (already diverged) |
| 11 | sort | Front/Back/Sort/InvSort | 7 modes | Unity enum; Heaps' four map onto it |
| 12 | Value kinds | Pow/Sin/Cos/Poly | keyed Hermite | sample to keys within a stated tolerance |
| 13 | damping | (Godot in void3d) linear | dampen-above-limit + drag | Unity fields + `linearDamping` extra |
| 14 | noise | (Godot turbulence in void3d) | Unity Noise | both, as separately named modules |

### 5.5 Mapping from `EmitterState` and what breaks

`EmitterState` (`VP:111-142`) fields and where each one goes:

| EmitterState | New model |
|---|---|
| loop, maxParts | main.loop, main.maxParticles |
| globalLife | main.duration |
| globalSpeed (Value) | main.simulationSpeed if constant, else refused by the front end |
| globalSize | refused (renderer scale already in world units) |
| emitRate | emission.rateOverTime (curve on system time: same axis) |
| bursts {time, count} | emission.bursts {time × duration, count constant, cycles 1} |
| shape (Line/Sphere/Cone/Disc/Point/Box/Ring) | shape: Sphere, Circle, Box, Edge, Unity cone; Heaps cone via `HeapsCone`, Godot ring via Donut/Circle with thickness (exact for thickness 0), point = shape disabled |
| emitFromShell | shape.radiusThickness 0 / 1 |
| emitLocal | main.simulationSpace Local / World |
| randomDir | shape.randomDirectionAmount 1 |
| life | main.startLifetime |
| initialSpeed | main.startSpeed |
| speed | `directionalSpeed` (§5.3) |
| size, ratio | main.startSize 1 + sizeOverLifetime (ratio becomes separateAxes y = size·ratio, exact) |
| rotation | `angleCurve` extra |
| frame, frameCount | textureSheetAnimation.frameOverTime (fraction), tiles from the atlas |
| gravity | main.gravityModifier against a scene gravity vector of 1 along −Y |
| force | forceOverLifetime (time-axis caveat, conflict 2) |
| damping | limitVelocity.linearDamping extra |
| turbulence | turbulence extra |
| colors, light, alpha | colorOverLifetime gradient (exact without `light`; front end samples otherwise) |
| sortMode | renderer.sortMode |

**What breaks**:
- **Callers of `EmitterState`**: `src/examples/campfireScene.ms` (snow and ember states,
  `:361-394`), `src/examples/cardTableScene.ms` (flame with turbulence, `:268-292`),
  `src/test/particlesCheck.ms` (11 `EmitterState` sites; per `VOID3D.md:2563` the file holds 345
  tests over `ParticleValue`, shapes, forces and sorting), `src/test/particleVisualCheck.ms`
  (17 sites), `tests/integration/particleFade.ms:60` and `tests/integration/particleVisual.ms:75`.
  `src/test/drawCheck.ms` only imports the instance strides (`:18`), so it breaks only if the
  runtime report changes the stream layout.
- **The Heaps oracle** `tests/oracle/particles3d.cases` runs Haxe Heaps against
  `EmitterState.defaults()` literals (`:59-63`, 9 cases at `:80-173`, one declared
  `diverges=particle-random-per-life` at `:154`). It proves Heaps parity, which the Unity model does
  not have by design.

**Plan**:
1. Add the new asset and its simulation.
2. Turn `EmitterState` into the **Heaps compatibility front end**: a pure function
   `fromHeaps(state): ParticleSystemAsset` that uses the lowerings above, including the
   `directionalSpeed`, `HeapsCone`, cycle-time force and `light` compatibility terms.
3. The oracle keeps running through `fromHeaps` unchanged, so all 9 cases must stay green. That
   proves the lowering is exact for every case the oracle covers. The cases use Heaps' cone,
   constant forces (where the time axis is moot), `light` Linear and `Converge.End` size, so each
   compatibility term is exercised.
4. Move `particlesCheck.ms` value tests to `MinMaxCurve`, and keep its Heaps tests as front-end
   tests. Scenes migrate to the new asset when they are next touched.
5. Add a **Unity oracle** for the new semantics. It cannot run Unity headless here, so the honest
   form is a set of numbers recorded from a real Unity run (one prefab per module) committed as
   goldens with the Unity version. Until those exist, every "(mem)" semantic above is an
   assumption, and the docs must say so.
6. Retire the front end only when the person decides Heaps parity is no longer wanted.

### 5.6 Open questions for the person

1. **Extras.** Is it acceptable that a few Godot and Heaps fields (`turbulence`, `linearDamping`,
   `directionalSpeed`, `angleCurve`, `HeapsCone`) live beside the Unity modules as named extras?
   The alternative is dropping them and losing URG and Heaps parity.
2. **Unity ground truth.** Does the team have a Unity install to record goldens? Without one,
   simulation order and `speedModifier` stay unmeasured.
3. **Gradient blending.** Should gradients blend in sRGB like a Gamma-space Unity project, or in
   linear/Oklab? This decides whether imported colours match Unity's look.

