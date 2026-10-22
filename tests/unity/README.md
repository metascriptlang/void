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

## Limits

- `textureSheetAnimation` frame is not part of `ParticleSystem.Particle`. The texture sheet
  case reads it from `ParticleSystemRenderer.BakeMesh` UVs instead, using a camera at
  (0,0,-10) and recording the min UV corner of each quad.
- Trigger callbacks (`OnParticleTrigger`) are not captured. The trigger cases set one event's
  action to Kill, so the particle count shows when that event fires.
- Noise is captured as `animatedVelocity` magnitude statistics plus 4 particles. Void's noise
  pattern differs from Unity's by design.
- Shape cases capture a single burst of 512 particles: position and velocity only, with
  startSpeed 1, so velocity is the spawn direction.
- A second run on the same machine wrote byte-identical files. Other machines and other Unity
  versions were not checked.
