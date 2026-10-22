# Particles research: simulation features to implementation depth

Scope: the simulation half of a Unity-compatible particle system on Void, written for the
columnar CPU sim that `particles-research-runtime.md` fixes (SoA columns, per-particle hash
seed, CPU only). Authoring shape, module table and the §5.3 velocity model are in
`particles-research-authoring.md` and are not repeated. Rendering, trail rendering and GPU
tiers are out of scope here.

Evidence marks: `file:line` is source read in this session; (doc) is the Unity manual fetched
2026-10-22 (WebFetch gives summaries plus short quotes, so wording is close, not verbatim);
(mem) is from memory of Unity's native runtime, which is closed source and not in the C#
reference, and must be confirmed by an oracle run in Unity before it is treated as fact.

Source roots: Unity = `UnityCsReference/Modules/ParticleSystem/`; Godot =
`godot/` (4.x master); Heaps = `heaps/h3d/parts/`; hanabi = `bevy_hanabi/src/`; Void =
`void-wt-void2d-gpui/src/void3d/particles.ms` and `docs/VOID3D.md`.

---

## 0. The per-particle state the features below need

The runtime report fixes the column layout; this list is what the simulation features add to
it, so the column set is decided once.

| column | type | written by | read by |
|---|---|---|---|
| `position` | vec3 (vec2 in 2D) | integrate, collision | everything |
| `velocity` | vec3 | start speed, inherit, force, gravity, external forces, collision, limit drag | integrate |
| `animatedVelocity` | vec3, per step, not stored across steps | VoL, Noise, orbital/radial | integrate, by-speed modules |
| `age`, `lifetime` | float32 | spawn, collision lifetime loss | every over-lifetime curve |
| `startSize`, `startRotation`, `startColor` | per spawn | spawn, sub-emitter inherit | curves multiply these |
| `angularVelocity` | float32 (vec3 in 3D Rotation3D) | spawn | rotation integrate |
| `seed` | uint32 | spawn: `hash(systemSeed, spawnIndex)` or `hash(parentSeed, eventIndex)` | every random draw |
| `parentSeed` | uint32 | sub-emitter spawn | inherit-from-parent curves |
| `initialVelocity` | vec3 | spawn | InheritVelocity Initial, `m_InitialVelocity` |
| `triggerInside` | bitmask uint8 (one bit per trigger volume, cap 8) | trigger pass | Enter/Exit edges |
| `custom1`, `custom2` | vec4 each | CustomData module, app | renderer, app |
| `collided` | uint8 flag, per step | collision | turbulence skip (Godot), events |

Unity's `Particle` struct carries the same set: `m_Position, m_Velocity, m_AnimatedVelocity,
m_InitialVelocity, m_AxisOfRotation, m_Rotation, m_AngularVelocity, m_StartSize, m_StartColor,
m_RandomSeed, m_ParentRandomSeed, m_Lifetime, m_StartLifetime, m_MeshIndex,
m_EmitAccumulator0/1, m_Flags` (`Managed/ParticleSystemStructs.cs:1082-1098`). Two Unity facts
fix the velocity split: `velocity` is stored and integrated, `animatedVelocity` is recomputed
every frame by VelocityOverLifetime and Noise and never accumulates
(`ParticleSystemStructs.cs:946-956`); `totalVelocity = velocity + animatedVelocity`.
`m_EmitAccumulator0/1` are per-particle emission accumulators, used by sub-emitter Birth with
rate over distance (mem: the child's rate accumulator lives on the parent particle).

Void today stores no `animatedVelocity`: `stepParticle` (`particles.ms:~658-737`) folds speed
curve and turbulence into the integrated direction. Moving to the Unity split is a column add,
not a new mechanism (Unity's own model).

---

## 1. Main module runtime

### 1.1 Duration, looping, playback time

Reference. `duration` is the length of one cycle; `loop` restarts it. `ParticleSystem.time`
"wraps" and does not include the start delay (`ScriptBindings/ParticleSystem.bindings.cs:111-124`).
PlaybackState keeps `m_PlaybackTime`, `m_StartDelay` and `m_AccumulatedDt`
(`ParticleSystemStructs.cs:1624-1708`).

Algorithm (per emitter, per step, `dt` already scaled, §1.6):

```
if state == Stopped: return
if delayLeft > 0:
    delayLeft -= dt
    if delayLeft > 0: simulate existing particles only; return
    dt = -delayLeft          # the part of this step after the delay ends
    delayLeft = 0
t0 = time; t1 = time + dt
if t1 >= duration:
    if loop: emit over [t0, duration) then over [0, t1 - duration) as two spans; time = t1 mod duration; cycle += 1
    else:    emit over [t0, duration); time = duration; emitting = false
```

The two-span split is what makes a burst at `t = 0` fire again on every loop and a burst at
`duration - ε` fire before the wrap. Heaps uses one span and compares `at <= time && at > old`
(Void `updateEmitter`, `particles.ms:~766-800`), which misses the burst at 0 on a wrap. Void
must split (mem: Unity fires the time-0 burst every loop; Unity also re-samples
`startDelay` only at Play, not per loop).

Oracle: `duration=1, loop=true`, one burst at 0 of count 5, rate 0; step 0.3 for 10 steps;
expect alive spawns at cycles 0,1,2 (15 total) and no spawn in steps that do not cross 0.

### 1.2 Start delay and prewarm

Reference. Prewarm makes the system look as if it already simulated one full loop
(`ParticleSystemModules.bindings.cs:101`); the editor allows prewarm only on looping systems
and refuses startDelay together with prewarm, and says prewarm on a sub-emitter is unneeded
(`Editor/.../InitialModuleUI.cs:51-80`). `startDelay` is a MinMaxCurve evaluated once at Play
(mem). Godot preprocesses in fixed steps of `1/fixed_fps` (default 30), with `speed_scale` set
to 1 during the preprocess (`scene/3d/cpu_particles_3d.cpp:649-717`).

Algorithm. Prewarm = run `ceil(duration / prewarmStep)` fixed steps of `prewarmStep =
duration / n` with `n = ceil(duration * 30)` before the first visible frame, with events
(collision, trigger, sub-emitter) suppressed or not by an explicit flag. Unity (mem) runs
sub-emitter births during prewarm because the children are themselves simulated; Godot has
no sub-emitter prewarm. Recommend: prewarm runs the full step order including sub-emitters,
app callbacks off.

Refusals to keep (fail loud at asset build): `prewarm && !loop`, `prewarm && startDelay != 0`.
Both are Unity editor rules; making them errors in Void is safe and follows the reference.

Oracle: a looping rate-10 emitter with lifetime 1 and prewarm shows ~10 alive at frame 0,
same count and same positions as the non-prewarmed system after 1 s of fixed 1/30 steps
(byte-equal positions if prewarm uses the same step size).

### 1.3 Simulation space and scaling mode

Reference. `ParticleSystemSimulationSpace` Local/World/Custom
(`Managed/ParticleSystemEnums.cs:364`). `ParticleSystemScalingMode` Hierarchy/Local/Shape:
Shape scales spawn positions but not particle size or movement (`ParticleSystemEnums.cs:386`).

Algorithm.
- Local: positions and velocities live in emitter space; render applies the emitter transform.
  Gravity and world forces are rotated into local space each step (`R⁻¹ g`).
- World: spawn transforms the shape sample by the emitter world matrix at the spawn instant;
  after that no transform. Sub-step interpolation of the emitter transform between `t0` and
  `t1` per spawned particle removes the visible "clumping" of fast-moving world emitters
  (Unity does this, mem; Godot does it with `interp_to_end` in `particles.glsl:59-87`).
- Custom: World relative to another node's matrix. Recommend deferring Custom: it is World
  with a different parent matrix and needs no new state, only an API slot.
- Scaling: Hierarchy = full world scale on positions, size and velocity; Local = emitter's own
  scale only; Shape = scale applied to the shape sample only.

2D vs 3D: identical with a 2D affine (mat3) instead of mat4.

Oracle: World space, emitter moving +x at 10 u/s, rate 100, speed 0; positions of a step's
spawns must be spread over the step's x interval, not stacked at one x.

### 1.4 Emitter velocity and inherit velocity

Reference. `emitterVelocityMode` Transform/Rigidbody/Custom
(`ParticleSystemEnums.cs:429`); setting `emitterVelocity` switches the mode to Custom
(`ParticleSystemModules.bindings.cs:27-28`). InheritVelocity: mode Initial applies once at
birth, Current "applied to all particles on every frame" (doc; `ParticleSystemEnums.cs:451-458`);
for a sub-emitter the velocity comes from the parent particle
(`ParticleSystemModules.bindings.cs:4235`). Godot: `VELOCITY += EMITTER_VELOCITY *
inherit_emitter_velocity_ratio` at spawn only (`scene/resources/particle_process_material.cpp:916-918`).

Algorithm.
- `emitterVelocity` = `(pos_t1 - pos_t0) / dt` for Transform mode, app value for Custom.
  Void has no rigidbody, so Rigidbody maps to Custom with the app feeding it.
- Initial: at spawn `velocity += emitterVelocity * curve(emitterNormalizedTime)`.
- Current: each step `animatedVelocity += emitterVelocity * curve(age/lifetime)` (mem: Unity
  adds it to the animated part so it follows the emitter without accumulating). In World
  space only; in Local space Current is a no-op because local particles already move with the
  emitter.

Oracle: World, emitter at constant 5 u/s, Initial multiplier 1, speed 0, no forces; particle
x after 1 s = spawn x + 5. Current: emitter stops at t=0.5; particle stops at the same time.

### 1.5 Lifetime by emitter speed

Reference. Multiplies start lifetime by a curve sampled at the emitter speed mapped over
`range` (`ParticleSystemModules.bindings.cs:4436-4558`).

Algorithm: at spawn `lifetime *= curve(saturate((|emitterVelocity| - range.x) / (range.y -
range.x)), rand(seed, LIFETIME_BY_SPEED))`. Refuse `range.y <= range.x` at asset build.

### 1.6 Simulation speed, unscaled time, culling

Reference. `simulationSpeed` multiplies dt; `useUnscaledTime` reads unscaled delta (mem for
how it interacts with `Time.timeScale`). `cullingMode` Automatic/PauseAndCatchup/Pause/
AlwaysSimulate; Automatic is Pause for looping and AlwaysSimulate for one-shot
(`ParticleSystemEnums.cs:413`).

Algorithm. `dt = (unscaled ? appUnscaledDt : appDt) * simulationSpeed`. Culling needs the
renderer's visibility from the previous frame; PauseAndCatchup stores `pausedTime` and, when
visible again, runs one big simulate (Unity runs it as one large step, mem; Void should run it
through the fixed-step loop of §6 with a cap so a long-hidden system cannot stall a frame:
cap catch-up at `max(duration, maxLifetime)` because older state is gone anyway).

### 1.7 maxParticles, ring buffer, stop action

Reference. Reaching `maxParticles` means "Emission will be temporarily halted"
(`InitialModuleUI.cs:51-80`). `ringBufferMode` Disabled/PauseUntilReplaced/LoopUntilReplaced
(`ParticleSystemEnums.cs:706-715`): with a ring buffer, particles never die of age; at the cap
the oldest is replaced. LoopUntilReplaced loops each particle's age within `ringBufferLoopRange`
and, once it is chosen for replacement, plays from the range end to death. PlaybackState
keeps `m_RingBufferIndex` (`ParticleSystemStructs.cs:1624-1708`). `stopAction`
None/Disable/Destroy/Callback (`ParticleSystemEnums.cs:399`) fires when the system has
stopped and its last particle died.

Algorithm.
- Disabled: spawn while `count < max`; extra spawns of the step are dropped and the
  accumulator keeps only its fractional part (see §1.8 for why).
- PauseUntilReplaced: age advances until `age >= lifetime`, then clamps at `lifetime - ε`
  (alive, frozen in its final over-lifetime state). Spawn at the cap overwrites slot
  `ringIndex`, then `ringIndex = (ringIndex + 1) % max`. Because the runtime report uses
  order-keeping compaction, ring mode instead keeps a fixed-size array with no compaction and
  a write cursor; the two layouts never mix in one emitter.
- LoopUntilReplaced: `age` wraps inside `[range.x, range.y] * lifetime` until the slot's
  "replace pending" bit is set, then runs to death; the slot is then refilled.
- Stop action: emitter has `emitting == false && alive == 0 && subEmittersAlive == 0` →
  fire once. Callback is an app event on the frame's event list (§3.5), not a synchronous call
  into app code mid-step.

Oracle: ring Pause, max 4, rate 10, lifetime 0.1; after 1 s exactly 4 alive, all with age
`lifetime - ε`, and spawn order visible in slot order 0..3 rotating.

### 1.8 Emission accumulation and bursts

Reference.
- Unity PlaybackState keeps `m_ToEmitAccumulator`, `m_ParticleSpacing` (rate over distance)
  and an emission seed (`ParticleSystemStructs.cs:1624-1708`). Burst fields: time, count
  (MinMaxCurve), cycleCount (0 = infinite, `:403`), repeatInterval, probability (stored inverted,
  `:435-447`); burst time is "Time or Distance" (`:392`).
- Heaps: `emitCount += rate*et`, burst counts added in, then `while emitCount > 0 { if count <
  max spawn; emitCount -= 1 }` (`h3d/parts/Emitter.hx:68-97`; Void `particles.ms:~766-800`).
  The carry sits in `(-1, 0]`, so Heaps spawns `ceil` and goes negative: it emits early.
- hanabi: `spawn_remainder += count*ratio; n = floor(spawn_remainder); spawn_remainder -= n`
  (`spawn.rs:838-940`): floor carry, remainder in `[0, 1)`.
- Godot: fixed phase slots, particle `i` spawns at phase `i/amount` of the cycle
  (`cpu_particles_3d.cpp:719+`); no accumulator, a fixed ring.

Algorithm (recommended, Unity-shaped, floor carry as hanabi):

```
rate = rateOverTime.eval(cycleT, rand(emitSeed, step))      # curve over normalized cycle time
acc += rate * dt
acc += rateOverDistance * |emitterPos_t1 - emitterPos_t0|    # world distance moved
n = floor(acc); acc -= n
for each burst b with an occurrence in (t0, t1]:             # span-split per §1.1
    if hashUnit(emitSeed, b.index, occurrence) < b.probability:
        n_b = round(b.count.eval(...))
        spawn n_b at the burst time (ages pre-advanced by t1 - burstTime)
spawn n particles at times t0 + (k + 1 - frac) / rate ...    # sub-step placement, below
```

Sub-step placement. Each of the `n` rate spawns gets its own spawn time inside the step:
`tk = t1 - (acc_after + k) / rate` for `k = 0..n-1` (the k-th most recent). The particle is
created with `age = t1 - tk` and its position integrated by `age` with the spawn velocity
(Unity does this "pre-simulation" of fresh particles, mem; Godot does it with
`use_fractional_delta`, `particles.glsl:387-425` and `cpu_particles_3d.cpp:782`). Without it a
low-fps frame produces visible bands.

Burst repeat. Occurrence `j` of burst `b` is at `b.time + j*b.repeatInterval`, for `j <
b.cycleCount` (or unbounded if 0), within the current cycle. Probability draws are keyed on
`(b.index, cycle, j)`, never on frame count, so they are frame-rate independent.

Cap. At `count == max` the step's remaining spawns are dropped and `acc` keeps its fraction
only. Keeping the overflow in `acc` would release a flood the moment slots free, which neither
Unity (mem) nor hanabi does.

Divergence from Void today: Heaps-style `ceil` carry. Moving to floor is a change of reference
(Unity/hanabi) on the existing column; not a new mechanism. The burst comparison changes to
the span split of §1.1.

Oracle: rate 10, dt 1/60 for 60 steps; expect exactly 10 spawns, first at step 6 (acc reaches
1.0 at t=0.1, floating: assert spawn steps {6,12,...,60} ±1). Rate 7, dt 0.1: spawn counts per
step follow floor of cumulative `0.7k`: 0,1,0,1,1,0,1,0,1,1... Burst probability 0.5 with seed
42 must pick the same occurrences at dt 1/30 and dt 1/144.

### 1.9 Seeds and determinism

Reference. `randomSeed` plus `useAutoRandomSeed` (`ParticleSystem.bindings.cs:132-143`);
PlaybackState holds per-module Seed4 streams (Initial, Shape, Force, Collision, Emission;
`ParticleSystemStructs.cs:1624-1708`); each particle carries `m_RandomSeed`. Godot:
`seed + 1 + i + cycle` hashed (`cpu_particles_3d.cpp:627-647, 719+`). hanabi: pcg seeded per
particle (`render/vfx_update.wgsl:140-190`).

Algorithm. Every random draw is `hashUnit(particle.seed, MODULE_SALT, k)`, a pure function,
not a stream. That gives: per-particle curves "random between two curves" stable over life
(Unity uses one value per particle per module, mem, which is what `m_RandomSeed` exists for);
frame-rate independence; and order independence, which the event pass of §3 relies on.
Per-step draws that Unity re-picks each frame (Force `randomized`, "picks a new random each
frame", `ParticleSystemModules.bindings.cs:4876`) key on `(seed, salt, stepIndex)`, which is
only frame-rate independent under the fixed step of §6. The emitter-level stream is
`hash(systemSeed, cycle, ...)`; spawn index `s` gets `seed = hash(systemSeed, s)` with `s` a
monotonic 64-bit counter per emitter.

The runtime report already chose a hash seed; this section only adds the salt-per-module rule
and the key for per-step draws.

---

## 2. Shape module

### 2.1 Shapes

Reference. `ShapeModule` (`ParticleSystemModules.bindings.cs:1984`), editor in
`Editor/.../ShapeModuleUI.cs:219-327`, manual (doc). Unity list: Sphere, Hemisphere, Cone
(emit from Base or Volume), Box (Volume/Shell/Edge), Mesh/MeshRenderer/SkinnedMeshRenderer
(Vertex/Edge/Triangle), Sprite/SpriteRenderer, Circle, SingleSidedEdge (line), Donut,
Rectangle. Each has a position/rotation/scale transform. Godot: point, sphere, sphere surface,
box, points (texture), directed points, ring (`cpu_particles_3d.cpp:719+`). Void today: the
Godot set plus the Heaps cone (`docs/VOID3D.md:2533-2566`).

Algorithm (sample = position + direction):

| shape | position | direction |
|---|---|---|
| Sphere r, thickness t | `dir = randUnitSphere; rad = r * cbrt(lerp((1-t)^3, 1, u))` | `dir` |
| Hemisphere | Sphere with `dir.z = |dir.z|` (z-up local) | `dir` |
| Circle r, arc | `θ = arc sample; rad = r*sqrt(lerp((1-t)^2,1,u))` in XY | radial |
| Cone angle α, radius r, length L | base point as Circle; | `normalize(lerp(Z, radial, sin α))`; Volume: position `+= dir * L * u` |
| Donut R, r | center on circle R at θ, then point in tube r | from tube center |
| Box | Volume: uniform; Shell: pick face by area then uniform; Edge: pick edge by length | local +Z (Unity default) |
| Rectangle | uniform in XY | +Z |
| Edge (line) | `lerp(-L/2, L/2, arc sample)` on X | +Y |
| Mesh | vertex/edge/triangle by area with `m_ShapeMeshIndex` modes | interpolated normal |
| Sprite | triangle by area of the sprite mesh | sprite normal |

The thickness formulas give uniform density in the shell (cube root in 3D, square root in
2D). Unity's `radiusThickness` 0 = surface, 1 = full volume (doc).

Mesh, SkinnedMesh and Sprite shapes need the app's mesh data on the CPU each step for
skinned meshes. Recommend: Mesh and Sprite from a static CPU-side triangle list (an asset
reference), SkinnedMesh deferred until void3d skinning exposes CPU-side bone matrices; flag it
as a dependency, not a new mechanism.

2D vs 3D. void2d gets Circle, Edge, Rectangle, Donut-as-ring, Sprite; the 3D shapes collapse to
their XY slice (Sphere → Circle, Box → Rectangle, Cone → 2D arc of angle α). Direction in 2D
is a vec2.

### 2.2 Arc modes

Reference. Arc mode Random/Loop/PingPong/BurstSpread with `spread` and `speed`
(`ParticleSystemEnums.cs:692-701`, `ShapeModuleUI.cs`, doc). Spread quantizes: 0.1 gives
positions at 10% steps (doc). Speed applies only to Loop and PingPong (doc). Radius has the
same mode set for Circle/Cone/Edge. PlaybackState keeps the arc and radius timers with their
previous values (`ParticleSystemStructs.cs:1624-1708`).

Algorithm, one function used for arc angle and for radius:

```
u = match mode:
    Random:      hashUnit(seed, SHAPE_ARC)
    Loop:        fract(timerAt(spawnTime) )                      # timer += speed * dt / 1, per emitter
    PingPong:    pingpong(timerAt(spawnTime))                    # 1 - |fract(x/2)*2 - 1|
    BurstSpread: (k + 0.5?) / nInBurst  for the k-th particle of this burst or step
if spread > 0: u = floor(u / spread) * spread
angle = u * arc
```

`timerAt(spawnTime)` interpolates between the stored previous and current timer value by the
spawn's sub-step fraction (that is why Unity stores prev; mem). BurstSpread's exact centering
(`k / n` vs `(k+0.5)/n`) is (mem) and needs an oracle in Unity: emit a burst of 4 on a 360°
circle and read the angles.

### 2.3 Direction and position options

Reference (doc, `ShapeModuleUI.cs:219-327`): `alignToDirection` (orient particle along the
start direction), `randomDirectionAmount` (blend toward a random direction),
`sphericalDirectionAmount` (blend toward the direction from the shape center),
`randomPositionAmount` (offset the position randomly in a cube of that size).

Algorithm, in this order (mem for order; doc for each):

```
dir = shapeDir
dir = normalize(lerp(dir, normalize(pos - shapeCenter), spherize))
dir = normalize(lerp(dir, randUnitSphere(seed, SHAPE_DIR), randomize))
pos += (randUnitCube(seed, SHAPE_POS) * 2 - 1) * randomPosition
if align: startRotation3D = lookRotation(dir) composed with startRotation
velocity = dir * startSpeed
```

Oracle: Cone α=0, randomize=1 gives a uniform direction histogram over the sphere (chi-square
on 12 bins over 10k samples); spherize=1 on a Box gives `dir == normalize(pos)`.

---

## 3. Collision

### 3.1 Reference semantics

Unity (`ParticleSystemModules.bindings.cs:9586`, `ParticleSystemEnums.cs:64,291,301`,
`CollisionModuleUI.cs:53-75`, doc):
- `type` Planes or World; `mode` 3D or 2D.
- Planes: a list of transforms; the plane is the transform's XZ plane with its Y axis as the
  normal (`CollisionModuleUI.cs:53-75`). Planes are infinite.
- World: High quality queries physics every frame; Medium and Low use a voxel cache for static
  colliders and particles may leak through (doc; quality enum at
  `ParticleSystemEnums.cs:64`, `quality` at `bindings.cs:10150`).
- `dampen`: fraction of speed lost per collision; `bounce`: scales the component along the
  normal; `lifetimeLoss`: fraction of *start* lifetime lost per collision
  (`CollisionModuleUI.cs:53-75`). All three are MinMaxCurves evaluated at age (mem: per
  particle random from `m_RandomSeed`).
- `minKillSpeed`, `maxKillSpeed`: applied after the collision response
  (`CollisionModuleUI.cs`).
- `radiusScale` scales the particle size used as the collision radius
  (`bindings.cs:10155`).
- `enableInteriorCollisions` (World only, `bindings.cs:10366-10369`).
- `colliderForce` with `multiplyColliderForceByCollisionAngle / ByParticleSpeed / BySize`
  pushes the hit rigidbody (`bindings.cs:10263-10276`).
- `sendCollisionMessages` turns on `OnParticleCollision`; events are read with
  `GetCollisionEvents`, each with intersection, normal and velocity in world space plus the
  collider (`ParticleSystemStructs.cs:1804-1825`; `ParticleSystem.bindings.cs:1702-1711`).
- `maxCollisionShapes`, `collidesWith` layer mask: World only.

Godot (GPU) (`servers/rendering/renderer_rd/shaders/particles.glsl:~540-670`;
`particle_process_material.cpp:1013-1024`):
- Collider kinds: sphere, box, SDF (baked 3D texture), heightfield, and 2D SDF
  (`particles.glsl:42-47, 503-540`). Each yields `depth, normal`; several contacts combine as
  `c += normal * max(0, depth - dot(normal, c))`; the summed vector `c` gives depth and normal
  after.
- Response RIGID: `r = dot(N, V); slide = step(2 / clamp(b + 1, 1, 2), |r|); pos += N*depth;
  V -= N*r; V = mix(V, 0, friction); V -= N*r*(bounce*slide)`. The `slide` step stops bouncing
  when the normal speed is below a threshold so resting particles settle. HIDE_ON_CONTACT kills.
- Turbulence is skipped on a collided particle that step.
- Collision runs after force and damping and before integrate, as a position correction
  (`pos += N*depth`).

Heaps (`h3d/parts/Collider.hx:3-7`, `Emitter.hx:177-213`, `Data.hx:116-125`): an app
interface `collidePart(p, normal):Bool`; the emitter calls it after the move; on hit either
kill (`collideKill`) or reflect the direction times `bounce`. Void ported none of it
(`docs/VOID3D.md:380-425, 2533-2566`).

hanabi: `KillSphereModifier`, `KillAabbModifier`, `ConformToSphereModifier` only
(`modifier/force.rs:70-250`); no response collision.

### 3.2 What Void builds

Void has no physics engine, so Unity's World type cannot be honoured as Unity defines it
("collide with the scene's colliders"). The recommendation, in reference order:

1. Planes, exactly as Unity (infinite planes from node transforms). No new mechanism.
2. Analytic colliders: sphere, box (inside and outside), capsule, heightfield, as Godot's
   collider nodes, listed on the emitter or found by a layer mask in the scene. Godot's
   mechanism; the capsule is the one shape neither has, and it is a sphere-swept segment with
   the same depth/normal contract, so it is an addition inside the existing contract, not a
   mechanism.
3. An app hook in the Heaps form for everything else (the app's physics, a tilemap):
   `collide(positions, radii, velocities, count) -> writes (depth, normal, colliderId) per hit`
   as a batch call over the column range, once per step, not a per-particle virtual call.
   Batch is the columnar form of Heaps's `collidePart`.

Unity World type maps to (2)+(3): Void collides with "the world" the app describes. Calling
that "World" in the asset would claim Unity semantics Void does not have; recommend the asset
field accepts `World` and resolves it to the colliders on the layer mask plus the hook, with
the doc saying so. Medium/Low voxel cache: refuse or ignore; it is a quality knob for Unity's
physics cost, meaningless without it. SDF collision (Godot's baked SDF) is a NEW MECHANISM for
Void (needs an SDF bake), defer.

### 3.3 Algorithm (one step, CPU, columnar)

Swept test against the step's motion, so fast particles do not tunnel through thin planes:

```
for i in alive:
    p0 = pos[i]; v = velocity[i] + animatedVelocity[i]
    p1 = p0 + v * dt
    r  = size[i] * 0.5 * radiusScale
    best = none
    for each plane (n, d):                       # n·x = d
        s0 = dot(n, p0) - d - r; s1 = dot(n, p1) - d - r
        if s0 >= 0 and s1 < 0: tHit = s0 / (s0 - s1); keep the smallest tHit
        # interior: if !twoSided and s0 < 0: no collision (Unity planes are one-sided, mem)
    for each analytic collider: same (sphere/box/capsule use ray-vs-inflated-shape)
    for hook results: depth, normal from the app (no tHit; treat as tHit = 1)
    if best:
        p = lerp(p0, p1, tHit) + n * ε
        vn = dot(n, velocity[i]) * n; vt = velocity[i] - vn
        velocity[i] = (vt - vn * bounce) * (1 - dampen)
        lifetime[i] -= lifetimeLoss * startLifetime[i]
        speed = |velocity[i]|
        if speed < minKillSpeed or speed > maxKillSpeed: kill
        pos[i] = p + velocity[i] * (1 - tHit) * dt   # spend the rest of the step
        collidedFlag[i] = 1
        if sendEvents: push CollisionEvent(i, p, n, velocity, colliderId)
        if subEmitter[Collision]: push SubEmitEvent(Collision, i, ...)
    else:
        pos[i] = p1
```

Notes.
- Unity's exact `bounce`/`dampen` formula is (mem): the manual says bounce scales motion along
  the normal and dampen is the fraction of speed lost (`CollisionModuleUI.cs:53-75`). The form
  above is the plain reading: normal component scaled by bounce, then the whole velocity by
  `1 - dampen`. It is the first thing to confirm with a Unity oracle.
- Only `velocity` is reflected; `animatedVelocity` is recomputed next step by its module, so a
  VoL-driven particle keeps pushing into a plane. Unity has the same behaviour (mem: particles
  with strong VoL slide along or leak through planes); keep it, and document it.
- One hit per particle per step (smallest `tHit`). Godot instead sums all contact depths for a
  position push. The swept single hit is enough for planes and convex shapes and is
  deterministic; corner cases (two planes in one step) resolve on the next step.
- Resting contact: apply Godot's `slide` rule: if `|dot(n, v)| < restThreshold` the normal
  component is zeroed instead of bounced, so particles settle instead of jittering. Unity has
  no documented equivalent (mem: Unity particles jitter or sink at very low bounce); this is a
  Godot mechanism borrowed, not invented.

2D vs 3D. Unity `mode` 2D collides with Physics2D in the XY plane. Void2d: planes become lines
(normal vec2), colliders circle/box/capsule/tilemap-hook; the same code on vec2. 2D is the same
algorithm in the plane, not a second implementation if the column math is written over a
dimension parameter.

### 3.4 App API

- Asset: `collision { kind: Planes | World, planes: [NodeRef], dampen, bounce, lifetimeLoss,
  minKillSpeed, maxKillSpeed, radiusScale, sendEvents, layerMask }`.
- Runtime: `emitter.colliderHook = (batch) => void`, and collider nodes
  `ParticleCollider{Sphere|Box|Capsule|Heightfield}` with a layer.
- Events: `emitter.collisionEvents(): Span<CollisionEvent>` valid until the next update (Unity's
  `GetCollisionEvents` is pull, not push). An `onParticleCollision` callback is a convenience
  Neon may add on top; Void exposes the buffer.

### 3.5 Oracle

1. Plane y=0 normal up, particle at y=1 with v=(0,-10,0), dt=1/60, bounce=1, dampen=0, size 0:
   after 0.15 s the particle is above the plane, v.y = +10 exactly at hit step, energy kept.
2. Same with dt=0.2 (tunnel case): one step crosses the plane; result must equal (1) at
   matched times within 1e-5 (sweep correctness).
3. lifetimeLoss=0.5, startLifetime 2: after two hits the particle is dead.
4. minKillSpeed=5, bounce 0.3, start 10: dies on the first hit (speed after = 3).
5. Unity cross-check (to run on a machine with Unity): same scene, record positions per frame
   with `GetParticles` at fixed dt; compare to tolerance 1e-3.

### 3.6 Triggers

Reference. Trigger module (`bindings.cs:10372`; `ParticleSystemEnums.cs:311, 323, 463`;
`TriggerModuleUI.cs:31-36`; doc): a list of colliders; four event types Inside, Outside, Enter,
Exit, each with OverlapAction Ignore/Kill/Callback. Inside and Outside act every frame;
Enter/Exit once on the crossing frame (`bindings.cs:10496, 10616`; `TriggerModuleUI.cs:31-36`).
Callback adds the particle to a list read in `OnParticleTrigger` with
`GetTriggerParticles(type, list)`; the script may modify and write back with
`SetTriggerParticles` (`ParticleSystem.bindings.cs:1726-1780`). `colliderQueryMode`
Disabled/One/All reports which collider (`bindings.cs:10974`). `radiusScale` as in collision.

Algorithm (after integrate, §6 step order):

```
for i in alive:
    insideNow = 0
    for k, vol in triggers:          # k < 8
        if overlap(pos[i], radius[i], vol): insideNow |= 1 << k
    entered = insideNow & ~triggerInside[i]; exited = triggerInside[i] & ~insideNow
    for event e in (Enter: entered, Exit: exited, Inside: insideNow, Outside: ~insideNow & mask):
        if mask(e) != 0: apply action(e): Kill → mark dead; Callback → append i to list(e)
    triggerInside[i] = insideNow
    if Enter/Inside etc. has sub-emitter Trigger: push SubEmitEvent(Trigger, i)
```

A newly spawned particle starts with `triggerInside = 0` (mem: Unity fires Enter on a particle
born inside; confirm with an oracle). Callback edits by the app: the lists hold indices into
the alive columns; the app writes columns through a span; Void applies writes before the
compaction of the step. That is Unity's Get/Set pair in columnar form, no new mechanism.

Oracle: sphere trigger at origin r=1, particle moving through on x from -2 to 2 at 1 u/s,
dt=0.1: Enter at exactly the step crossing x=-1, Exit at x=1, Inside on each step between.

---

## 4. Sub-emitters

### 4.1 Reference semantics

Unity (`bindings.cs:11248`, `ParticleSystemEnums.cs:629-661`, doc,
`SubModuleUI.cs:150-228`, `ParticleSystemEditor.bindings.cs:50`):
- Types Birth, Collision, Death, Trigger, Manual. Birth emits across the parent particle's life
  using the child's full emission settings (rate, distance, bursts); Collision, Death, Trigger,
  Manual support only a single burst (doc): the child's bursts at time 0 run once per event.
- Properties bitmask: InheritNothing, Color (multiplies), Size (multiplies), Rotation (adds),
  Lifetime (a shorter lifespan the closer the parent is to death), Duration (the parent's
  duration and age drive the child's MainModule curves) (`ParticleSystemEnums.cs:646-661`).
- Probability `0..1` per sub-emitter entry (`bindings.cs:11705`), emit-or-not per event.
- Inherit velocity for children comes from the parent particle, through the child's
  InheritVelocity module (`bindings.cs:4235`).
- `TriggerSubEmitter(index, particle(s))` for Manual (`ParticleSystem.bindings.cs:1495-1575`).
- Circular references are refused when assigned; a sub-emitter must be a descendant of the
  root system (`SubModuleUI.cs:150-185, 228`; `ParticleSystemEditor.bindings.cs:50`
  `CheckCircularReferences`).
- A sub-emitter's own sub-emitters run (nesting allowed), with prewarm unneeded.

Godot (`particle_process_material.cpp:1149-1183`, `particles.glsl:~208-229, 342-385`):
- Modes Constant (every `1/frequency` s, with `interval_rem`), AtEnd (fires when the parent
  dies this step: `age > lifetime - DELTA`), AtCollision, AtStart (just spawned).
- `amount_at_end/at_collision/at_start` counts; `keep_velocity`.
- Mechanism: the parent writes requests into an emission buffer with `atomicAdd`; past the
  child's `particle_max` the request is refused; flags POSITION | ROT_SCALE, plus VELOCITY with
  keep_velocity; colour and custom are zero. The child consumes the buffer next frame.
- Not on the Compatibility (low-end) backend (`particle_process_material.cpp:1946`).

hanabi (`modifier/mod.rs:649-715`, `modifier/attr.rs:148-230`):
- `EmitSpawnEventModifier { condition: Always | OnDie, count, child_index }` appends events in
  the parent's update; the child's spawner consumes them next frame.
- `InheritAttributeModifier` copies an attribute from the parent particle as it was in the
  previous frame (one-frame latency).

### 4.2 What Void builds

Events, not calls. Each emitter owns an event buffer per event kind (SoA):

```
SubEmitEvents {
  kind: uint8[]           # Birth | Collision | Death | Trigger | Manual
  entry: uint8[]          # which sub-emitter entry of the parent fired
  parentSeed: uint32[]
  eventIndex: uint32[]    # monotonic per parent emitter (determinism key)
  position, velocity: vec3[]
  color: vec4[]; size: vec3[]; rotation: vec3[]
  parentAgeFraction: float32[]      # for Lifetime and Duration inherit
  parentLifetime: float32[]
  subStepTime: float32[]            # time inside the step the event happened
}
```

Order of processing in one update (§6): the whole tree is stepped parent-first (topological
order of the DAG); a parent fills its buffers during its step; each child consumes the buffers
of its parent(s) in the same update, after the parent is done. This is zero-frame latency,
unlike Godot and hanabi (one frame). Zero latency is what Unity shows (mem: Death sub-emitters
appear at the death position in the same frame) and the CPU sim can afford it because the tree
is stepped serially. Same-update consumption is the reason a cycle must be refused: with a
cycle there is no order.

Spawning children for an event:

```
for event e in buffer order (parent index order, then event kind):
    if hashUnit(e.parentSeed, SUB_PROB, e.entry, e.eventIndex) >= entry.probability: continue
    childSeedBase = hash(e.parentSeed, e.entry, e.eventIndex)
    match e.kind:
        Birth:   handled per parent particle, below
        else:    for each burst of the child at time 0: n = burst.count.eval(...)
                 spawn n with seed = hash(childSeedBase, k), age = t1 - e.subStepTime
    each spawned child:
        position = e.position + shapeSample (child's shape, in the child's space at e.position)
        velocity = child start speed * dir + inheritVelocity.eval * e.velocity
        if Color: startColor *= e.color; if Size: startSize *= e.size
        if Rotation: startRotation += e.rotation
        if Lifetime: lifetime *= (1 - e.parentAgeFraction)        # mem: exact form
        if Duration: child main curves use e.parentAgeFraction as normalized time
```

Birth. A Birth child is not event-driven per step; it emits continuously while the parent
lives. Each parent particle with a Birth entry carries the child's emission accumulator
(Unity's `m_EmitAccumulator0/1` per particle, `ParticleSystemStructs.cs:1082-1098`). Per step,
for each alive parent particle: `acc += childRate * dt + childRateOverDistance * |Δpos|`, `n =
floor(acc)`, push `n` Birth events with sub-step times. The child's bursts run on the parent
particle's age as their time axis (mem). That needs per-particle accumulator columns on the
parent, two float32s per Birth entry, allocated only when the emitter has a Birth entry.

Cap. A child at its `maxParticles` drops spawns as §1.8 (Godot refuses past `particle_max`).
The parent is never blocked by a full child.

Cycle refusal. At asset build, build the graph emitter → sub-emitter entries and run a DFS
with three colours; on a back edge refuse with an error naming the cycle path ("sub-emitter
cycle: sparks → embers → sparks"). Unity refuses at assignment
(`ParticleSystemEditor.bindings.cs:50`); Void refuses at build because Void has no editor gate.
A sub-emitter shared by two parents is allowed (DAG, not tree); it consumes both parents'
buffers in parent order. Unity requires the child to be a descendant of the root
(`SubModuleUI.cs:228`); Void's asset is one tree of emitters, so this is structural.

Manual. `emitter.triggerSubEmitter(entry, particleIndices?)` appends Manual events from the
app between updates; they are consumed in the next update at `subStepTime = t0`.

Determinism. Child seeds are `hash(parentSeed, entry, eventIndex)`, never a running stream,
so the result does not depend on how many children other parents spawned. Event order is by
parent column index after compaction of the previous step, which is stable because the
compaction keeps order (runtime report).

2D vs 3D: same; vec2 columns in 2D.

NEW MECHANISM check. Event buffers are Godot's and hanabi's mechanism (an emission buffer
filled by parents). Same-update consumption is a scheduling choice on the CPU path, not a new
mechanism, and it moves Void toward Unity's visible behaviour. Flag one thing for the person:
the future GPU tier (runtime report) will be one frame late like Godot and hanabi, so the CPU
and GPU tiers would differ by one frame of child spawn. Either accept that, or make the CPU
tier one frame late too for parity. See open question Q3.

### 4.3 Oracle

1. Parent burst of 1, lifetime 1, Death child burst 3: at the step where the parent dies,
   3 children exist in that same update at the parent's final position (zero latency).
2. Probability 0.5, 1000 parents, seed fixed: child count = same exact number at dt 1/30 and
   dt 1/120 (frame-rate independence of the draw).
3. Birth child rate 10, parent lifetime 1: each parent yields 10 ± 1 children; with Color
   inherit and parent colour red, every child `startColor.r == child.r * 1.0, g == 0`.
4. Asset with A → B → A: build fails with the cycle path in the message.
5. Collision child: parent hits plane at step k; children's first position on the plane, y ≥ 0.

---

## 5. Velocity and force modules

All of these write `velocity` (stored, integrated) or `animatedVelocity` (recomputed per step).
Which one decides whether the effect accumulates. The authoring report's §5.3 fixes the model;
this section gives the per-module math.

### 5.1 Velocity over Lifetime

Reference. `VelocityOverLifetimeModule` (`bindings.cs:2593`), doc: linear `x,y,z` in Local or
World space; `orbitalX/Y/Z` around the axes with `orbitalOffset` as the centre; `radial` away
from (or toward) the centre; `speedModifier` scales speed "along/around their current direction
of travel" (doc). Godot has orbit, radial and directional velocity as displacement
(`particle_process_material.cpp:700-845`): orbit rotates the position about the pivot exactly
by `ω·2π·dt` and returns `displacement/dt`.

Algorithm (per step, writes `animatedVelocity`, and speedModifier scales the sum at integrate):

```
tN = age / lifetime
lin = vec3(x.eval(tN, r), y.eval(...), z.eval(...))      # r = hashUnit(seed, VOL)
if space == World and simSpace == Local: lin = R⁻¹ lin   (and vice versa)
c = emitterOrigin + orbitalOffset
rel = pos - c
# orbital: exact rotation, Godot form, so the radius does not drift outward
rotated = rotateXYZ(rel, orbital.eval(tN, r) * dt)   # radians/s, per axis, in X then Y then Z order (mem)
orb = (rotated - rel) / dt
rad = normalize(rel) * radial.eval(tN, r)
animatedVelocity = lin + orb + rad
speedMul = speedModifier.eval(tN, r)
```

Integration then uses `pos += (velocity + animatedVelocity) * speedMul * dt` (mem: Unity
applies speedModifier to the total velocity at integrate). The exact-rotation orbit is
Godot's; a naive `cross(ω, rel)` tangent velocity spirals outward at large `ω·dt`. Recommend
Godot's form; it is the mechanism of a reference.

Radial toward the centre: clamp so the particle does not overshoot the centre in one step
(Godot clamps the inward case, `particle_process_material.cpp:~760-800`): `if rad points
inward: |rad*dt| <= |rel|`.

2D: orbital only around Z; radial in the plane; linear x,y.

Oracle: orbitalZ = 2π rad/s, start at (1,0,0), no other velocity; after 1 s at dt 1/60 the
particle is back at (1,0,0) within 1e-4 and radius stays 1 within 1e-5 at every step.

### 5.2 Limit Velocity over Lifetime

Reference. `LimitVelocityOverLifetimeModule` (`bindings.cs:3500`), doc: `limit` (or per-axis
with `separateAxes`), `dampen` "how much this module dampens particle velocities that exceed the
velocity limit" (`bindings.cs:3944`); editor: dampen 0.5 removes 50% of the excess
(`ClampVelocityModuleUI.cs:29`); `space` applies only with separateAxes
(`bindings.cs:4034-4035`); `drag` is linear drag, with `multiplyDragByParticleSize` and
`ByParticleVelocity`. Limit Velocity disables procedural simulation
(`ParticleSystem.bindings.cs:152-160`), which says it is step-dependent state. Godot:
`velocity_limit_curve` clamps final speed after turbulence. hanabi LinearDrag:
`v *= max(0, 1 - drag*dt)` (`modifier/force.rs:~280-300`). Void: Godot damping,
`damped()` (`particles.ms:~739`).

Algorithm (mem for order; doc for each part):

```
tN = age/lifetime
# drag first
d = drag.eval(tN, r)
if mulBySize: d *= size^2 (mem: area)          ; if mulByVelocity: d *= |v|^2 (mem)
velocity *= max(0, 1 - d * dt)                  # hanabi form; frame-rate dependent only at large d*dt
# then limit, on the TOTAL velocity, but correction written into velocity
L = limit.eval(tN, r)
vt = velocity + animatedVelocity; s = |vt|
if s > L:
    excess = s - L
    k = dampen * excess                         # fraction of the excess removed this step
    velocity -= normalize(vt) * k               # mem: whether Unity scales by dt here
```

Frame-rate dependence. Unity's dampen as documented is "per update" (editor tooltip, 50% of
the excess), which makes the result depend on frame rate; this is very likely why Limit
Velocity is excluded from procedural mode. Void's fixed step (§6) makes it reproducible. A
frame-rate independent form is `k = excess * (1 - (1 - dampen)^(dt * 60))` (exact under the
60 Hz reading); that is a divergence and is an open question (Q4), not a default.

Separate axes: same per component, in the chosen space.

Oracle: start speed 10, limit 5, dampen 0.5, no other forces, fixed dt 1/60: speeds per step
10, 7.5, 6.25, 5.625 ... (excess halves each step). Drag 1, dt 1/60: speed after 1 s equals
`10 * (1 - 1/60)^60` within 1e-5.

### 5.3 Force over Lifetime

Reference. `ForceOverLifetimeModule` (`bindings.cs:4617`): `x,y,z` in Local/World;
`randomized` picks a new random value each frame (`bindings.cs:4876`), only with two constants
or two curves (`ForceModuleUI.cs:25`). Void today evaluates force and gravity on emitter
cycle time (`particles.ms:~658-737`), which is Heaps.

Algorithm: `velocity += F(tN, r) * dt` with `r = randomized ? hashUnit(seed, FORCE, stepIndex)
: hashUnit(seed, FORCE)`. Curves over particle normalized age (Unity), not emitter time:
emitter-time force is a Heaps divergence to drop or keep as a separate Heaps-compat field
(the authoring report's call).

### 5.4 Gravity

`gravityModifier` × `Physics.gravity` (mem) or `gravitySource` 3D/2D physics
(`ParticleSystemEnums.cs:441`). Void has no physics settings object: gravity is an engine-level
vector (or a per-emitter override) times `gravityModifier.eval(emitterT)` (mem: Unity evaluates
gravityModifier over the emitter's normalized time, not the particle's). `velocity += g * dt`.

### 5.5 External Forces and force fields

Reference. ExternalForces affects particles with ForceFields and WindZones
(`bindings.cs:7100-7103`): `multiplier` (MinMaxCurve), `influenceFilter` (LayerMask or List),
an influence list. ForceField (`ScriptBindings/ParticleSystemForceField.bindings.cs`): `shape`
Sphere/Hemisphere/Cylinder/Box (`ParticleSystemEnums.cs:732`), `startRange`, `endRange`,
`length` (cylinder), `directionX/Y/Z`, `gravity` with `gravityFocus` (0 = centre, 1 = outer
edge), `rotationSpeed` about the field's Z axis, `rotationAttraction`, `rotationRandomness`,
`drag` with multiply by size/velocity, `vectorField` (3D texture) with `vectorFieldSpeed` and
`vectorFieldAttraction`. Curves are allowed on direction, gravity, rotation speed/attraction,
drag and vector field (doc), sampled over (mem) the particle's normalized distance inside the
field range or its age — unverified, see Q6.

Godot attractors (`particles.glsl:452-493`): sphere, box, vector field; per attractor
`strength` (sign = attract/repel), `attenuation` (pow falloff), `directionality` (blend from
radial to the attractor's -Z direction); force added to the step's force sum before
`VELOCITY += force*DELTA`.

Algorithm (per field f, per particle, in field space):

```
lp = f.worldToLocal * pos
d  = distanceInShape(lp, f.shape)            # sphere: |lp|; cylinder: radial |lp.xy| within length; box: max-norm
if d > endRange: continue
w  = d < startRange ? 1 : 1 - (d - startRange) / (endRange - startRange)     # mem: linear falloff
tN = saturate(d / endRange)                                                    # see Q6
acc  = f.rot * vec3(dirX.eval(tN), dirY.eval(tN), dirZ.eval(tN))
focus = lerp(0, endRange, gravityFocus)
toward = -normalize(lp) * sign(d - focus)                                      # mem: focus semantics
acc += f.rot * toward * gravity.eval(tN)
# rotation: tangential around field Z
tang = cross(Z, lp.xy0) normalized
acc  += f.rot * tang * rotationSpeed.eval(tN)          # mem: velocity target vs acceleration
# drag
dd = drag.eval(tN) * (mulSize ? size : 1) * (mulVel ? |v| : 1)
velocity *= max(0, 1 - dd * dt * w)
# vector field
if f.vectorField: target = sampleTrilinear(field, lp) * vfSpeed.eval(tN);
                  velocity = lerp(velocity, target, vfAttraction.eval(tN) * w)  # mem
velocity += acc * w * externalMultiplier * dt
```

Unity's ForceField internals (focus, falloff, rotation attraction form) are (mem) throughout;
the manual describes intent only. The safe plan: build Godot's attractor contract (strength,
attenuation, directionality, sphere/box/vector field), which is read source, as the
mechanism; expose Unity's ForceField field names on top where each maps to a Godot term
(gravity → strength toward centre, directionX/Y/Z → directional term, drag → per-field linear
drag), and treat `gravityFocus`, `rotationSpeed/Attraction/Randomness`, `vectorFieldAttraction`
as Unity terms whose exact form needs a Unity oracle before they are claimed compatible.
WindZone: a direction plus turbulence pulse; maps to a directional field with noise; defer.

2D: fields in the plane; Cylinder and Hemisphere collapse to circle; rotation about the view
axis.

Oracle: a sphere attractor at origin, strength 10, no falloff, particle at rest at (5,0,0);
after the step `v == (-10*dt, 0, 0)`. Box field: particle outside the box is unaffected.

### 5.6 Noise and turbulence

Reference. NoiseModule (`bindings.cs:7648`): `strength` (per axis optional), `frequency`,
`scrollSpeed`, `damping` (strength proportional to frequency, `NoiseModuleUI.cs:43-56`),
`octaveCount`, `octaveMultiplier`, `octaveScale`, `quality` 1D/2D/3D
(`ParticleSystemEnums.cs:617`), `remapEnabled` + remap curves, `positionAmount`,
`rotationAmount` in degrees/s (`bindings.cs:9485`), `sizeAmount` as a multiplier
(`bindings.cs:9535`). PlaybackState keeps `m_NoiseScrollOffset`
(`ParticleSystemStructs.cs:1624-1708`). Noise writes `animatedVelocity` (`:946-956`), so it is
a displacement field, not a force: it does not accumulate.

Godot turbulence (`particle_process_material.cpp` turbulence block; Void port
`src/void3d/particleNoise.ms:57-145`): curl noise from 4D simplex, `noise_strength`,
`noise_scale`, `noise_speed` (scroll) and `noise_speed_random`, `influence` min/max (blend
velocity toward the noise direction), `initial_displacement`; skipped for a collided particle;
applied by bending the velocity direction toward the noise direction, keeping speed.

These are two different mechanisms. Unity Noise adds a velocity offset each step (so a
particle at rest wobbles in place). Godot turbulence rotates the stored velocity toward the
field (a particle at rest stays at rest; a moving one curls). Void today has Godot's
(`bentToward`, `particles.ms:~748`).

Algorithm for Unity Noise (on the existing curl noise, which is Godot's source):

```
scroll += scrollSpeed * dt                       # per emitter, PlaybackState
for i:
    f = frequency; a = strength.eval(tN, r); if damping: a = a * f (mem: strength/frequency? see doc)
    n = 0; amp = 1; fr = f
    for o in octaves: n += amp * curl3(pos * fr + seedOffset, scroll); amp *= octaveMultiplier; fr *= octaveScale
    if remap: n = remapCurve(n)
    animatedVelocity += n * a * positionAmount
    rotation += n.x * rotationAmount * dt        # degrees/s → radians
    sizeMul   *= 1 + n.y * sizeAmount            # mem: which channel drives size
```

Quality 1D/2D/3D picks how many independent noise lookups (1D gives the same value on all
axes, mem). Unity's noise function is not curl (mem: it is a value or Perlin-like noise); Void
should use its existing curl noise and accept that the pattern differs from Unity while the
parameters mean the same thing. That is not a divergence that changes any program's result
contract, only the noise pattern, so it needs no NIM-REF-style entry, but say it in the docs.

Keep Godot turbulence as a separate module (it is in the authoring report's extras). Both may
run; Noise writes `animatedVelocity`, turbulence bends `velocity`.

Oracle: noise strength 0 is a no-op (byte-equal columns); with scrollSpeed 0 and the particle
held still (`velocity = 0`), its position oscillates around a fixed point rather than drifting
(no accumulation) — measured as mean displacement over 10 s < 0.1 * strength.

### 5.7 Color, Size, Rotation by Speed

Reference. Modules sample their curve at `saturate((speed - range.x) / (range.y - range.x))`
where speed is the total speed (mem: total velocity including animated).

Algorithm: computed after the velocity modules of the step, before render:
`s = |velocity + animatedVelocity|`, `u = saturate((s - lo)/(hi - lo))`,
`color = startColor * colorOverLifetime(tN) * colorBySpeed(u)`; size and rotation the same
(rotation by speed is an angular velocity, integrated: `rotation += rotBySpeed(u) * dt`).
Refuse `hi <= lo`.

### 5.8 Custom Data

Reference. `CustomDataModule` (`bindings.cs:14127`): two streams Custom1/Custom2, each
Disabled, Vector (up to 4 MinMaxCurves over lifetime), or Color (MinMaxGradient); read by the
renderer's custom vertex streams and by scripts via `GetCustomParticleData`.

Algorithm: per step `custom1 = vec4(c0.eval(tN, r), c1.eval(...), ...)` or gradient. Two vec4
columns allocated only when enabled. The app may also write them (Unity
`SetCustomParticleData`); the module overwrites them each step only when its mode is not
Disabled, so app-written data survives with the module off (mem).

### 5.9 Size, rotation and colour over lifetime

Covered by the authoring report; the only simulation fact here is order: they evaluate at the
post-step age, after integrate, so the rendered frame shows the age the particle has reached.

---

## 6. Stepping and determinism

### 6.1 References

- Unity: variable dt by default; `Simulate(t, withChildren, restart, fixedTimeStep)`
  (`ParticleSystem.bindings.cs:828-836`) with fixedTimeStep meaning "use
  `Time.fixedDeltaTime` slices" (mem); PlaybackState `m_AccumulatedDt` (`ParticleSystemStructs.cs:1624-1708`)
  is the remainder of that slicing (mem). Unity's module order inside one step is closed
  source; the order below marked (mem) is what its behaviour suggests.
- Godot CPUParticles: `fixed_fps` (0 = variable). With fixed_fps, `frame_remainder += dt;
  while remainder >= 1/fps: step(1/fps)`; dt is clamped to `[0.001, 0.1]`; preprocess uses the
  same fixed step with speed scale 1 (`cpu_particles_3d.cpp:649-717`). With `interpolate`
  the renderer lerps between the last two steps. Order in `process()` of the material:
  age → controlled displacement (orbit, radial, directional) → force sum (gravity, linear,
  radial, tangent accel, attractors) → `VELOCITY += force*DELTA` → damping → collision → turbulence
  (if not collided) → final velocity = controlled + VELOCITY → velocity limit → integrate →
  colour/scale/rotation curves → sub-emitter emit (`particle_process_material.cpp:926-1183`).
- hanabi: `MotionIntegration` None/PreUpdate/PostUpdate, default PostUpdate: modifiers then
  `position += velocity * dt` (`asset.rs:27-80`).
- Heaps: variable dt, collision after the move (`Emitter.hx:177-213`).

Unity's order (mem, to confirm by oracle): emission and spawn (with shape, inherit,
lifetime-by-speed) → age → VoL linear/orbital/radial into animatedVelocity → Inherit Current
→ Force (incl. gravity) and External Forces into velocity → Noise into animatedVelocity →
Limit velocity (drag, then clamp) → integrate with speedModifier → collision (swept) →
trigger → colour/size/rotation over lifetime and by speed → custom data → death and sub-emitter
death events.

### 6.2 Recommendation: fixed step with a remainder

Fixed step is what makes the collision sweep, limit dampen, force `randomized`, and the
Unity-style per-update rules reproducible across frame rates, and it is what the oracles above
assume. Godot has it on the CPU path; Unity has it as an option.

```
update(frameDt):
    dt = clamp(frameDt * simSpeed, 0, maxFrameDt)        # maxFrameDt 0.1 (Godot)
    acc += dt
    n = min(floor(acc / h), maxSubSteps)                  # h = 1/60 default, maxSubSteps 8
    acc -= n * h; if n == maxSubSteps: acc = min(acc, h)   # drop the rest, avoid spiral
    repeat n: step(h)
    alpha = acc / h                                        # render interpolation factor
```

Interpolation for render: keep `prevPosition` only when the asset asks for interpolation (a
column added on demand), else render the last step; Godot's `interpolate` is the model.
Variable step stays available (`fixedStep = 0`) for cheap effects, with the documented loss of
frame-rate independence for collision, limit dampen and randomized force.

Prewarm and PauseAndCatchup use the same `step(h)`.

### 6.3 The fixed Void step order for one `step(h)`

For the emitter tree in topological order (parents before children), per emitter:

1. **Time**: start delay, cycle time `t0 → t1`, loop split into spans (§1.1); `emitterVelocity`
   from the transform delta.
2. **Consume events** from parents' buffers of this step and the app's Manual queue (§4.2);
   spawn children with sub-step ages.
3. **Emit**: rate over time and distance (floor carry), bursts by occurrence with hashed
   probability (§1.8); cap at maxParticles or ring replace (§1.7).
4. **Spawn init** for every new particle (from 2 and 3): seed, shape sample with arc modes and
   direction options (§2), start values, lifetime × lifetime-by-speed, `velocity = dir * speed +
   inherit Initial`, sub-emitter inherit props, `age = t1 - spawnTime`; Birth sub-emitter
   accumulators zeroed.
5. **Age**: `age += h` for old particles (new ones already have their age); ring modes clamp or
   wrap; mark `age >= lifetime` dead (not removed yet).
6. **Animated velocity** (recomputed from zero): VoL linear + orbital (exact rotation) + radial
   (§5.1), Inherit Current (§1.4), Noise (§5.6).
7. **Stored velocity**: Force over lifetime, gravity, external fields (§5.3-5.5),
   `velocity += a * h`; Godot linear damping (Void's existing extra); Godot turbulence bend
   (skipped if collided last step).
8. **Limit**: drag, then the speed clamp with dampen on the total (§5.2).
9. **Integrate + collide**: swept collision against planes, analytic colliders, app hook; the
   rest of the step after a hit; lifetime loss, kill speeds; collision events and Collision
   sub-emit events (§3.3).
10. **Trigger**: overlap, Enter/Exit/Inside/Outside, actions and callback lists, Trigger
    sub-emit events (§3.6).
11. **Rotation and size integrate**: angular velocity, rotation by speed, noise rotation.
12. **Appearance**: colour, size, rotation over lifetime and by speed, custom data, texture
    sheet frame, at the post-step age.
13. **Birth events**: per alive parent with a Birth entry, accumulate and push events (§4.2).
14. **Death**: collect dead (age, kill speed, trigger Kill, collision kill), push Death sub-emit
    events with the particle's final state, then compact (order-keeping).
15. **Stop**: stop action when emission ended and nothing alive.

Then the children of this emitter run steps 1-15 in the same update with the events of
2/9/10/13/14 visible. App event spans (collision, trigger) are valid from the end of `update`
until the next `update`.

What is (mem) in this order: Unity's placement of Noise before or after forces, of limit before
or after integrate, of trigger relative to collision. None changes a single-module oracle; they
change combinations (Noise + Limit). The way to settle it is a small Unity capture scene per
pair, which needs a machine with Unity.

### 6.4 Determinism contract

Given the asset, the system seed, the app inputs per update (emitter transform, `frameDt`,
hook results, manual triggers), and a fixed step, every column is a pure function of those
inputs, across frame rates (because the step is fixed and draws are keyed hashes), across
CPU core counts (the CPU sim is serial per emitter tree, or parallel per tree with no shared
state), and across native and web builds when the math is float32 with the same operation
order (the web build must not use fast-math contraction differently; worth one cross-target
oracle: same seed, 600 steps, column hash equal on native and emcc).

Void's existing float64 times (`docs/VOID3D.md:380-425`, measured needed) stay: `time`, `age`
accumulate in float64 or are kept as float32 relative to a float64 cycle origin.

---

## 7. NEW MECHANISM summary

None of the features above needs a mechanism absent from all references. Things to flag:

| item | status | why |
|---|---|---|
| Sub-emitter events consumed in the same update (zero latency) | scheduling choice; references: Unity behaviour (mem) vs Godot/hanabi one frame late | CPU and future GPU tier differ by a frame (Q3) |
| Capsule collider | addition in Godot's depth/normal collider contract | no reference has it as a particle collider |
| App collision hook as a batch over columns | columnar form of Heaps `Collider.collidePart` | — |
| World collision type | refused as Unity's physics semantics; mapped to Void colliders + hook | Void has no physics (Q1) |
| SDF / heightfield bake collision | Godot mechanism, needs a bake pipeline | defer |
| Limit dampen frame-rate independent form | divergence from Unity's per-update rule | only if the person wants variable dt exact (Q4) |
| Noise pattern | curl (Godot source) instead of Unity's closed noise | same parameters, different pattern |
| Resting-contact slide rule | Godot's, borrowed into a Unity-shaped collision | — |

---

## 8. Test oracles, consolidated

- Unit oracles listed per section run on the CPU sim with fixed `h`, no renderer: emission
  counts (§1.8), burst loop split (§1.1), prewarm equivalence (§1.2), ring buffer (§1.7), shape
  distributions (§2), collision sweep and tunnel equality (§3.5), trigger edges (§3.6),
  sub-emitter latency, probability, cycle refusal (§4.3), orbit exactness, limit sequence, drag
  closed form (§5), frame-rate independence: the same asset at h fixed and frameDt 1/30 vs
  1/144 gives byte-equal columns (§6).
- Cross-target: column hash equal on native and emcc for one asset with every module on.
- Unity parity (needs a Unity install; none on this machine as far as this research saw):
  capture scenes for collision bounce/dampen form, BurstSpread centering, Noise/Limit order,
  sub-emitter Lifetime inherit, ForceField focus and falloff, trigger Enter for particles born
  inside. Until those run, each such claim stays (mem) in the docs.

---

## 9. Open questions for the person

Q1. **World collision.** Void has no physics engine. Options: (a) Void builds Planes + its own
analytic particle colliders + an app hook, and an asset's `World` resolves to those (no
Unity-scene parity); (b) refuse `World` and accept only Planes and Void colliders; (c) a
physics integration later. Recommend (a): Unity assets load and behave plausibly, and the
hook lets a game's physics take over.

Q2. **Unity parity measurement.** Several exact formulas (bounce/dampen form, limit dampen,
ForceField focus, sub-emitter Lifetime, step order) are closed source. Is there a machine with
Unity where capture scenes can run? Without it these stay "Unity-shaped" rather than
"Unity-identical", and the docs say so.

Q3. **Sub-emitter latency.** CPU tier can spawn children in the same update (Unity-like, mem);
a later GPU tier will be one frame late (Godot, hanabi). Same-update on CPU with a documented
one-frame difference on GPU, or one frame late on both for parity?

Q4. **Fixed step by default.** Recommend fixed `h = 1/60` with remainder and render
interpolation as the default, variable dt opt-in. This changes Void's current behaviour
(variable dt, Heaps). Accept? And if variable dt stays available, should Limit dampen use the
frame-rate independent form (a divergence from Unity's per-update rule) in that mode?

Q5. **Emission carry.** Heaps's ceil carry (current Void) spawns one particle earlier than
Unity/hanabi floor. Switching to floor changes the timing of every existing effect by up to one
spawn. Accept the switch?

Q6. **ForceField curve axis.** Unity's ForceField curves are sampled over something (distance
in the field, or particle age); the manual does not say. Ship ForceField with Godot's attractor
mechanism plus the Unity names that map 1:1, and hold the rest until measured?

Q7. **SkinnedMesh shape.** Needs CPU-side skinned positions from void3d. Defer until void3d
exposes them, or have the shape read the GPU skinning output (a readback sokol does not have)?
