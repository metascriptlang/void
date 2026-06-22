# void2d — Unified 2D / UI Render Layer

Void's 2D layer: draw the **same pixels on every platform** (Metal / D3D11 / GL / WebGPU / WebGL2) through one MetaScript codebase. This is the layer that makes Neon's UI rendering "special" — instead of binding to per-OS native widgets, an opted-in app can render its UI through Void and get identical output everywhere.

## Where it sits

```
Neon (parent)            component model: View, Text, Flexbox, events, state, diffing
  │   React-Native style; picks a backend per platform
  ├── native widgets      iOS UIKit · Android · Browser DOM          ← Neon-default
  └── Void backend        unified pixels on every platform           ← opt-in, "special"
         │
   JSX / Solid layer      reconciles a declarative tree → void2d/void3d nodes
   (built in parallel)    like React-Three-Fiber, but Solid-model (fine-grained
         │                reactivity, no virtual-DOM diff). Needs a RETAINED host.
   ┌─────┴───────────────────────────────────┐
 void2d (this layer)                        void3d (camera/mesh/material)   ← opt-in
   Node2D tree + quad batcher                       │
         │                                          │
         └──────────── Void GPU bridge ─────────────┘   = oryol "Gfx" tier  ✅ DONE
                              │   src/sokol/{bridge,gpu}
                       sokol_gfx (floooh)  ← the load-bearing cross-platform dependency
```

## Two faces of void2d (load-bearing)

1. **Immediate quad batcher** — thin over the GPU bridge: accumulate textured/colored quads CPU-side, flush as few draw calls. For HUD / games that just draw each frame.
2. **Retained `Node2D` tree** — `Node2D` = transform + props + children. This is the **host the JSX/Solid reconciler binds to** (R3F maps `<mesh>` → a retained `THREE.Object3D`; Solid-on-Void maps JSX → a retained `Node2D`). Each frame, walk the tree → emit batcher calls.

Both required from day one: face 1 ships HUD/game now; face 2 is what the reconciler (`createNode` / `setProp` / `appendChild`) will drive later. A pure immediate-mode 2D layer would have no host for the JSX layer to reconcile onto.

## Decision (2026-06-20): own the batcher, do NOT vendor sokol_gp

void2d's render base is a **hand-rolled quad batcher (~150 lines) on Void's own GPU bridge** — not [sokol_gp](https://github.com/edubart/sokol_gp).

**Why (in order):**

1. **Hard incompatibility.** sokol_gp master binds textures with the **old** sokol_gfx API (`sg_bindings.images[]`, `sg_shader_desc` images). Void's vendored `sokol_gfx.h` is the **resource-views** generation: `sg_bindings` has only `views[]`, `sg_shader_desc` has only `views[]` — no `images[]`. sokol_gp master **does not compile** against our sokol_gfx. (Downgrading sokol_gfx is rejected: it would break the working cube and move backward.)
2. **Less long-term maintenance, not more.** Owning the batcher = track **one** upstream (sokol_gfx). When sokol_gfx bumps its API we fix our bridge once (which we do for the cube anyway). Patching sokol_gp = track **two** upstreams (floooh's sokol_gfx + edubart's sokol_gp) **plus their compatibility** — which is already out of sync today, and would need re-patching on every sokol_gfx bump.
3. **Own-the-stack discipline.** A 2D quad-batcher is exactly the "UI-helper layer above the narrow waist" that Void's CLAUDE.md says Void should own. Hand-rolling a quad batcher directly on sokol_gfx is also the mainstream sokol pattern — floooh positions sokol_gp/sokol_gl as optional utils; many samples batch quads by hand.

**Important:** this does **not** detach Void from sokol. void2d still issues `sokol_gfx` calls through the bridge. B2 declines a third-party *add-on* (sokol_gp), keeping only the load-bearing core (sokol_gfx) — it *reduces* the dependency surface.

**What we give up + the escape hatch:** sokol_gp ships a shape rasterizer (lines, arcs, AA strokes, transform/clip stack). For UI we need only a subset (filled-rect, textured-rect, rounded-rect, clip, transform) — cheap to own. If void2d later needs heavy vector graphics (charts, arbitrary paths, AA strokes), evaluate **NanoVG-on-sokol** as an opt-in layer *above* void2d at that point — not now.

## Reference engines / libs

| Source | Local | Take | Skip |
|---|---|---|---|
| **oryol** (floooh) | `~/projects/oryol` | Module discipline: small layered modules, strict one-way deps (high→low), tier stays technique-agnostic. Its `Gfx` module = the **predecessor of sokol_gfx** → confirms our sokol bridge already IS that tier. | Its C++ container/RTTI opinions, CMake. |
| **Heaps `h2d`** | `~/projects/heaps` · [docs/HEAPS.md](HEAPS.md) | **Object model only**: `Object` retained transform tree, `Drawable`/`Tile`/`TileGroup` batching, `Text`/`Font` glyph layout, lazy cached matrices, object flags. Direct model for `Node2D`. | `Flow`/`Interactive`/`domkit` — that's a **UI framework = Neon's job**, not Void's. |
| **Kha `graphics2`** | `~/projects/Kha` | "2D built on top of the GPU layer" generational pattern; how a 2D API maps onto a 3D/GPU backend + a fallback path. | Its full multi-target build system. |
| **sokol_gp** (edubart) | not vendored — [github](https://github.com/edubart/sokol_gp) | Read its quad-batching + transform-stack approach as a model. | **Do not compile** (version mismatch, see decision above). |
| **sokol_fontstash** | `deps/sokol/util/sokol_fontstash.h` ✅ | Text/glyph atlas on sokol_gfx — the text path for void2d (step after shapes). | — |

## Text design (2026-06-21): one shared glyph layer, two consumers — bitmap now, SDF later

The decision that matters for text is **NOT** "2D text vs 3D text" — it's **bitmap atlas vs SDF**. Every engine surveyed (Bevy, Unity, Godot, Heaps) shares **one** font/glyph/shaping/atlas layer and exposes only **thin per-context consumers** on top. The "2D/3D split" is cosmetic (component/node types per render path), not two text systems.

| Engine | Shared font layer | 2D / UI consumer | 3D / world consumer | Atlas |
|---|---|---|---|---|
| **Bevy** | `bevy_text` (cosmic-text + `FontAtlasSet` → `TextLayoutInfo`) | `Text` (UI) | `Text2d` (world 2D; **no** 3D-mesh text) | bitmap |
| **Unity TMP** | Font Asset + SDF + TMP shader | `TextMeshProUGUI` | `TextMeshPro` (MeshRenderer) | **SDF** |
| **Godot** | `TextServer` (shape + raster) | `Label`, `RichTextLabel` | `Label3D` (billboard) + `TextMesh` (extruded geometry) | bitmap (MSDF opt) |
| **Heaps** | `h2d.Font` (BMFont/SDF atlas) | `h2d.Text`, `h2d.HtmlText` | DIY (HUD overlay / billboard quad) | bitmap (SDF via tool) |
| **Void** | **fontstash** (atlas + layout → quads) | **void2d** ✅ | void3d (→ [VOID3D.md](VOID3D.md)) | **bitmap → SDF when 3D** |

**Why glyphs are the same in 2D and 3D:** text is always rasterized to an atlas texture; each character becomes a **textured quad with UVs**. The only difference is *where the quads sit + which pipeline draws them*: 2D = screen/pixel space, orthographic, crisp 1:1, z by draw order; 3D = world space through the camera MVP, perspective + depth-tested (billboard quad, or extruded mesh).

**The real fork — bitmap vs SDF:** a bitmap atlas (fontstash default) is **crisp for fixed-size 2D UI** (1:1 pixel mapping — exactly Neon's need) but **blurs / jaggies under scale or 3D perspective** (Flax users hit "jagged fonts on 3D walls"; Roblox hits atlas-overflow flicker). World-space / heavily-scaled text wants **SDF** (Unity adopted SDF specifically for this; the high end is GPU-from-outline, e.g. Slug / TextMeshDOTS).

**Void's call:**
1. **Shared glyph layer, not two text systems.** fontstash does shaping + atlas + glyph quads once; consumers stay thin (matches Bevy/Unity/Godot/Heaps).
2. **fontstash (bitmap) → void2d now.** Neon UI = fixed-size screen text → bitmap is crisp, lean, proven. Correct first step.
3. **Keep the glyph layer backend-neutral** — it emits `quad + UV + atlas`, NOT screen-space-coupled geometry. So when void3d wants crisp world-space labels, it **swaps the atlas to SDF and feeds the same glyph quads through the 3D MVP** — no rearchitecting. The bitmap→SDF upgrade and the 3D-text consumer are deferred to [VOID3D.md](VOID3D.md).

This is "the Heaps way" only in the sense that the shared-font-layer + thin-consumers pattern is industry-universal — it is **not** a Heaps-specific tradeoff. The one thing Void does better than Heaps from day one: keep the glyph layer render-path-neutral so the 3D/SDF door stays open.

## Scope discipline

void2d = unified 2D **draw primitives** (rects, sprites, text, clip, transform, batching) + a retained node tree for the reconciler. It is **not** a UI framework: no flexbox layout, no event system, no declarative components — those live in Neon (above) and the JSX/Solid layer (which reconciles onto void2d's `Node2D`). Keep the narrow waist.
