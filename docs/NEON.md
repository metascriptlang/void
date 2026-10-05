# Neon on Void

What Neon builds on Void, in the syntax an app author writes, and what Void still has to add for
it to ship. Decided with the person on 2026-10-03 in a Neon session. Neon's own record of the same
model is `neon/docs/VISION.md` "Inside a Void area"; Neon reads this file for Void's side.

Every Void pointer below was read on Void's `main` at `fc6efe0`; "What Neon builds now" and items 1,
2 and 8 were read again at `89981dd`.

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

Neon's void host (`neon/src/platform/void/host.ms`) is still written against `Node2D`, which P5
step 6 deleted, so it does not build on Void's `main`. It also keeps its own parent links, sums
x/y into world positions, measures text through its own `MeasureText` callback, tracks dirtiness
with `onDirty`, and maps every element tag to an empty group. Its rewrite is Neon's card
`~/metascript/.wt/void-noderef-host.md`, written against the contract below. This contract replaces
the host API note approved on 2026-09-30 (`~/metascript/.inbox/neon/2026-09-28-void2d-noderef.md`),
which never left the Windows machine.

### The 2D host contract

- **A host owns one `Scene2D`, and its elements hold `NodeRef` handles.** The types are
  `src/void2d/node.ms` `Scene2D`, `NodeRef` and `NodeId2D`. Construction and the frame calls are
  extensions in `src/void2d/scene.ms`, so the host imports that module too. A Neon `HostNode`
  keeps the handle, not a node object. Handles compare with `==`, and a disposed handle stops by
  name on its next use. Events, focus, text-input clients and dispatch order stay in Neon: a
  rendering handle owns no registry.
- **Every write goes through a binder** (the `set*` extensions in `node.ms`). The readers
  (`local()`, `paint()`, `textStyle()`, …) return value groups, so changing a returned group is
  not a node write and the scene never sees it. Paint, transform, order, content and text-style
  writes return early on an equal value (`putPaint`, `putLocal`, `putOrder`, `putContent`,
  `putTextStyle`), so writing an unchanged prop costs nothing.
- **A View is created with `group()` and gets its paint later.** `setBackground` and
  `setBoxStyle` promote it to a Rect on the same row, and `clearBackground` demotes it (item 8
  below). The handle, children and layout survive both. Making every View a Rect up front would
  emit an instance for every transparent box.
- **The tree is Void's.** `addChild`, `addChildAt`, `remove`, `parent`, `getChildAt`,
  `getChildIndex` and `numChildren` replace the host's parent-link map. `remove` detaches and
  keeps the handle valid, so a keyed move is `addChildAt` on the new parent, and a cycle stops by
  name. `dispose` frees the whole subtree and is for unmount only. A node's world position is
  `localToGlobal(vec2(0.0, 0.0))`, live right after the writes. It is not the sum of
  translations once rotation, scale, pivot or scroll apply.
- **Geometry and text measurement are Void's** (`src/void2d/render.ms`). Pointer hit-testing
  uses `hitTest(vec2(x, y))` in scene coordinates. It applies live transforms, ancestor masks and
  scroll, and rejects hidden nodes. It tests content bounds, not texture alpha. A `TextInput`
  places its caret and maps a press with the painted label's own layout: `xForIndex`, `lineBoxAt`
  and `indexAt` (UTF-16 indices), plus `textWidth` and `textHeight`. `calcTextWidth` measures
  other, unwrapped text in that label's font. Neon removes `MeasureText` and its `noMeasure` path
  rather than keep a second measurer that can disagree with what is drawn. Caret and selection
  padding are paint, not content bounds, so IME placement reads the text geometry, never render
  bounds.
- **Frames are on demand, and the scene says when.** After input and layout, request a frame only
  if `isDirty()` is true: a node or tree write, the camera, the default sampler, or a scene never
  painted. It replaces the host's `onDirty` bookkeeping. `isDirty()` cannot know about the surface,
  so first paint, size, DPI, the clear colour, a recreated surface and lost GPU contents stay the
  host's to invalidate. `present()` and `presentAt(dpi)` open and commit the screen pass. Over a 3D
  frame, call `prepare(w, h, dpi)` before any screen pass and `drawScreen()` inside the caller's
  pass, never `present()` nested in it. `w` and `h` are logical units: framebuffer pixels divided
  by DPI.
- **Warm only the blend modes the host draws with.** After `setup2d()`, call
  `preparePipelines([BlendMode.Alpha])` (`src/void2d/draw.ms`; `BlendMode` is in
  `src/gpu/state.ms`), adding another mode only when the host uses it. It warms the screen and
  offscreen variants and the blur pipeline. Warming every mode is wrong: the slots exceed the
  native pipeline pool (`docs/VOID2D.md` "D1 as built"). Without warmup, pipeline creation lands in
  the first presented frame. The D3D11 numbers are in the same section and do not promise anything
  for another driver.
- **A scene cannot be torn down for good yet.** Disposing nodes frees their rows, but a dropped
  `Scene2D` keeps its retained GPU lists (`docs/VOID2D.md` "Known defects", P5 review B1). A host
  that would create a scene per window or per texture keeps it alive until B1 lands.

The rewrite is proven by its consumers, not by compiling. A keyed move keeps its handles. Pointer
tests on transformed, scrolled and masked nodes hit what is drawn. The real `TextInput` caret
matches the painted text. The host keeps no dirty flags and no measurer of its own. Startup warms
its pipelines. The tiers are in `docs/TESTING.md`.

### The 3D components

The 3D components follow Void's own model: owners made with `T.create` and ended with their
`close` in the component's cleanup, handles as values, and each reactive prop written through one
binder (`setLocal`, `setVisible`, `setLightPower`), so an unchanged value costs nothing. The Neon
session builds next, using only what is on Void's `main`:

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

1. **Draw a `Scene2D` into a render target the caller owns.** On `main` at `2bd7a9b`:
   `src/void2d/scene.ms` `drawTarget`, using existing prepared replay.
   During `openPrepare` … `closePrepare`, prepare at the target's pixel size divided by DPI,
   then draw it. The call opens and closes its own pass, never commits, and consumes that
   same-frame preparation just as `drawScreen` does. Existing filter targets finish in prepare.
   Refused targets and lifecycle misuse stop by name; `tests/integration/sceneTarget.ms` is the
   native consumer and `scripts/gate.sh` runs its pixel comparisons and misuse cases.

   The redraw policy stays the caller's: `isDirty()` does not know that an image was recreated.
   Remember the last drawn `target.image` or attachment as well; resize can replace both while
   `RenderTarget.generation` stays unchanged (that field names the GPU context, not a resize).
   Owner identity stays stable through resize; it is not a cache-validity key for the image.
   A recreated target must be drawn even when the scene is clean. The native consumer proves
   idle, same-size recreation, resize, @2× and @1.5× DPI, and post-prepare writes.
   The caller must also invalidate when its DPI or clear input changes; those host inputs are
   not node mutations tracked by `isDirty()`. `drawTarget` itself adds no scheduling policy.

   Reference read: Heaps `h2d/RenderContext.hx` `pushTarget`/`popTarget` at `b9aa6dcb`; Bevy
   `examples/ui/render_ui_to_texture.rs`. drei `bf6f4ad` `src/core/RenderTexture.tsx` `Container`
   renders a portal scene into its FBO, restores the outer target and gates by `frames`;
   `src/core/Fbo.tsx` sizes the FBO by DPR. r3f `d604b18` `packages/fiber/src/core/store.ts`
   `frameloop`/`invalidate` puts demand policy at the caller, not at the texture.
2. **A material that samples a render target safely.** `Material.texture` is a `TextureId` made
   from uploaded pixels, generation-checked; `texture0` … `texture3` take raw view ids with no
   generation (`src/void3d/material.ms`). `RenderTarget.asTexture` gives a view
   (`src/gpu/target.ms`), and that view changes when the target is resized or the context is
   lost. Needed: a context texture whose image is a render target, so a material names it
   through the same checked `TextureId` and survives a resize. Heaps: a `Texture` with the
   `Target` flag is both (`h3d/mat/Texture.hx`).

   The target-owner prerequisite is on `main` at `6d68e8a`: `src/gpu/target.ms`
   `RenderTarget` shares one owner across aliases, resizes in place and closes terminally.
   Heaps `Texture.resize` and three `RenderTarget.setSize` keep that object identity;
   Void reuses its PipelineCache/M25 reference-owner model. The native lifecycle consumer is
   `tests/integration/targetOwner.ms`. This does not complete item 2: a material still needs
   M27's checked texture row that resolves the owner's current view rather than a saved raw id.

   **Answer, M27 (branch commits `b2570ef` + `92fcf79`, not yet landed):** `src/void3d/draw.ms`
   `addTargetTexture(context, target, filter, wrap, TextureAlpha.Premultiplied)` gives a
   `TextureId` in the same checked space as an uploaded image, and a material names it as
   `Material.texture`. The slot holds the `RenderTarget` owner, not a view: the view is read at
   every bind, so `resize` (new image, same owner) keeps the material drawing with no rebind.
   After a lost context the material draws nothing until the owner resizes the target, and Neon
   then redraws the UI into it, which item 1's rule already requires. A redraw of a sampled
   target is not a 3D scene change: call `markChanged` on the 3D renderer when the frame is on
   demand. Closing the target while a material samples it stops by name (release the material
   first), and so does sampling it inside a pass that draws into it, before sokol.
   Evidence: [VOID3D.md, M27 as built](VOID3D.md#m27-as-built).
3. **A textured program without lights.** Implemented by M28 in branch commit `e80a077`,
   not yet landed; see `src/void3d/gpu3d.ms`
   `Program.UnlitTextured`; the pixel-art map chooses its MRT twin. Material colour
   uses the existing material-owned block ABI, with the offsets/length named in gpu3d.ms.
   The unlit texture keeps its authored colour when the scene goes dark; the real
   forward/pixel-art consumer and its old-lit failure control are recorded in
   [VOID3D.md, M28 as built](VOID3D.md#m28-as-built). Premultiplied target input is still
   items 2/5 (M27), not silently inferred by this program.
4. **The UV of a pick hit.** Implemented by M29 in rebased branch commit `4ce6f8f`, not yet
   landed. The query is `src/void3d/pick.ms` `PickHit.uv`;
   the query keeps authored `TEXCOORD_0`, without wrap or clamp, and a mesh without that
   attribute still hits with `uv == null`. Neon maps that coordinate into the texture's
   UI hit test. Reference: three.js `Mesh.js` `checkGeometryIntersection` and `Triangle.js`
   `getInterpolatedAttribute` at `d4ea9b9`; the arithmetic and real pressed-pixel evidence
   are in [VOID3D.md, M29 as built](VOID3D.md#m29-as-built).
5. **Premultiplied alpha and colour space across the boundary.** Read for item 1 on 2026-10-03:
   `src/void2d/shader2d.glsl` emits gamma-encoded RGB multiplied by alpha, and
   `src/void2d/draw.ms` `premultipliedBlend` blends those values into an Rgba8 UNORM target
   (`src/gpu/door.c` `doorMakeTargetImage`), not an sRGB-format attachment. Item 1 also
   premultiplies the clear. Native readback holds a transparent coloured clear at `(0,0,0,0)`
   and a half-red interior at `(128,0,0,128)`; target replay and direct screen replay agree.

   **Material side still open for items 2/3/5:** `src/void3d/shader3d.glsl` and
   `src/void3d/pixelArt3d.glsl` `litTexturedFs` treat sampled RGB as straight before sRGB decode.
   They cannot yet sample these UI targets correctly. Unpremultiply encoded RGB before any
   nonlinear decode (zero alpha yields zero RGB), then apply the material's declared colour
   processing and premultiply the encoded output when its blend expects it. Do not decode
   already-premultiplied channels or multiply coverage twice. This slice establishes the
   producer's contract; it does not claim that a 3D material already honours it.

   **Material side answered by M27:** a void2d target is declared `TextureAlpha.Premultiplied`
   and sampled by `Program.UnlitTexturedPremultiplied` (a screen keeping its authored colour,
   item 3) or `Program.LitTexturedPremultiplied` (lit with the scene), blended
   `BlendMode.AlphaAdd`; any other pairing is refused by `addMaterial` with a named
   `MaterialError`. The program unpremultiplies before decoding and premultiplies its output:
   the half-red texel (128, 0, 0, 128) draws red exactly 128 over black, and a zero-alpha texel
   leaves what is behind it byte-exact, on both presets.
6. **A camera placed by a node's world transform.** Implemented by M30 in branch
   source commit `971ee3d`, not yet landed. Use `src/void3d/camera.ms`
   `Camera3D.fromWorld`, or `src/void3d/scene.ms` `SceneCamera` / `cameraOf`
   for an active Group-bound mount; Neon does not extract yaw/pitch or discard roll.
   The existing camera request still supports its yaw/pitch convenience path.
   Parent scale is excluded, stale/closed mounts fail loudly, and the measured
   rolled orthographic pixel-art snap remains supported rather than refused.
   Reference rationale, numerical rejection boundary and final native proof:
   [VOID3D.md, M30 as built](VOID3D.md#m30-as-built).
7. **Create a node before its parent, and move it.** Implemented by M31 in branch
   source commit `32f0f9c`, not yet landed. `src/void3d/scene.ms`: the four
   `add*Node` factories take `parent: NodeId3D | null` (old calls compile
   unchanged); `attach(scene, parent, node)` moves a node with its local pose,
   ids, pins, bound animation, camera binding and pick ownership intact;
   `insertBefore(scene, parent, node, before)` places it among its siblings, and
   the order is observable in equal-depth draw order. Detached rows draw, light,
   pick and sync nothing; `worldOf` answers `DetachedNode` and an active detached
   camera `DetachedCameraNode`. Misuse — root, cycle, foreign or stale ids, a
   `before` under another parent — stops by name; `closeScene` releases
   never-attached forests. Measured red and native proof:
   [VOID3D.md, M31 as built](VOID3D.md#m31-as-built).
8. **A View that starts as a pure group and only draws once it has paint.** A Neon View is a
   group until it gets a background, a border or a shadow; void2d fixes `DrawKind` at
   construction (`node.ms` `newRow`), and `setBoxStyle` requires a Rect, so Neon must either
   make every View a Rect (render.ms's Rect branch then emits an instance even for a
   transparent fill) or recreate the node and break the NodeRef its binders hold. Wanted: an
   optional paint on the same row — a fill or a box style promotes a Group to a drawing node
   in place (same row, NodeRef, children, layout, order, alpha); clearing returns it to Group
   and frees the box style; only a Group or a Rect may change, any other kind stops by name;
   a fully transparent fill with no border and no shadow emits nothing.

   References: React Native `18f5ddb` `ViewShadowNode.cpp` `formsView` — a view forms a host
   view when its background colour is meaningful, it has a border, a box shadow or the like;
   the same shadow node either way. GPUI `b961b49` `style.rs:713-714` paints the background
   only when it is set and not transparent. Flutter `6f0e0db` `container.dart:405` inserts a
   `ColoredBox` only `if (color != null)`. Heaps `b9aa6dcb` `Flow.hx:1115` `set_backgroundTile`
   builds and removes a ScaleGrid child lazily — Void's divergence is to keep one row instead
   of adding a child, so the layout size needs no sync.

   **Answer, on `main` at `dabfdbc` + `e5602f5`:** `setBackground`, `clearBackground` and
   `setBoxStyle` promote and demote a Group↔Rect on the same row (`node.ms` `takePaintable`);
   the NodeRef, children, layout, order and alpha are untouched, any other kind stops by name,
   and a transparent fill with no border and no shadow emits nothing. Promotion always starts
   from a transparent fill and clearing resets it, so a border-only View never shows a white
   interior (the React Native reading). `setBackground` on a Rect made by `rect()` keeps
   today's behaviour — it just sets the colour (GPUI `style.rs:713` paints whatever background
   is set); `clearBackground` on such a Rect demotes it to a Group, as Flutter's `ColoredBox`
   exists only while a colour is set. Native consumer `tests/integration/viewPaint.ms`
   (gate.sh): pixels after promote and demote, a child kept over both, a transparent
   background emitting zero draws, a border-only interior showing the background through it,
   and a label background stopping by name. The harness refuses a framebuffer smaller than
   requested, naming both sizes: Windows enforces a minimum client width, which once read as
   a phantom 2× placement.

Done when each item has a commit on Void's `main` or an answer that Neon does it on its side,
written under its number here, and a note in `~/metascript/.inbox/neon/` names the commits.
