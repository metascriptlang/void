# Embedding Void in a host

A host that owns the window and the frame clock (Ion on Windows and macOS, a React-Native
`VoidView` on iOS, a `SurfaceView` on Android) drives Void through **views**. The entry points are in
`src/sokol/bridge.h` (`voidEmbedRegister`, `voidViewCreate`, `voidViewResize`,
`voidViewFrame`, `voidViewDestroy`, `voidViewSwapChain`, `voidCurrentView`), and MetaScript
reaches them through `src/sokol/gpu.ms` (`embedRegister`, `viewCreate`, …). The shared part is
`src/sokol/views.c`; each platform's half is the `voidPlatform*` set in `bridgeWin.c`,
`bridgeIos.m`, `bridgeEmbed.m` (macOS), `bridgeAndroid.c` and `bridgeWeb.c` (browser).

The split follows `neon/docs/VISION.md` "Many Void areas in one app": the device, pipelines,
shaders, glyph atlas and textures exist once per process, and each view owns its surface, its
pixel size, its DPI scale and its frame policy.

## The frame scope

`voidViewFrame(v)` makes `v` the current view, calls the registered frame closure, and
expects the closure to end in `commit()`, which presents `v` and clears the current view.
`fbWidth`, `fbHeight`, `dpiScale` and `beginPass` read the current view. Called outside a view
frame, they abort with a message that names the call. A closure that returns without
`commit()` also aborts.

Void2d's API did not change for this: `Scene.present()` reads the size and the DPI scale of
whatever view is current.

Several layers can share one view frame. Each layer's offscreen passes run first, then one screen
pass that a 3D preset and void2d both draw into, then the one `commit()` (docs/VOID3D.md, M18 as
built). A layer that refuses its frame skips only its screen half: the screen pass and the commit
still happen, or the view frame aborts.

**Why this shape.** Three options were weighed on 2026-09-24:

- *A current view that persists across frames*, as `wglMakeCurrent`/`eglMakeCurrent` and D3D11's
  `OMSetRenderTargets` do. Rejected: a caller that forgets to switch draws into the wrong
  window, and nothing reports it.
- *The view id passed to every call* (`fbWidth(v)`, `beginPass(v, …)`, `commit(v)`), as bgfx
  views and Flutter's multi-view `render(scene, view)` do. Rejected: every signature in
  void2d, the examples and the bridges would change, and Neon's use of void2d with them.
- *Explicit at the start of the frame, implicit inside it, cleared at its end* (chosen). This
  is sokol's own model: `sg_begin_pass` takes the swapchain, and every call up to
  `sg_end_pass` means that pass. Metal and WebGPU do the same through their drawable and
  pass encoder.

Of these references, only sokol was read at source (`sg_swapchain` in the pinned
`sokol_gfx.h`). The others are cited from their documented models.

## Windows: two drivers in one binary

`bridgeWin.c` holds both the sokol_app window driver (`voidRun`, used by the demos, the golden
runner and the benches) and the host-view driver. The first of `voidRun` or `voidViewCreate`
chooses the driver for the process. The other then aborts, and every frame call that runs
before either aborts too.

A `-d:` build flag that picked one of them at compile time was rejected: each consumer
(Neon, Terminator) would have to pass it, and the gate would need two builds to cover both
drivers.

The view driver creates one `ID3D11Device` (feature levels 11.1 then 11.0, like sokol_app),
and one `IDXGISwapChain1` per view through `CreateSwapChainForComposition`: B8G8R8A8,
premultiplied alpha, flip-sequential, two buffers, `DXGI_SCALING_STRETCH`. Ion creates no surface
for it: a window is an empty DirectComposition root (`ionWindowRoot`, `ionWindowDevice` and
`ionWindowCommit` in `ion/src/platform/bridge.h`; why, in `ion/docs/WINDOW-CONTENT.md`). The host
creates a visual on `windowDevice(win)`, `SetContent`s the view's `viewSwapChain` onto it, parents
it under `windowRoot(win)` and calls `commit(win)`: `swapChainVisualAttach` in
`examples/swapChainVisual.cpp`, and Neon's `voidVisualAttach` in
`neon/src/platform/ion/voidVisual.cpp`. `AddVisual` with a NULL reference inverts `insertAbove`
(Ion's "Traps"), so `FALSE` puts the new visual in front of its siblings. Each view presents with
sync interval 1. With two views redrawn in the same tick, each `Present` waits for vblank, and
that has not been measured. Ion's per-window frame clock (`setFramePolicy`, `requestFrame`,
`onFrame`) owns pacing.

A view's clear alpha reaches the compositor. Clear to `rgba(0, 0, 0, 0)` to let the visuals
below show through, as the overlay in `examples/ionViews.ms` does.

## macOS: two drivers in one binary

`bridgeEmbed.m` follows `bridgeWin.c`: `voidRun` (a Cocoa window, no sokol_app) and the host-view
driver share one process, the first of the two chooses, and the other aborts. Both draw through
the door's Metal backend (`src/webgpu/metal/`); `bridge.c` and `views.c` are compiled beside it.

`native` in `viewCreate` is an `NSView*` or 0. With a view, Void adds a `CAMetalLayer` as a
sublayer of the view's layer (it sets `wantsLayer`), sized to the view's bounds at every
`viewResize`, and removes it on `viewDestroy`; the host's own layer is not replaced. With 0, Void
makes the layer and attaches it nowhere: `viewSwapChain` returns the `CAMetalLayer*`, as it returns
the `IDXGISwapChain1*` on Windows, and the host adds it to its own layer tree. `w` and `h` are
pixels. `tests/integration/macViews.ms` creates both and checks sizes, resize and destroy, with no
pixel readback because the Metal capture path is a stub.

## iOS: an app driver on the host views

`bridgeIosApp.m` gives iOS a `voidRun`, so an entry written for `voidRun` (Neon's `runCanvas`)
runs as a full-screen UIKit app. sokol_app's iOS path was not used: it has no marked text and no
hardware-key presses, which a terminal and an editor need. The driver is a host of the view
driver in `bridgeIos.m`: its one `UIView` calls `viewCreate`, `viewResize` and `viewFrame` from a
`CADisplayLink`, and it builds `VoidAppEvent` values (`src/platform/appEvent.h`) and hands them to `appWindow.c`, so
`window.ms` reads them as on Windows and the web.

- `voidRun` enters `UIApplicationMain` and does not return. The app's `main()` calls `MsMain`
  (`src/examples/iosAppEntry.m`), as Neon's iOS entry does.
- Touches arrive in framebuffer pixels in `AppEvent.touches`, with `changed` set on the touches
  that moved; `safeArea()` gives the insets in pixels and `keyboardHeight()` how far a docked
  software keyboard covers the view (0 hidden or floating), both changing with a `Resized` event.
- A hardware key gives `KeyDown`/`KeyUp`; Backspace repeats while held. Typed text gives `Char`
  per codepoint while text input is off, and `TextInput` plus `Preedit` for marked text while
  `setTextInput(true)`; only then does the software keyboard show.
- Demo: `src/examples/iosApp.ms` logs every event; a tap toggles text input.

## Web: a view per canvas

`bridgeWeb.c` follows `bridgeWin.c` too: the sokol_app canvas (`voidRun`) and the host-view
driver share one document, and the first chooses. A page does not call `viewCreate` itself.
The entry calls `embedRegister` (`gpu.wms`), which also defines `Module.voidStart(canvas)`; that
starts a view on the canvas and returns its `stop`. A page may start and stop views any number
of times in one document, as a Neon route does when it is left and entered again.

The shape is React Three Fiber's (d604b18): one runtime per document, one root per canvas
(`core/root.tsx:31,235-260`), one animation-frame loop over the live roots that cancels itself
when none is left (`core/loop.ts:95-130`), and an unmount that disposes the renderer and forces
its context lost (`core/renderer.ts:22-42`). Emscripten's `MODULARIZE` was rejected: it builds a
second runtime per mount, which none of R3F, Three.js or Heaps does.

- The canvas reaches C as an id. `voidStart` registers it in emscripten's `specialHTMLTargets`
  under `#void-view-<id>`, the selector both the WebGPU surface and the WebGL2 context resolve.
- WebGPU: one device for the document, requested by `voidStart` into
  `Module.preinitializedWebGPUDevice` unless the page put one there, and read by
  `emscripten_webgpu_get_device()` (emdawnwebgpu `library_webgpu.js:650`). Each view configures
  its own canvas surface; `stop` unconfigures it.
- WebGL2: a context belongs to its canvas, so the device is the one live view's context, and a
  second live view aborts by name. `stop` shuts sokol down, calls
  `WEBGL_lose_context.loseContext()` and destroys the context. The next view sets sokol up on its
  own context and bumps the GPU generation, as Android's context restore does
  (`bridgeAndroid.c` `restore_context`): `contextGeneration()` owners drop their old ids.
- The view's pixel size follows the canvas's CSS size times `devicePixelRatio`, read every frame.

## What proves it

- `tests/integration/twoViews.ms` in the gate: two windowless views (480×300 at scale 1.0,
  600×330 at 1.5) in one process, each read back after its own frame. Pixels at the board's
  edges and at the overlay panel's corners are placed by that view's size and scale, the
  board drawn again after the overlay is byte-identical, and a resize to 360×240 at 1.25
  reaches the swapchain. `VOID_VIEWS_OUTSIDE=1` checks that `fbWidth` outside a frame aborts.
  Three mutations, measured red on 2026-09-24: `dpiScale` pinned to 1, `ResizeBuffers`
  skipped, and a readback of buffer 0.
- The readback uses **buffer 1**. After `Present` on a two-buffer flip-sequential swapchain,
  buffer 0 read back as all zeros and buffer 1 held the frame just presented (measured on this
  box, D3D11, 2026-09-24).
- `examples/ionViews.ms` is the Ion host: a board of tiles and an overlay panel, two views whose
  visuals sit under one window's root. Each redraws only when a click changes it or the window
  resizes. On Ion's earlier render-surface API, driven by synthetic clicks and `SetWindowPos` from
  1000×640 to 700×820 on 2026-09-24, both views followed the resize, and the board's 3 px edge
  frame stayed on the window's edges. On the window-root API it builds (msc v0.3.4, BUILD
  `5631dd3e5`, ion `b9b5e8b`, 2026-10-16) and has not been run.

- `sh scripts/webViews.sh` builds `src/examples/webViews.ms` for WebGPU and WebGL2 and runs
  `tests/web/views.html` in headless Chrome: a view started, stopped, then started on a second
  canvas. Each view must show its clear colour in a screenshot, and each stop must leave no
  animation frame requested in 300 ms and the canvas context released (WebGL2 `isContextLost()`,
  WebGPU `getCurrentTexture()` throwing). 12 of 12 passed on 2026-10-20 (msc BUILD `177f04c27`,
  emscripten 5.0.5, Chrome 155 on macOS). Headless Chrome on macOS hands out neither WebGL2 nor a
  WebGPU adapter except on SwiftShader, so the run uses it, and SwiftShader takes seconds to hand
  out the WebGPU device. With `stop` no longer destroying the view, 5 checks went red.

Not verified:

- A view that draws more than a clear across a WebGL2 restart. The web test's views only clear,
  so the GPU-generation rebuild of void2d and void3d resources after a second WebGL2 setup is
  covered only by the Android context-loss path.

- A live DPI change. This box has one monitor at 96 DPI. The scale path is covered only by
  `twoViews` at 1.25 and 1.5.
- iOS (`bridgeIos.m`, `ios/VoidView.m`): it has not been built, because this box cannot build
  for iOS. The drawable size is now set by Void from the view's pixel size, and `dpiScale()`
  returns the view's `contentScaleFactor` where it used to return 1.0.
- Android on a device. `dpiScale()` stays at 1.0 there, because `voidJni.c` passes 1.0 and the
  Kotlin side does not send the density yet.
