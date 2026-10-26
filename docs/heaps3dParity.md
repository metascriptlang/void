# Heaps 3D parity campaign

## Boundary and provenance

The approved direction is to finish missing 3D rendering capabilities in one continuously
running campaign, fan out every independent lane, then perform the integrated audit and
optimization. It is not permission to put an ECS, physics simulation, audio, editor or asset
build pipeline into Void, nor to reproduce every Heaps convenience API. Retained scene and
asset helpers remain above the thin GPU door. Existing decisions in `VOID3D.md`, including
explicit refusals and the deliberate rows in `tests/PENDING3D.md`, are not automatically
revoked by the word parity. Do not restore reference bugs merely to match their outputs.

This is a first-pass capability inventory, not a completed architectural trace. A Heaps file
or a missing Void symbol identifies work to trace; it does not prove a safe implementation
or portable acceptance. Before choosing a mechanism, read the relevant decision documents
in full and the actual reference pass, and verify the proposed seam in a small probe.

Sources inspected:

- Heaps `b9aa6dcbb2307b03c1f435e87bdb036060100984`, `h3d/` and referenced `hxd/` loaders.
- Void main `d92138098ec855eef0068f21b0f5e0a5e4f33af3`; this branch `0000599b`, source tree
  `1c1b697f975822e2f1f970cfe6da6d623f95dbc6`. Local skinning is not on main.
- glTF reference `b43260ee1291134a94b3098d415f54f479a59508`; the pinned specification used by
  the skin trace is `out/tmp/skinning/specPinned.adoc`.

At that source tree the headless index passes **1538/1538 on BUILD 89005562**, 98 files,
0 new reds against the historical BUILD 5039c014 run. Command:
`MSC_NO_GLOBAL_CACHE=1 msc test src/test/index.ms`; local receipt
`out/tmp/parity/index890.log`, with matching binary/support BUILD captures before and after.
This does not rerun the older DRC/ORC controls, establish new GPU evidence, or accept any
rendered skin, browser or physical device. Keep the old receipts as historical evidence.

## Existing paths to reuse, not rebuild

`VOID3D.md` owns their acceptance and known gaps. Source pointers are `scene.ms`, `camera.ms`,
`renderer.ms`, `passList.ms`, `material.ms`, `gltf.ms`, `gltfScene.ms`, `texture.ms`,
`dirShadowMap.ms`, `billboard.ms`, `particleWriter.ms`, `screenFx.ms`, `toneMap.ms`, `bloom.ms`,
`worldLabel.ms` and the registered programs in `gpu3d.ms` / `programKeys.txt`.

These cover retained transforms and identity, perspective/orthographic views and masks,
material phases/layers and alpha cutout/blend, directional shadows, textured/emissive/normal
mapped materials, several primitives per source mesh, target-texture boundaries, world text,
CPU particles, HDR/tone curves/bloom, resource holders/close/rebuild and the shader door.
Their presence is not a fresh acceptance claim. In particular, emissive strength, bloom and
multi-primitive loading are not new Geass gaps.

## Frontier and reference anchors

| Family | Reference to trace | Current boundary and required proof |
|---|---|---|
| Skin asset and instance integration | `h3d/scene/Skin.hx`, `h3d/anim/Skin.hx`, `h3d/col/SkinCollider.hx:62-95`, glTF skins/animation | Skin import and instance binding landed before this wave (`VOID3D.md` "glTF skinning, integration and historical CPU foundation"). The `SkinCollider` ray query is `skinGeometry.ms` `rayIntersectionElements`; the other `h3d.col` types are ported (see [VOID3D.md](VOID3D.md#m5-end-game-stack-as-built-2026-10-23)). Skin with morph is refused. No rendered skin acceptance. |
| Animation composition | `h3d/anim/Transition.hx`, `SmoothTransition.hx`, `SimpleBlend.hx:15-49`, `BlendSpace2D.hx`, `SmoothTarget.hx` | Built: cross-fade with masks and weight tracks, smooth target with clip and blend speeds, 2D blend space; oracle-checked, with a recorded divergence for a node only one clip animates (the port blends toward the captured rest or frozen pose, Heaps toward `MZERO`). See [VOID3D.md](VOID3D.md#m5-end-game-stack-as-built-2026-10-23). Heaps' `SimpleBlend` (objects in its map from the second animation, the rest from the first) is `animationCompose.ms` `stageExclusiveCompose`. Not built: instance-scratch sharing across independent actors. |
| Morph deformation | `h3d/prim/Blendshape.hx`, `h3d/shader/Blendshape.hx`, glTF targets/weights | Built: glTF POSITION/NORMAL/TANGENT targets, default weights and weight tracks import, and a scene instance deforms through a private dynamic mesh that bounds, picking and the shadow pass also read. Skin and morph on one node morph on the CPU, then skin on the GPU (`addSkinMorphMeshNode`), with bounds and picking skinning the same morphed vertices. CPU-checked only. See [VOID3D.md](VOID3D.md#m5-end-game-stack-as-built-2026-10-23). |
| Exporter/accessor coverage | glTF accessors, nodes and images; `hxd/fmt/hmd/Library.hx`, `hxd/res/Image.hx` | Built: strided (interleaved) and sparse accessors decode for positions, normals, UVs, tangents, colours, indices and animation outputs (`gltfAccessor.ms`, `165ac5ba`, `493c95e3`); affine matrix nodes decode to TRS (`c3513dfe`), refused only as an animation target, where glTF allows TRS alone; COLOR_0 takes FLOAT or normalized u8/u16, VEC3 or VEC4 with its alpha (`gltfColour.ms`); indices take u8, u16 and u32 (`gltfIndexCheck.ms`). Pinned by `gltfAccessorCheck.ms`, `gltfCheck.ms`, `gltfColourImportCheck.ms`, `gltfIndexCheck.ms`, `gltfAnimationCheck.ms`, `gltfMaterialCheck.ms`. Weights outputs also take normalized byte, ubyte, short and ushort, as glTF's sampler table allows (`gltfMorphImportCheck.ms`); normalized rotation outputs stay refused until a real asset settles their unit check ([VOID3D.md](VOID3D.md#pending-normalized-integer-rotation-outputs)), and sparse sampler inputs are refused by decision ([VOID3D.md](VOID3D.md#gltf-sparse-animation-output-cpu-acceptance)). Several buffers load, the first supplied or embedded and the rest as `data:` URIs ([VOID3D.md](VOID3D.md#gltf-files-with-several-buffers-as-built-2026-10-26)). File URIs for buffers and images read through a caller's `GltfFileSystem`, Heaps' `hxd.fs.FileSystem` shape; without one they stay `BufferByUri` / `ImageByUri`, and a percent-encoded URI is refused until std decodes it ([VOID3D.md](VOID3D.md#gltf-files-that-name-other-files-as-built-2026-10-26)). |
| Large meshes / index width | `h3d/Indexes.hx`, `h3d/prim/BigPrimitive.hx`, `Polygon.hx` | Built (`42b2dc9f`): a mesh past 65535 vertices uploads u32 indices (`gpu3d.c` `gpu3dMakeIndexBuffer32`), the index type is part of the pipeline key (`src/gpu/pipeline.ms`), and the 65535/65536-vertex fixtures pin the promotion in `meshDataCheck.ms`, `pipelineCheck.ms` and the skin checks. `MAX_MESH_VERTICES` is the int32 bound. |
| PBR surface response | `h3d/shader/pbr/BRDF.hx:40-63`, `PropsDefinition.hx`, `PropsTexture.hx:28-34`, `Lighting.hx`, `mat/PbrMaterial.hx` | Built, opt-in: direct BRDF for one light, glTF metallic-roughness factors and maps (glTF channel packing, not Heaps'), occlusion, emissive, skinned. Refused: roughness 0, a pbr material with a UV transform. Reads about pi dimmer than the legacy lambert. Not done: environment/IBL, so indirect light is a flat ambient. See [VOID3D.md](VOID3D.md#m5-end-game-stack-as-built-2026-10-23). |
| Texture sampling and environment lighting | `h3d/mat/Texture.hx` `mipLevels` / `anisotropicMaxLevel`, `TextureArray.hx`, `Texture3D.hx`; `scene/pbr/Environment.hx`, `shader/pbr/CubeLod.hx` | Built: explicit mip chains with min/mag/mip filter, wrap, lod range and anisotropy samplers. Not done: automatic mip generation, `lodBias`, anisotropy above 1 on GLCORE/GLES3 (refused), cube/array/3D textures, environment and prefilter. No GL or WebGL2 receipt. See [VOID3D.md](VOID3D.md#m5-end-game-stack-as-built-2026-10-23). |
| Light shapes and shadow coverage | `scene/pbr/SpotLight.hx`, `RectangleLight.hx`, `CapsuleLight.hx`; `pass/PointShadowMap.hx:25-60`, `CubeShadowMap.hx`, `RectangleShadowMap.hx`, `CapsuleShadowMap.hx`, `SpotShadowMap.hx`, `CascadeShadowMap.hx` | Built: `scene.ms` `LightKind` Spot, Rectangle and Capsule are positioned light records beside point lights, packed as four shape vec4 per record (`gpu3d.ms` `LIGHT_RECORD_SHAPE`), and evaluate in the lit and pbr paths with Heaps' representative-point specular direction; the pixel-art preset refuses them (`PixelArtError.ShapedLight`). Divergences: `light-shape-*` rows in `tests/PENDING3D.md`. Spot shadows and cube shadows of a point, rectangle or capsule are built, one spot and one cube caster per frame (six array layers, [VOID3D.md](VOID3D.md#cube-shadows-point-rectangle-and-capsule-lights-as-built-so-far-2026-10-25)). Every map samples with `None` or `Pcf` ([VOID3D.md](VOID3D.md#shadow-filtering-pcf-as-built-so-far-2026-10-25)); ESM is not offered. Every map takes Bevy's normal bias, opt-in (`DirShadowMap.normalBias`, same section). Spot cookies are built, one cookie spot per frame, read at level 0 ([VOID3D.md](VOID3D.md#spot-cookies-as-built-2026-10-26)). Not done: environment lighting has its CPU math only (`pbrEnvironment.ms`). Additional shapes and shadow modes need their camera/culling/depth/sampler mechanisms traced and GLES/WebGPU budgets measured. The existing attenuation divergence is a prior decision, not a missing spelling. |
| General mesh instancing and LOD | `prim/Instanced.hx:17-86`, `impl/InstanceBuffer.hx`, `scene/MeshBatch.hx`, `prim/MeshPrimitive.hx` | Built: every mesh draw reads its world from an instance row, neighbours that differ only in world draw as one instanced draw, and an `InstanceRun` binds a caller's instance stream ([VOID3D.md](VOID3D.md#every-mesh-draw-reads-an-instance-row-as-built-2026-10-24)). `Scene3D` picks a LOD level per frame with the main camera and shadows reuse it (`addLodMeshNode`, `setForcedLod`, [VOID3D.md](VOID3D.md#scene3d-picks-the-lod-level-itself-2026-10-26)); `setInheritLod` hands a mesh's ratio to the LOD meshes below it ([VOID3D.md](VOID3D.md#a-lod-mesh-hands-its-screen-ratio-down-2026-10-26)); skinned meshes pick too (`addLodSkinMeshNode`); no pick per instance row; a GPU golden pins the pick (`meshLod.ms`, `VOID_MESH_LOD_SCENE`). Skinned draws bind a row of one. |
| Post-processing and material transforms | `pass/FXAA.hx:3-59`, `ScalableAO.hx`, `shader/pbr/SSR.hx`, `pass/ColorMatrix.hx`, `shader/ColorMatrix.hx`, `shader/Parallax.hx`, `shader/VolumeDecal.hx` | Built: parallax on normal-mapped pbr-maps materials, height in the pbr-maps texture's alpha from 6 face-on to the material's step count at grazing, 0 for Heaps' 24 (`PBR_PARALLAX_STEPS`, `PbrMaterial.parallaxSteps`; [VOID3D.md](VOID3D.md#parallax-as-built-so-far-2026-10-25)). Existing HDR/bloom, outlines/fog and screen quads are reusable. Decals are traced ([VOID3D.md](VOID3D.md#decals-what-ports-traced-2026-10-26)): Heaps' `DecalOverlay` ports in four steps, the first (its fragment math) built; `DecalPBR` needs a G-buffer and is not a port. Full material colour matrices and further post features are candidates, not traced-ready ports. AO/SSR depend on the proper depth/normal inputs; separate missing capability from a performance-only variant. |
| Remaining particle/geometry helpers | `parts/Data.hx`, `parts/Particles.hx`, `parts/GpuParticles.hx`, `scene/Trail.hx`, `scene/Graphics.hx`, `col/` | CPU particle curves/shapes/fade and rotation/aspect/atlas visuals exist (`9596ac70`, `3e4a5048`). `trail.ms` has CPU history/ribbon oracle coverage; upload/material/GPU integration is unverified. `h3d.col` is ported and oracle-checked: bounds, ray, frustum, segment, capsule, cylinder, polygon, height map, transform, object, optimized and group colliders ([VOID3D.md](VOID3D.md#m5-end-game-stack-as-built-2026-10-23)). Trace particle collision/subemitters and GPU particles separately. A GPU-compute-only path cannot claim WebGL2 parity; controller/UI policy belongs above rendering. BVH and batching optimization wait for equivalent results. |
| Acceptance and portability | existing `tests/integration`, `scripts/gate3d.sh`, `scripts/web3d.*`, compiler/Yoga inbox | Real exporter, WebGL2/WebGPU and physical GLES acceptance are independent work, not inferred from headless/native success. Preserve held-not-accepted captures and diagnose current cards on the installed compiler. No compiler/vendor edits from this session. |

### One concrete semantic trap

Heaps `PropsTexture.hx` stores metalness in R, derives roughness as `1 - G*G`, and reads AO
from B. glTF's metallic-roughness texture instead stores roughness in G and metalness in B,
with linear transfer; occlusion is separately defined by the specification
(`specPinned.adoc:2596,2631`). Port the BRDF mechanism, not Heaps' asset packing as if it were
glTF. This adapter is part of the asset/material contract to settle before parallel writers.

## Dispatch and ownership

The maximal frontier is the number of independent ready lanes, not the number of feature
names above. Initially all reference/fixture investigations can be independent; implementation
fan-out grows only after their common contracts have been read and probed.

| Lane | Exclusive first-pass output | Shared edits reserved to integration owner | Dependency |
|---|---|---|---|
| Skin consumer | `skin*` proof/fixtures, instance-binding proposal | `gltf.ms`, `gltfScene.ms`, `scene.ms`, `pick.ms` | Existing local skin stack; retained scene ownership and tangent remap contract |
| Accessor/export coverage | packed-accessor/colour/u32 fixtures and pure decoder proposal | glTF entry and mesh/index ABI | Source id and influence preservation, index-width contract |
| PBR response | BRDF numeric/reference probes and isolated material contract | material block, generated program set, both preset GLSL sources | Map packing, camera/view data and linear/HDR convention |
| Texture/environment | mip/sampler/cube capability probes | `src/gpu/*`, bridge, context texture tables | GPU-door owner coordination; environment after cube/prefilter contract |
| Lights/shadows | light/shadow reference fixtures and slot-budget proposal | scene/light block, shared shader blocks, registry | Texture target/sampling capability and PBR/light ABI |
| Animation/morph | curve/composition/morph reference fixtures and data proposal | shared pose/vertex ABI and glTF entry | Morph-before-skin ordering, instance ownership and generated attribute budgets |
| Mesh instancing/LOD | transformed-instance/LOD fixtures and lifecycle proposal | mesh/layout/renderer ABI and registry | Vertex/index contracts; both plain and deformed meshes |
| Post/material effects | isolated input/output fixtures and pass proposal | shared shader source/registry and frame graph | Depth/normal/HDR convention; AO/SSR wait for their actual inputs |
| Particle/query helpers | isolated reference fixtures and capability verdicts | shared billboard layouts, shader blocks and scene queries | Existing particle semantics; portability for any compute path |
| Acceptance | producer fixtures, negative controls and backend receipts | no shared feature code without assignment | Features reach their real consumers; native GPU requires named manager GO |

One owner updates the shared test index and documentation entrypoints. One shader owner
regenerates the table/headers after integration; concurrent regenerators are not separate
lanes. Tests owned by each lane stay isolated until the integration owner registers them.
Use one worker/worktree per actual path-disjoint implementation lane; do not make worktrees
for sequential slices or use a second repository's worktree to evade its compiler boundary.

Read-only audits can fan out before ABI decisions. A candidate awaiting an untraced mechanism
is not implementation-ready merely because its filenames are different. Extend the settled
references; a required genuinely new mechanism is raised before implementation.

## Operational conditions

The human authorized replacing the workspace's fixed two-worker interpretation with
ready-lane/resource-based concurrency. The old two-worker result remains the tested baseline,
not proof that more workers are either safe or impossible. Keep one workspace coordinator,
record the active ownership/dependencies, and reduce a contended job class when measured
throughput or reliability worsens. Do not stop unrelated reading/code lanes for a GPU slot.

At inventory time this Pi session has no subagent launcher tool. Shared Windows Pi settings
and installed packages have no configured subagents package; the shipped example is not loaded.
No worker has been launched. Do not report peer sessions or shell tool concurrency as a
launched subagent campaign, and do not silently pivot to another launcher or install code.
Launcher synchronization/setup must happen before actual fan-out.

**Executed frontier.** After human setup, native workflow
`d054a694-bfbd-4a83-a417-74929df2797a` completed its launcher smoke and ten read-only scouts
at `c9381878`. The parent read every returned report. These are source/reference traces,
not passing feature lanes: most scouts explicitly reported incomplete full-document retrieval.
The parent recovered its own exact read coverage and read the missing VOID3D ranges before
implementation. Runtime-managed `frontier/*.md` reports retain the individual anchors and limits.

### Component wave contract

This is a **multi-seam** campaign. The next writers own isolated **single-seam** components;
integration across importer, retained scene, renderer, shaders and GPU door remains parent-owned.
Each component must follow its reference and supply two variants plus an isolated negative control.
Only source/fixture preparation may fan out during the compiler gate: CPU compilation/tests run
serially after each writer exits, under the agreed scheduler slot. No component handoff counts as
verified until those tests run; no component may lift an importer refusal or register a program.

| Component owner | Exclusive files | Contract at the integration boundary |
|---|---|---|
| Accessor | `gltfAccessor.ms`, `gltfColour.ms`, dedicated checks | Owned decoded values from validated caller-supplied byte tables; stride/sparse/normalization and RGBA preservation. No URI policy or index-width GPU change. |
| Direct PBR | `pbrResponse.ms`, `pbrResponse.glsl`, dedicated check | Heaps direct response and separate glTF map interpretation in linear space. No legacy look change, view-slot choice or invented zero-roughness floor. |
| Mip data | `textureMip.ms`, dedicated check | Explicit supplied mip chains and complete supported sampler identity. No automatic generation, GPU door, cube target or environment approximation. |
| Light shape | `lightShape.ms`, dedicated check | Spot angular evaluation/camera data; rectangle/capsule closest-point math. No scene enum, attenuation replacement or unsafe culling copied by convenience. |
| Clip composition | `animationCompose.ms`, dedicated check | Staged TRS composition, captured-rest fallback and source-index exclusive masks; glTF intra-track SLERP and legacy sampling unchanged. |
| Morph data | `morphGeometry.ms`, dedicated check | Owned base/deltas and instance weights; atomic mesh-space position/normal/tangent deformation before skin. No GPU-only spatial proxy or dynamic-buffer policy. |
| LOD | `meshLod.ms`, `meshLodSceneCheck.ms` | Validated ordered thresholds and material/range-preserving selection, picked by `Scene3D` per frame and reused by shadows. No generic instance ABI or shared independent actor palettes. |
| Colour effects | `colorMatrixPass.ms`, `fxaaFilter.glsl`, dedicated check | Distinct material/screen matrix alpha rules and Heaps color-only FXAA block. No registry, preset ordering, AO/decal/SSR input invention. |
| Particle visuals | `particleWriter.ms` (`writeParticles`), `particleWriterCheck.ms` | Rotation/aspect/frame sampling and owned extended visual records, preserving current eight-float output and continuous Alpha. No compute or collision policy. |
| Acceptance asset | `tests/fixtures/gltf/generateSkinnedAsymmetric.py`, `skinnedAsymmetric.glb` | Independently computed asymmetric joints/IBMs/TRS, duplicate names, multiple materials and clone expectations. No private asset committed or GPU receipt inferred. |

All `.ms` paths above are under `src/void3d`; dedicated checks live under `src/test` and are
unregistered until parent integration. Workspace `wt.sh` provisions one worktree per writer;
the plugin does not allocate worktrees. Workers must finish mandatory document/reference reads,
probe the contract, and report any unresolved mechanism instead of guessing. Shared glTF/scene,
mesh/index ABI, materials/camera, GPU door/platform, shader registry/generated headers, test index
and docs are not worker-owned. Parent continues actual skin importer/instance/pick work independently.
Reference gaps (SSR compute on WebGL2, automatic mip generation, independent-pose instancing)
remain separate mechanism decisions, not implicit permission from this component wave.

Existing schedulers remain authoritative: timed BEGIN/END windows exclude heavy jobs;
CPU tests run in an agreed slot; native GPU execution requires named `void-manager` GO.
Parallel source workers do not justify simultaneous benchmark runs or changing acceptance
thresholds. Keep accepted captures/caches and historical receipts untouched.

After lanes converge: independently audit the actual integrated tree in the main session,
run the required native gate pair plus the applicable authorized GPU/web/device acceptance,
correct regressions and incomplete mechanisms, then measure and optimize. Commit small
logical changes internally without stopping at each commit; use the shared worktree flow to
land verified work and publish only under the recorded user approval. Do not call the
campaign complete while any required lane is partial, red or NOTRUN.
