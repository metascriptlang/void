# void3d — 3D Render Layer

The opt-in 3D consumer above Void's GPU bridge, sibling to [void2d](VOID2D.md). It is a port of Heaps `h3d` (`~/projects/heaps`), taken in the order Hibernal needs it.

**Status (2026-09-19):** M1 done. The campfire spike (`src/void3d/{camera,mesh,pass3d}`, `src/examples/campfireScene.ms`) still renders on its own; each milestone below replaces a piece of it, and the spike is deleted when M6 lands.

## What Hibernal needs

From `~/metascript/hibernal`: `docs/RENDERER-BRIEF.md`, `docs/BRIEF.md` §5.6 (which amends the brief), `docs/ROADMAP.md` V1–V6 and A3/A4/A10/A11.

- **One scene, two surfaces.** The campfire home scene renders in the live wallpaper and in the app, from the same native core (`libhibernal.so`); the HUD is void2d/Neon drawn on top in-app only.
- **The t3ssel8r look.** Render at **360×800** into offscreen targets, integer-scale **3×** to 1080×2400 with nearest sampling. Passes: color + depth, normals, outline from depth + normal edges, palette quantization through a LUT, blit.
- **Pixel-perfect camera.** Orthographic, fixed yaw/pitch, snapped to the low-res texel grid; the sub-pixel remainder is applied as an offset in the blit. Without it the image shimmers — the brief calls it the single most important item.
- **Content.** Low-poly meshes, ≤500 tris per pet, ≤200 per prop, position + normal + vertex color, no textures on the pet, loaded from a glTF subset exported by a Blender generator.
- **Lighting.** One directional light plus one campfire point light, a toon ramp in the color shader, fire flicker stepped at 10–12 fps.
- **Animation.** Vertex-baked keyframes stepped at 12 fps. No skinning.
- **Interaction.** Tap the pet (pick), tap-and-hold (the host deep-links).
- **State-driven looks.** Palette swap for day/night, Winter and a Fading pet; fire size from hearts; harvest objects appear in the scene; snow. The mapping from game state lives in Hibernal, void3d only has to make each of these a parameter.
- **Wallpaper constraints (V6).** 30 fps target, ~10 fps or on demand when idle, stop when invisible, no allocation in the frame loop, every GPU resource rebuildable after context loss, a reduced-fidelity preview path.

## Porting rules

sokol replaces `h3d/impl` (drivers) and `hxsl` (shader compiler), so the port covers the layers above them.

Kept from Heaps: row-vector matrices and `local * parent` world transforms; the `posChanged` lazy sync of `h3d.scene.Object`; Material → Pass → render state; a Renderer that owns an ordered list of passes; depth in `[0, 1]`.

Changed on purpose:

- **Y up, right-handed** (Heaps: Z up, left-handed). glTF, the Blender exporter and the spike are Y up.
- **Fixed sokol-shdc programs instead of hxsl shader lists.** A Material names one program and carries its uniform values. Composable fragments stay deferred (`docs/SHADER.md` Tier 3).
- **The renderer consumes a draw list, not the scene tree.** Heaps' `emitRec` fills per-pass object lists during the walk; here the scene flattens to `Vec<DrawItem>` only when its structure changes, and each frame only rewrites world matrices. The renderer works (and is tested) with no scene at all.

Not ported: `hxsl`, `h3d/impl`, PBR (`scene/pbr`, `shader/pbr`), shadow maps, skinning (`anim/Skin`, `scene/Skin`), `World`/`HierarchicalWorld`, `GpuParticles`, `MeshBatch`/`Batcher` beyond instanced billboards, `RenderGraph`, `CameraController`.

## Data types

Storage is a plain retained tree: a Hibernal scene is tens of objects, and at that size layout costs nothing measurable. What is taken from [SCENE-SCALE.md](SCENE-SCALE.md) is how the **types** are cut, so that the tree could be moved to columns later without changing callers:

- **Per-node state is value structs grouped by the pass that reads it.** `Transform3D { position: Vec3; rotation: Quat; scale: Vec3 }` is one field; `world: Mat4` is another. An `h3d.scene.Object` allocates four times (itself, `absPos`, `qRot`, `children`); here only the node and its `children` array allocate.
- **Small node, kind data in side tables.** `Object3D` carries `kind`, `flags` (visible, posChanged, culled as bits), `local`, `world`, `children` and a `payload: int32` indexing the scene's `meshes: Vec<MeshInstance>` or `lights: Vec<Light>`. The opposite of `Node2D`'s 71 fields.
- **Assets are CPU data plus GPU handles.** `MeshData` keeps its vertex/index arrays; GPU buffers are `uint32` handles created from them and can be recreated from them after context loss. The same holds for textures (palette LUT, billboard atlases) and pipelines.
- **Frame state is preallocated.** Uniform blocks are `Vec<float32>` sized once; the draw list is rebuilt only on structural change; nothing in `frame` allocates.
- **Handles into scene tables are indices**, not references, so a draw item or a pick result is a plain value.

Possible feedback into void2d (not part of this plan): if the small-node + side-table split works here, `Node2D` is the obvious next candidate.

## Milestones

Ordered by Hibernal's device lane (`ROADMAP.md` §4: … → V1/V2 → V5 → A3 → V3/V4/T1 → A4 → … → A10 → A11). The render passes on device come first because A3 gates the rest, and the renderer does not need a scene to be tested.

| # | Heaps source | Void deliverable | Unblocks | State |
|---|---|---|---|---|
| M1 | `Vector`, `Vector4`, `Matrix`, `Quat` | `src/math/math3d.ms`, 17 tests | V3 | **done** |
| M2 | `mat/Pass` (render state), `mat/Material`, `impl/PipelineCache`, `mat/Texture` (targets) | Pipeline/pass creation from MetaScript through a flattened-descriptor bridge (`src/void3d/gpu3d.c`); render-state → pipeline cache; offscreen targets with depth; `DrawItem { mesh, material, world }` | V2, V1 (offscreen depth) | next |
| M3 | `scene/Renderer`, `scene/fwd/Renderer`, `pass/PassList`, `pass/ScreenFx`, `pass/Copy`, `pass/Outline` | The Hibernal renderer: scene pass to MRT color + normal/depth, one post pass for outline + palette LUT, integer-scale blit with sub-pixel offset; preview path at reduced fidelity | V5, A3 | |
| M4 | `Camera` (ortho `orthoBounds`, `makeCameraMatrix`, `project`, `rayFromScreen`) | Ortho camera with fixed yaw/pitch, texel-grid snap, remainder handed to the blit | A4 camera | |
| M5 | `prim/Primitive`, `Polygon`, `Cube`, `Plane2D`, `col/Bounds` | `MeshData` (position, normal, color; uint16 indices), GPU upload and rebuild, bounds; box/plane builders moved from the spike | A4, T1 | |
| M6 | `scene/Object`, `scene/Mesh`, `scene/Scene` | `Object3D` tree, lazy world sync, scene → draw list; **campfire rebuilt on M2–M6, spike deleted** | A4 | |
| M7 | `scene/Light`, `fwd/DirLight`, `fwd/PointLight`, `shader/AmbientLight` | Directional + point light as scene nodes, toon ramp levels as a material parameter | A4 lights | |
| M8 | — (Heaps loads HMD/FBX) | glTF subset loader: one buffer, positions, normals, `COLOR_0`, one mesh per node, node TRS | V4 | |
| M9 | `anim/Animation`, `anim/LinearAnimation`, `anim/BufferAnimation` | Object keyframes and vertex-baked frames, both stepped at a fixed rate (12 fps) | A4 idle, replay | |
| M10 | `col/Ray`, `col/Bounds`, `scene/Interactive` | Tap → ray → nearest object by bounds, then by triangle | A4 touch | |
| M11 | `parts/Emitter`, `parts/Particles` (CPU) | Snow and embers on the instanced billboard path; palette LUT swap and desaturation as renderer parameters | A11 | |

M3 and M6 end with the campfire running on D3D11 here and as a `.so` for Android. Every milestone adds headless tests to `src/test/` for whatever does not need a GPU (math, camera snap, bounds, sync, glTF parsing, animation stepping, picking).

### Android lifecycle (V6), alongside from M3

- The shell already renders one engine at a time through one shared EGL context (`VoidRenderer.show/hide`), so preview and live never draw concurrently; the preview gets the reduced path from M3.
- Context loss: `bridgeAndroid.c` keeps `g_ctx` forever and never sees `EGL_CONTEXT_LOST`. Add detection at swap, and a rebuild that replays M2's pipeline cache and M5's mesh uploads from CPU data.
- `EGL_DEPTH_SIZE` stays 0: the scene renders offscreen with its own depth attachment, and the swapchain only receives the blit.
- Frame pacing (30 / ~10 / on demand) is the host's call; void3d exposes "nothing changed since the last frame" from the dirty state so the host can skip frames.

## Open questions

- **Depth for edge detection.** The spike packs depth into the 8-bit alpha of the normal target. Sampling the real depth attachment (sokol depth textures) is more precise and frees the alpha; check support on GLES3/Mali before M3 depends on it. Same measurement as RENDERER-BRIEF §10 Q4 (`RGB10_A2` vs `RGBA8` normals).
- **One post pass or two.** The brief lists outline and palette as separate passes; merging them saves a full-screen read/write on mobile. Plan is one pass, split only if the palette needs the outlined image as input.
- **Device.** Nothing here has run on the Seeker yet; the Android `.so` has only been built. The first on-device run is the checkpoint after M3.

## Compiler notes (msc 0.2.53)

Hit while writing M1; both worked around in `math3d.ms`, neither checked against a newer msc.

- A second `` `*` `` overload on the same receiver type is invisible to importing modules: the C backend emits a raw `*` on two structs. In the defining module both overloads resolve. Workaround: one `` `*` `` per receiver (`Vec3 * Mat4`); scaling is `scaled()`.
- A float literal in arithmetic inside a struct-literal field widens to `float64`: `const p: P = { a: 2.0 * (x + x) }` with `a: float32` is a type error, the same expression in a `float32` local is not. Workaround: `float32` locals for the constants.

## Deferred from void2d: 3D text + SDF

Text shares **one** glyph layer with void2d — see [VOID2D.md → Text design](VOID2D.md#text-design-2026-06-21-one-shared-glyph-layer-two-consumers--bitmap-now-sdf-later). Carry-overs for void3d:

- **Same glyph quads, different transform.** The font layer (fontstash) emits backend-neutral `quad + UV + atlas`. void2d feeds them through the screen-space ortho path; void3d feeds the **same** quads through the camera MVP (world space, depth-tested). No second text system.
- **3D-text consumer = billboard or text-mesh.** Start with billboard; mesh only if a use case demands it.
- **Atlas upgrade bitmap → SDF** when void3d needs crisp world-space text. The glyph-quad interface stays the same, so void2d is unaffected.

## Reference

- [HEAPS.md](HEAPS.md) — `h3d.scene` / `h3d.mat` object and material model.
- [SCENE-SCALE.md](SCENE-SCALE.md) — how node data is typed and grouped (used here for types only, not storage).
- `~/projects/oryol` — module discipline + the `Gfx` tier that sokol_gfx descends from.
- Same scope discipline as void2d: a thin render layer, **not** a scene graph engine / ECS / physics. Higher-level game systems are layers above, pulled in per use case.
