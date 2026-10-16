# Embedding Void in a host

A host that owns the window and the frame clock (Ion on Windows and macOS, a React-Native
`VoidView` on iOS, a `SurfaceView` on Android) drives Void through **views**. The entry points are in
`src/sokol/bridge.h` (`voidEmbedRegister`, `voidViewCreate`, `voidViewResize`,
`voidViewFrame`, `voidViewDestroy`, `voidViewSwapChain`, `voidCurrentView`), and MetaScript
reaches them through `src/sokol/gpu.ms` (`embedRegister`, `viewCreate`, …). The shared part is
`src/sokol/views.c`; each platform's half is the `voidPlatform*` set in `bridgeWin.c`,
`bridgeIos.m`, `bridgeEmbed.m` (macOS) and `bridgeAndroid.c`.

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
driver share one process, the first of the two chooses, and the other aborts. sokol_gfx is the
single implementation in `sokol.o`; `bridge.c` and `views.c` are compiled beside it.

`native` in `viewCreate` is an `NSView*` or 0. With a view, Void adds a `CAMetalLayer` as a
sublayer of the view's layer (it sets `wantsLayer`), sized to the view's bounds at every
`viewResize`, and removes it on `viewDestroy`; the host's own layer is not replaced. With 0, Void
makes the layer and attaches it nowhere: `viewSwapChain` returns the `CAMetalLayer*`, as it returns
the `IDXGISwapChain1*` on Windows, and the host adds it to its own layer tree. `w` and `h` are
pixels. `tests/integration/macViews.ms` creates both and checks sizes, resize and destroy, with no
pixel readback because the Metal capture path is a stub.

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

Not verified:

- A live DPI change. This box has one monitor at 96 DPI. The scale path is covered only by
  `twoViews` at 1.25 and 1.5.
- iOS (`bridgeIos.m`, `ios/VoidView.m`): it has not been built, because this box cannot build
  for iOS. The drawable size is now set by Void from the view's pixel size, and `dpiScale()`
  returns the view's `contentScaleFactor` where it used to return 1.0.
- Android on a device. `dpiScale()` stays at 1.0 there, because `voidJni.c` passes 1.0 and the
  Kotlin side does not send the density yet.
