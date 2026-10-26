# Unity particle goldens

`goldens/*.json` are `ParticleSystem` states captured from Unity, the reference that Void's
particle simulation is compared against. `ParticleCapture.cs` produces them: each case builds
one `ParticleSystem` from code, with `useAutoRandomSeed = false` and `randomSeed = 12345`
(children use 12346). Frame 0 is recorded after `Simulate(0, true, restart: true, false)`, and
frame k after k calls to `Simulate(dt, true, restart: false, fixedTimeStep: false)`. Each frame
stores the particles that `GetParticles` returns, capped per case.

## Regenerate

Captured on 2026-10-23 with Unity 6000.6.6f1 (Unity Personal license) on Windows 11. The
project is an empty built-in render pipeline project made by `-createProject`, with no template.
Its Color Space is Gamma. The script also runs `color_over_lifetime_linear` and
`subemitter_death_linear` with `PlayerSettings.colorSpace = Linear`, then restores the setting.

```sh
W=<worktree>
UNITY="C:/Program Files/Unity/Hub/Editor/6000.6.6f1/Editor/Unity.exe"
"$UNITY" -batchmode -nographics -quit -createProject "$W/out/unity/ParticleCapture" -logFile "$W/out/unity/create.log"
mkdir -p "$W/out/unity/ParticleCapture/Assets/Editor"
cp "$W/tests/unity/ParticleCapture.cs" "$W/out/unity/ParticleCapture/Assets/Editor/"
"$UNITY" -batchmode -nographics -quit -projectPath "$W/out/unity/ParticleCapture" \
  -executeMethod ParticleCapture.Run -goldenDir "$W/tests/unity/goldens" -logFile "$W/out/unity/capture.log"
```

The log ends with `ParticleCapture: done, failed cases = 0`. If any case fails, the exit code is 1.

## Prefab fixtures

`prefabs/*.prefab` are the importer's fixtures (`src/test/particleUnityPrefabCheck.ms`).
`PrefabExport.cs` builds four effects from code (fountain, curves, subEmitters,
trailsCollision), saves each with `PrefabUtility.SaveAsPrefabAsset` in the project's default
text serialization, and copies the file out. Same project as above:

```sh
cp "$W/tests/unity/PrefabExport.cs" "$W/out/unity/ParticleCapture/Assets/Editor/"
"$UNITY" -batchmode -nographics -quit -projectPath "$W/out/unity/ParticleCapture" \
  -executeMethod PrefabExport.Run -prefabDir "$W/tests/unity/prefabs" -logFile "$W/out/unity/prefab.log"
```

The log ends with `PrefabExport: done`.

## Age probe

`AgeProbe.cs` reruns the 21 `tie_death` cases and records, per frame, the remaining lifetime,
the custom data of a linear 0-1 curve, and the AgePercent and InvStartLifetime vertex streams
(`uv0.z`, `uv0.w` of `BakeMesh`). It writes one JSON file, not a golden; docs/PARTICLES.md
"Parity" holds what it showed. Same project as above:

```sh
cp "$W/tests/unity/AgeProbe.cs" "$W/out/unity/ParticleCapture/Assets/Editor/"
"$UNITY" -batchmode -nographics -quit -projectPath "$W/out/unity/ParticleCapture" \
  -executeMethod AgeProbe.Run -out "$W/out/unity/ageProbe.json" -logFile "$W/out/unity/ageProbe.log"
```

The log ends with `AgeProbe: done`.

## Limits

- `textureSheetAnimation` frame is not part of `ParticleSystem.Particle`. The texture sheet
  case reads it from `ParticleSystemRenderer.BakeMesh` UVs instead, using a camera at
  (0,0,-10) and recording the min UV corner of each quad.
- The `stretch_*` and `billboard_*` cases read the quad corners of `BakeMesh` (vertex order: top-left,
  top-right, bottom-right, bottom-left of the sprite) with an orthographic camera at (0,0,-10), so a
  velocity in the xy plane is the 2D case. `billboard_velocity_*` bakes Unity's Velocity alignment:
  a quad whose normal is the velocity, edge-on to this camera.
- `stretch_freeform*` bake a freeform Stretch with a small velocity and a large `velocityScale`, because
  Unity's freeform quad foreshortens with the angle to the camera even when it is orthographic.
  `billboard_moved_<alignment>_<space>` move the system to (2, 1) turned 30 degrees about z; its
  camera is reset to world (0,0,-10) with no rotation. For a Local-space system the baked centre is
  the particle's local position and the offsets from it are in world orientation; a World-space one
  bakes world positions. `*_clamp_*` set `minParticleSize` and `maxParticleSize` with the camera's
  `aspect` and `orthographicSize` recorded in the settings.
- `tie_*` cases record only `remainingLifetime` per particle (`remainingOnly`) at exact float
  boundaries of emission, bursts, wraps and deaths; `tie_world_*` record full particles. The
  `-only <substring>` argument of `ParticleCapture.Run` captures just the cases whose name
  contains it.
- `p3d_*` cases are the 3D render modes under a perspective camera: `p3d_pose1_*` and `p3d_pose2_*`
  place the camera and the emitter with a pitch, yaw and roll (the pose is recorded per frame in
  `pose.camera` and `pose.emitter`), and `particleModeCheck.ms` replays each through the writer and
  `particleVisualVs`. `cameraVelocityScale` has no golden: `BakeMesh` does not see the camera's
  velocity, so that term is written by the writer and tested only for its value.
- `m3d_*` cases are Mesh render mode, from the same two placements as `p3d_*` (`Pose.Persp`,
  `Persp2`), with two meshes built in code (a unit cube with one corner pulled out, 8 vertices; a
  lopsided pyramid, 5 vertices), 3D start rotation (20, 35, 50 degrees) and a non-uniform 3D start
  size. Each frame records the particles (`pos`, `rot`, `size`, `vel`), the pose, the meshes'
  own vertices in `settings.meshes` and `BakeMesh`'s vertices of every particle, concatenated, as
  `bakedMesh` (default options) and `bakedMeshXform` (rotation, scale and position baked too;
  which one is world space for a Local-space system is not known before the capture). Cases:
  `m3d_<alignment>` and `m3d_ortho_<alignment>` for View, World, Local, Facing and Velocity;
  `m3d_localsim_<alignment>` (Local simulation space, same five); `m3d_pivot_{view,world,local}`
  and `m3d_localsim_pivot_world`; `m3d_flip_{x,y,z,xyz}` (flip 1 on those axes);
  `m3d_negsize_x` (start size x -1.2, if Unity keeps it), `m3d_size_uniform`, `m3d_rot3d_off`
  (start rotation z only), `m3d_rot_{x,y,z}30` (one axis at a time, which fixes the rotation
  order); `m3d_pose2_<alignment>` with a pivot; `m3d_two_meshes`: 8 identical particles with
  `NonUniformRandom` weights 1 and 3. Unity exposes no per-particle mesh index, so the replay
  finds each particle's mesh by which one maps onto its baked vertices; Unity's own random
  stream picks the meshes, so Void's picks differ. Measured rules, all in Unity's frame: vertex =
  p + B . Ry . Rx . Rz . (size * (flipSign * v + pivot * boundsSize * (1, 1, -1))), with positive
  Euler angles (Quaternion.Euler) and boundsSize the mesh's max - min, so the pivot is in mesh
  extents and its z is negated. B is the camera's axes (View), the world's, the emitter's
  (Local), look-at-camera with the camera's up (Facing) or the velocity as z with world up as the
  reference (Velocity; a velocity along up is unmeasured). A negative start size is floored at 0
  (`m3d_negsize_x`). `bakedMesh` is world space for World simulation and `bakedMeshXform` for
  Local.
- Trigger callbacks (`OnParticleTrigger`) are not captured. The trigger cases set one event's
  action to Kill, so the particle count shows when that event fires.
- Noise is captured as `animatedVelocity` magnitude statistics plus 4 particles. Void's noise
  pattern differs from Unity's by design.
- Shape cases capture a single burst of 512 particles: position and velocity only, with
  startSpeed 1, so velocity is the spawn direction.
- A second run on the same machine wrote byte-identical files. Other machines and other Unity
  versions were not checked.
