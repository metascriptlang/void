# Neon on Void

What Neon builds on Void, in the syntax an app author writes, and what Void still has to add for
it to ship. Decided with the person on 2026-10-03 in a Neon session. Neon's own record of the same
model is `neon/docs/VISION.md` "Inside a Void area"; Neon reads this file for Void's side.

Every Void pointer below was read on `origin/main` at `75b0d19`.

## The intent

A Neon app opens a Void area with `<Void>`, a tag laid out like `View`
(`neon/src/components/primitives.ms` `Void`, over the optional `Host.voidArea` in
`neon/src/render/hostTypes.ms`). Inside the area Void draws every pixel.

Inside a Void area there are two vocabularies, and the author always knows which one they are in:

- **3D is written in 3D's own terms.** Mesh, material, texture, camera, light: the author learns 3D
  as it is, and the tags carry the names of Void's own types, so a reader of Neon code and a reader
  of Void code call one thing by one name.
- **Application UI starts at a `View`.** Inside a `View` nothing is new: it is the same React-style
  UI as on every other Neon host, made seamless by Neon.
- **The one place the two meet is a texture.** 2D enters 3D the way every engine read for this
  does it: a `View` is drawn into a texture, a material samples the texture, a mesh carries the
  material.

## The syntax

```tsx
<Void style={{ flex: 1 }}>
  <Scene3D>
    <Camera3D active position={[0, 3, 8]} />
    <Light kind="directional" />
    <Mesh geometry={quad} position={[0, 2, 0]} rotation={[0, 0.4, 0]}>
      <Material>
        <Texture width={600} height={400}>
          <View style={{ flex: 1, padding: 24 }}>
            <Text>Shop</Text>
            <Pressable onPress={buy}><Text>Buy</Text></Pressable>
          </View>
        </Texture>
      </Material>
    </Mesh>
  </Scene3D>
  <View style={{ position: "absolute", top: 8, left: 8 }}>
    <Text>HP: {hp()}</Text>
  </View>
</Void>
```

- **`View`, `Text`, `Pressable`, `TextInput` are void2d, nothing more.** Where one is placed decides
  what it is. Directly in `<Void>` it is HUD: 2D drawn onto the screen, laid out by yoga over the
  area, moved by no camera. Inside a `<Texture>` it is 2D drawn into that texture. Inside a
  `<Scene2D>` it is void2d under that scene's camera.
- **The 3D tags are Void's types.** `Scene3D` is `src/void3d/scene.ms` `Scene3D`; `Group`, `Mesh`
  and `Light` are its `addGroup`, `addMeshNode`, `addLightNode`; `Material` is
  `src/void3d/material.ms` `Material`; `Camera3D` is `src/void3d/camera.ms` `Camera3D`; `Scene2D`
  is `src/void2d/node.ms` `Scene2D`. `Texture` is a texture whose pixels a `View` draws. If Void
  renames one of these, Neon renames the tag.
- **Transforms place 3D objects; yoga lays out 2D boxes.** Nothing in a `Scene3D` takes part in
  flexbox. Every 2D root, the HUD and each texture's `View`, is its own yoga root, sized by the
  area or by the texture.
- **A camera sits in the tree like any object.** A camera that follows a character is a
  `<Camera3D>` nested under the character's `<Group>`.
- **The HUD draws over the 3D scene in the same frame**, as M18 composes them
  (`docs/VOID3D.md` "M18 as built").
- **A press on the mesh reaches the `Pressable` inside the texture.** The pick ray hits the mesh,
  the hit's UV becomes a pixel of the texture, and that pixel goes through the same void2d hit test
  as the HUD.
- **One owner tree.** Signals and context reach the `View` inside a texture exactly as they reach
  the HUD. A texture is drawn again only when something in its `View` changed; an idle scene draws
  nothing.
- **The author sees the real cost.** UI that looks soft up close needs a larger `Texture`, not a
  different `View`. That is why the texture is a tag of its own instead of being hidden inside the
  material.

Each tag has a fixed set of parents, checked by Neon: void2d tags live in `<Void>`, a `Texture`, a
`Scene2D` or another void2d node; `Group`, `Mesh`, `Light`, `Camera3D` live in a `Scene3D` or
under a 3D node; a `Material` lives in a `Mesh` and a `Texture` in a `Material`.

## Rejected, each with the source that ruled it out

- **R3F's default, where everything inside the canvas is the 3D world.** `<Canvas>` creates a
  scene and a perspective camera and mounts its children into the scene (`react-three-fiber`
  `packages/fiber/src/core/configuration.ts`, the default camera and scene, at `d604b18`). A
  `View` in a Void area would stop being HUD, and HUD would need drei's `Hud`, a portal into a
  second scene with no layout (`drei` `src/core/Hud.tsx` at `bf6f4ad`). HUD by default is Bevy's
  model: a UI root draws onto the default UI camera through its own orthographic projection and
  ignores the camera's transform (`bevy` `crates/bevy_ui_render/src/lib.rs`
  `extract_ui_camera_view` at `2bddbdfd7`).
- **A 3D scene nested inside a `View`**, as Godot's `SubViewportContainer` (`godot`
  `scene/gui/subviewport_container.cpp` at `e7cfa29`) and drei's `View` (`src/web/View.tsx`) do.
  It makes the UI tree own a world and leaves the draw order of HUD, scene, HUD siblings
  undefined.
- **`World3D` as the tag.** Godot's `World3D` is a resource, not a node; Void's type is `Scene3D`.
- **Yoga on 3D objects.** `react-three-flex` (last commit `13e4b2d`, December 2022) must pick a
  plane and take an explicit size, because flexbox has two axes. Bevy runs taffy over UI nodes
  only (`crates/bevy_ui/src/layout/mod.rs` `ui_layout_system`); Godot has no 3D container.
- **3D props on `View`.** `View` runs on every Neon host, and its `transform` style is 2D.
- **A panel node that draws void2d quads straight through the 3D camera,** as uikit does, where
  every component is a three `Mesh` (`uikit` `packages/uikit/src/components/component.ts` at
  `7fbb8bb`). Text stays sharp at any distance, but it hides the texture and adds a node kind 3D
  does not have; the person chose the texture so that the author learns 3D as it is. Void's own 3D
  text may still take that path inside Void ("Deferred from void2d: 3D text + SDF" in
  `docs/VOID3D.md`).

## What Neon builds now, on what Void already has

Neon's void host (`neon/src/platform/void/host.ms`) maps every element tag to an empty void2d
`group()` today, and Neon's Ion window draws one `Scene2D` with `present()`
(`neon/src/platform/ion/window.ms`). The Neon session builds next, using only what is on Void's
`main`:

- `Scene3D`, `Group`, `Mesh`, `Light` through `src/void3d/scene.ms`; geometry from
  `src/void3d/meshData.ms` (`addBox`, `addPlane`, `addTexturedQuad`, `addTexturedCube`) and glTF;
  image textures from M22 and M23.
- `Camera3D` as the active camera of a `Scene3D`.
- The HUD over the scene in one frame: the renderer's `openPrepare` / `closePrepare` /
  `openScreen` / `drawScreen` (`src/void3d/renderer.ms`) with void2d's `prepare` / `drawScreen`
  (`src/void2d/scene.ms`) in place of `present()`.

So these signatures are now consumed from Neon. A change to them reaches `neon/src/platform/void/`
and `neon/src/platform/ion/window.ms`; say so in `~/metascript/.inbox/neon/`.

## What Void has to add for this to ship

In order. 1, 2 and 4 block UI on a mesh; 3 and 5 make it right to look at; 6 and 7 let the JSX
above be written without Neon working around Void.

1. **Draw a `Scene2D` into a render target the caller owns.** Today `Scene2D.prepare` paints and
   `drawScreen` draws into the open screen pass; `presentAt` opens and commits the screen pass
   (`src/void2d/scene.ms`). `beginTarget` / `endTarget` (`src/void2d/draw.ms`) draw into a target,
   but only for a node's filter. Needed: prepare a `Scene2D` at a target's size and DPI and draw
   it into that target, during the 3D prepare phase (M18's `openPrepare` … `closePrepare`), and
   only when `isDirty` says it changed. Heaps: h2d draws into an h3d texture through
   `h2d/RenderContext.hx` `pushTarget` (`heaps` at `25f9a88f`). Bevy: a UI root targets a camera
   whose `RenderTarget::Image` is then a material's texture (`examples/ui/render_ui_to_texture.rs`).
2. **A material that samples a render target safely.** `Material.texture` is a `TextureId` made
   from uploaded pixels, generation-checked; `texture0` … `texture3` take raw view ids with no
   generation (`src/void3d/material.ms`). `RenderTarget.asTexture` gives a view
   (`src/gpu/target.ms`), and that view changes when the target is resized or the context is
   lost. Needed: a context texture whose image is a render target, so a material names it
   through the same checked `TextureId` and survives a resize. Heaps: a `Texture` with the
   `Target` flag is both (`h3d/mat/Texture.hx`).
3. **A textured program without lights.** `Program` has `LitTextured` and `PixelArtLitTextured`
   and no textured program that skips lighting (`src/void3d/gpu3d.ms`). A screen or a sign in the
   world must not be darkened by the scene's lights. Heaps: a pass turns lighting off with
   `enableLights` (`h3d/mat/Pass.hx`).
4. **The UV of a pick hit.** `PickHit` carries `owner`, `mesh`, `distance`, `point`
   (`src/void3d/pick.ms`). Needed: the UV interpolated over the hit triangle's UVs, so Neon can
   turn a press on the mesh into a pixel of the texture.
5. **Premultiplied alpha and colour space across the boundary.** A void2d render target is
   premultiplied (`docs/VOID2D.md`, the closed "Filter semantics differ from h2d" item). The
   material that samples it has to blend it as premultiplied, and the two sides have to agree on
   sRGB, or the edges of UI on a mesh fringe and its colours shift. Not read yet; check before 1
   and 2 land.
6. **A camera placed by a node's world transform.** `Camera3D` is `position`, `yaw`, `pitch`
   (`src/void3d/camera.ms`) and is not a node (`NodeKind` is `Group`, `Mesh`, `Light`). A
   `<Camera3D>` nested under a moving object needs its position and orientation from the parent's
   `worldOf`. Neon can derive position and yaw/pitch itself, losing roll. Wanted: a camera node,
   or a `Camera3D` made from a world matrix. Bevy: a camera is an entity with a `Transform` and a
   parent; Godot: `Camera3D` is a node.
7. **Create a node before its parent, and move it.** `addGroup`, `addMeshNode` and
   `addLightNode` take the parent at creation, and there is `remove` but no re-parent
   (`src/void3d/scene.ms`). Neon's `Host` creates an element first and attaches it later, and a
   keyed list moves rows (`neon/src/render/hostTypes.ms` `Host`). Neon can defer creating the Void
   node until it is attached, but a move between parents then means remove and add again, which
   drops what the node holds (its pin, a bound animation). Heaps: `addChildAt` moves an object
   from its old parent and keeps it allocated (`h3d/scene/Object.hx`).

Done when each item has a commit on Void's `main` or an answer that Neon does it on its side,
written under its number here, and a note in `~/metascript/.inbox/neon/` names the commits.
