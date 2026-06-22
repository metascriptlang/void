# void3d — 3D Render Layer (planned, not started)

The opt-in 3D consumer above Void's GPU bridge — camera / mesh / material — sibling to [void2d](VOID2D.md). Same `sokol_gfx` bridge (`src/sokol/{bridge,gpu}`), same shared layers below; void3d adds the world-space draw path (perspective MVP, depth, culling, materials). The textured spinning cube (`src/rendererSokol.ms`) is the proto-renderer this layer will generalize.

**Status:** not started. void2d (UI/HUD) is the current focus because Neon's first need is unified 2D rendering. This doc records decisions deferred from void2d so they land in the right place when void3d begins.

## Deferred from void2d: 3D text + SDF

Text shares **one** glyph layer with void2d — see the survey + rationale in [VOID2D.md → Text design](VOID2D.md#text-design-2026-06-21-one-shared-glyph-layer-two-consumers--bitmap-now-sdf-later). Carry-overs for void3d:

- **Same glyph quads, different transform.** The font layer (fontstash) emits backend-neutral `quad + UV + atlas`. void2d feeds them through the screen-space ortho path; void3d feeds the **same** quads through the camera MVP (world space, perspective, depth-tested). No second text system.
- **3D-text consumer = billboard or text-mesh.** Billboard = a flat quad in world space that always faces the camera (Godot `Label3D`, Unity world `TextMeshPro`). Text-mesh = extruded glyph geometry (Godot `TextMesh`). Start with billboard; mesh only if a use case demands it.
- **Atlas upgrade bitmap → SDF.** Bitmap atlas (fontstash default, used by void2d) blurs/jaggies under 3D perspective + scaling. World-space text wants **SDF** (Unity adopted SDF for exactly this; high end = GPU-from-outline / Slug). When void3d adds crisp world text, swap the atlas rasterization to SDF — the glyph-quad interface stays the same, so void2d is unaffected.

## Reference

- [HEAPS.md](HEAPS.md) — `h3d.scene` / `h3d.mat` (Pass + ShaderList) object + material model; the 3D scene-graph reference (Dawn-era doc, GPU-layer notes superseded by sokol).
- `~/projects/oryol` — module discipline + the `Gfx` tier that sokol_gfx descends from.
- Same scope discipline as void2d: a thin render layer, **not** a scene graph / ECS / physics engine. Camera/mesh/material helpers live here; higher-level game systems are layers above, pulled in per use case.
