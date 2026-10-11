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
`dirShadowMap.ms`, `billboard.ms`, `particles.ms`, `screenFx.ms`, `toneMap.ms`, `bloom.ms`,
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
| Skin asset and instance integration | `h3d/scene/Skin.hx`, `h3d/anim/Skin.hx`, `h3d/col/SkinCollider.hx:62-95`, glTF skins/animation | Local `skin*` and `gltfCurve`/`gltfPose` primitives exist; `gltf.ms` `loadNode` still refuses skin. Finish canonical influence/IBM decoding, source ids through primitive expansion, per-instance binding, `Scene3D` picking and actual posed rendering. Pin independent clones, nonuniform/mirrored/singular transforms, shadow, context rebuild and teardown. |
| Animation composition | `h3d/anim/Transition.hx`, `SmoothTransition.hx`, `SimpleBlend.hx:15-49`, `BlendSpace2D.hx` | `animation.ms` `blendTo` interpolates one track; local timestamp clips are not cross-clip transitions or masked layers. Trace playback/composition and instance scratch before adding it; glTF sampling semantics must remain distinct from legacy fixed-FPS playback. |
| Morph deformation | `h3d/prim/Blendshape.hx`, `h3d/shader/Blendshape.hx`, glTF targets/weights | `gltf.ms` `loadMesh` refuses targets and animation decoding refuses weight tracks. Trace morph storage and composition with skin before an ABI change. Bounds, picking, normals and rebuild must consume the same deformation, not a GPU-only proxy. |
| Exporter/accessor coverage | glTF accessors, nodes and images; `hxd/fmt/hmd/Library.hx`, `hxd/res/Image.hx` | `gltf.ms` `accessorView` refuses sparse/interleaved data; `loadNode` refuses matrix; image URIs and extra buffers have explicit limits. FLOAT VEC3 COLOR_0 and ushort indices are narrower than general exports. Normalized colours, VEC4 alpha and large indices require exact fixtures; no silently discarded channels. URIs need an explicit resolver contract, not hidden filesystem/network policy. |
| Large meshes / index width | `h3d/Indexes.hx`, `h3d/prim/BigPrimitive.hx`, `Polygon.hx` | `meshData.ms` `MAX_MESH_VERTICES` and `gpu3d.c` `gpu3dMakeIndexBuffer` expose the u16 path. Trace a u32 path through pipeline identity, upload/rebuild and range validation; test both widths. Do not assume a larger sokol buffer pool removes the per-mesh index limit. |
| PBR surface response | `h3d/shader/pbr/BRDF.hx:40-63`, `PropsDefinition.hx`, `PropsTexture.hx:28-34`, `Lighting.hx`, `mat/PbrMaterial.hx` | Current forward materials do not consume metallic/roughness; `gltf.ms` refuses occlusion textures. Trace direct BRDF response and material/map semantics, with independent numeric and rendered probes. Legacy forward and pixel-art looks stay explicit, not silently replaced. |
| Texture sampling and environment lighting | `h3d/mat/Texture.hx` `mipLevels` / `anisotropicMaxLevel`, `TextureArray.hx`, `Texture3D.hx`; `scene/pbr/Environment.hx`, `shader/pbr/CubeLod.hx` | `texture.ms` `TextureData`, `gpu/door.ms` image/sampler creation and `gpu3d.c` mip level 0 are the inspected seams. Trace mip chains, min/mag/wrap, cube/array capabilities, then environment/prefilter dependencies. Coordinate shared GPU-door changes with void2d; sampling parity needs minified-image fixtures and loss/rebuild proof. |
| Light shapes and shadow coverage | `scene/pbr/SpotLight.hx`, `RectangleLight.hx`, `CapsuleLight.hx`; `pass/PointShadowMap.hx:25-60`, `CubeShadowMap.hx`, `SpotShadowMap.hx`, `CascadeShadowMap.hx` | `scene.ms` `LightKind` has directional/point and `collectLights` enforces its slot budget; directional shadow is the existing implementation. Additional shapes and shadow modes need their camera/culling/depth/sampler mechanisms traced and GLES/WebGPU budgets measured. The existing attenuation divergence is a prior decision, not a missing spelling. |
| General mesh instancing and LOD | `prim/Instanced.hx:17-86`, `impl/InstanceBuffer.hx`, `scene/MeshBatch.hx`, `prim/MeshPrimitive.hx` | Billboard/particle layouts already instance; that is not generic lit mesh instancing. Trace instance transforms/normals/bounds, material-preserving commands, shared primitive lifetime and LOD choice. Keep skin/morph attribute and uniform budgets visible. No ECS or scene-storage rewrite is implied. |
| Post-processing and material transforms | `pass/FXAA.hx:3-59`, `ScalableAO.hx`, `shader/pbr/SSR.hx`, `pass/ColorMatrix.hx`, `shader/ColorMatrix.hx`, `shader/Parallax.hx`, `shader/VolumeDecal.hx` | Existing HDR/bloom, outlines/fog and screen quads are reusable. Full material colour matrices and further post/decal/parallax features are candidates, not traced-ready ports. AO/SSR depend on the proper depth/normal inputs; separate missing capability from a performance-only variant. |
| Remaining particle/geometry helpers | `parts/Data.hx`, `parts/Particles.hx`, `parts/GpuParticles.hx`, `scene/Trail.hx`, `scene/Graphics.hx`, `col/` | Core CPU particle curves/shapes/fade exist. Trace rotation/aspect, trails, particle collision/subemitters, GPU particles and geometric query helpers separately. A GPU-compute-only path cannot claim WebGL2 parity; controller/UI policy belongs above rendering. BVH and batching optimization wait for equivalent results. |
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
| LOD | `meshLod.ms`, dedicated check | Validated ordered thresholds and material/range-preserving CPU selection. No generic instance ABI or shared independent actor palettes. |
| Colour effects | `colorMatrixPass.ms`, `fxaaFilter.glsl`, dedicated check | Distinct material/screen matrix alpha rules and Heaps color-only FXAA block. No registry, preset ordering, AO/decal/SSR input invention. |
| Particle visuals | `particleVisual.ms`, dedicated check | Rotation/aspect/frame sampling and owned extended visual records, preserving current eight-float output and continuous Alpha. No compute or collision policy. |
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
