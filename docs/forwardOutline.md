# Forward hidden-line transition

Plain `ForwardRenderer.create(context, background)` can transition from its usual image to
visible silhouettes and normal creases. No HDR constructor, pixel-art preset, palette, fog,
low-resolution target, triangle wireframe or temporal history required.

## API

Import setters/budgets from `src/void3d/forwardRenderer.ms` and `ForwardOutlineSettings` from
`src/void3d/forwardOutline.ms`. Budget `FORWARD_OUTLINE_UNIFORM_LENGTH` plus scene material
blocks in `DrawContext.withUniformCapacity`. HDR callers add
`FORWARD_OUTLINE_PASS_UNIFORM_LENGTH` to `FORWARD_HDR_UNIFORM_LENGTH` instead.

- `setOutlineBlend(renderer, blend)` takes a finite scalar in `[0,1]`, usable every frame.
  Unused/zero retains original Forward passes, keys and output. First positive value reserves
  three CPU screen-material holders and 20 uniform floats; first enabled prepare allocates GPU
  targets. Returning to zero bypasses them; resources remain owned until `closeForward`.
- `setOutlineSettings(renderer, settings)` copies value settings and marks core changed.
  `ForwardOutlineSettings.defaults()` gives straight black RGBA `(0,0,0,1)`, width 2,
  depth threshold 0.002, normal dot threshold 0.8.
- `color` is straight RGBA, each component finite in `[0,1]`. Final line output premultiplies
  once and multiplies all four channels by filtered coverage.
- `pixelWidth` is finite framebuffer pixels in `[1,16]`, not CSS pixels. For DPR 2,
  1–1.5 CSS pixels requests 2–3 framebuffer pixels. Base width2 silhouettes are inside nearest surface; creases span neighboring visible normals.
  Other widths apply the Heaps circle-max operator to scalar RGB coverage, with radius
  `abs(width-2)/2`; below2, affine RGB complement before/after the same operator contracts
  coverage. Quality0.48 gives48 circle samples plus own sample. Width2 bypasses this pass
  and never allocates its extra target. RGBA8 quantization and rasterization remain; this
  is not analytical subpixel geometry or temporal antialiasing.
- `depthThreshold` is finite normalized clip-depth distance in `(0,1]`, **not metres**.
  Perspective near/far settings affect sensitivity. `normalThreshold` is finite in `[-1,1]`;
  smaller dot product identifies a crease. Tune against consumer's actual camera and normals.
- Invalid settings/blend/budget/closed setters stop by name. Enabled outlines refuse blended
  opaque materials, opaque materials without Less/LessEqual depth writes, and translucent
  depth writes before frame GPU work. Opaque programs lacking declared normal MRT variants
  answer `ProgramNotDrawn`; supplied variants cover all shipped opaque Lit/LitTextured/
  UnlitTextured feature combinations, including cutout, normal/emission maps and shadows.

One-layer frame use, after configuring line settings and creating scene:

```ms
const blend: float32 = transitionValue;
setOutlineBlend(forward, blend);
const frame = renderFrame(forward, items, cameraValues, lightValues,
	fbWidth(), fbHeight());
if (!frame.ok) { unreachable; }
```

`renderFrame` owns its screen pass and commit as before. Composing callers use
`prepareFrame` then draw through `drawToScreen` inside caller's screen pass, or `endPrepared`
when consuming `colorTarget` themselves. In every case `colorTarget` holds final image.
At blend 1, flat faces vanish from colour/alpha **after** nearest opaque depth/normal capture;
covering faces still hide back geometry. At intermediate values output is straight full-RGBA
mix of normal premultiplied image and premultiplied outlined-only image. Clear `(0,0,0,0)`
for transparent canvas. `Program.Copy` preserves RGBA exactly; it adds no background or alpha.

## Mechanism and references read

Heaps `b9aa6dcbb2307b03c1f435e87bdb036060100984`:
- `h3d/scene/fwd/Renderer.hx:1–85`: full-resolution packed depth/normal producers and separate
  default/alpha/additive outputs. Void uses conditional opaque MRT with same nearest surface,
  then colour-only translucent phases, reusing existing PixelArt M32 split.
- `h3d/pass/Copy.hx:71–129`: RGBA texture getLod and default None blend.
- `h3d/pass/FXAA.hx:14–41`: unchanged RGB direction, reduction, bounded taps and range selection.
  Grayscale coverage is ordinary RGB input. Filtered red channel becomes coverage; final
  canvas alpha is **not** FXAA's unchanged `origin.a` rule. Generic FXAA policy is untouched.
- `h3d/pass/Outline.hx:1–44`, `h3d/shader/Outline2D.hx:1–32`: image dilation only, not evidence
  for hidden-line crease detection. Its circle-max/own kernel supplies width adjustment;
  `h3d/shader/ColorMatrix.hx:1-23` supplies affine RGB complement through homogeneous1.
  This is scalar RGB operator composition, not a claim of literal Heaps alpha erosion.
  `h3d/mat/Texture.hx:130-149` initializes linear filtering.

Void reuse: `pixelArt3d.glsl` post depth/normal neighbor tests (without directional normal bias,
opaque output, palette/fog/low-resolution assumptions); `pixelArtRenderer.ms` opaque-MRT then
colour-only phase split; existing ProgramKey feature specialization, targets, holders,
reflection, frame guards, setters and offline sokol-shdc registry.

Pinned Bevy `157e1ce6bc66fadca9f57260c18a16d743c11ed5` supplied original passages read:
`bevy_core_pipeline/src/prepass/mod.rs:1–20` excludes transparent meshes;
`bevy_pbr/src/prepass/prepass.wesl:171–190` packs normal RGB with alpha1;
`bevy_pbr/src/prepass/utils.wesl:1–20` loads depth and normalizes decoded normal. Valid stored RGB normals are normalized here;
identical packed normals cannot trigger a crease, including at dot threshold1. Presence-alpha
contours do not depend on the perspective depth gap to background, retaining far silhouettes. No claim full Bevy
renderer/postprocessor traced. Heaps/Void own implemented mechanisms.

Actual depth attachment is sampleable and explicitly stored. Backend mapping is stored depth
×1+0 on zero-to-one backends and ×2−1 on GL/GLES, undoing their clip-to-depth mapping.
Perspective reads actual rasterized depth, not PixelArt's orthographic-only `gl_Position.z`
packed into an 8-bit normal alpha. Normal alpha marks opaque presence only.

`NORMAL_MRT` uses ProgramKey bit15; bit14 remains reserved for parent skinning stack.
Original registry row order and default shader variants remain unchanged. New full-frame
passes use three extra bases (`OutlineMask`, `OutlineMix`, `OutlineWidth`), below existing 16-base boundary.

## Cost and acceptance boundary

Enabled path adds four full-resolution targets: lit RGBA8, normals RGBA8, depth, grayscale
mask RGBA8, plus linear sampler and two fullscreen passes. Existing baseline colour/depth
remain owned. Approximate additional attachment storage: 16 bytes × framebuffer pixels when
depth is 32-bit, excluding driver overhead. MRT adds normal bandwidth; mask performs18 nearest depth/normal reads; mix performs9
reference FXAA coverage reads plus one lit-image fetch. Widths other than2 lazily add one
RGBA8 target (4 bytes/framebuffer pixel, 10.37MB at1080x2400), fullscreen write/pass and49
linear circle/own reads. Width2 has no such target allocation or draw. Three owned material
holders consume20 uniform floats; both base passes use8, width uses4 at slot0. No extra
opaque geometry pass, temporal buffer, per-frame holder growth or performance benchmark.
Current dense ProgramKey index grows from 16384 to 65536 int32 entries (+192 KiB CPU storage).
These are resource counts, **not** a 60fps phone claim.

Fixtures: `src/test/forwardOutlineCheck.ms`, five `tests/aborts3d/outline*.ms`,
`tests/integration/forwardOutline.ms`, `tests/integration/copyAlpha.ms`, and corrected
`mrtBlend.ms` packed-depth alpha pin. Actual `scripts/web3d.sh` includes Copy and Forward
fixtures, with framebuffer-factor 1 and 2 runs. Factor2 is controlled pixel-size input,
not physical DPR/device acceptance. Motion fixture records coverage mass, partial alpha, moving edge-profile deltas and centroid;
visual crawl quality remains a separate judgment, not solved merely by using FXAA.

Current full CPU index1491/1491 and5/5 named refusal controls pass on installed9a4775dc.
All134 shader keys previously regenerated for7 backends; production header identity unchanged.
All11 integration entries build both web backends,22 builds PASS attempt1. WebGPU capture NOT RUN.
Mandatory external NOT RUN until owner supplies receipts: native Metal, actual Mac Geass asset
and screenshot (`sh ~/metascript/geass/mech3d/build.sh`), both real consumer web backends, actual
DPR2 midrange-phone 60fps and slow-camera visual acceptance. No Geass source changed here.


## Current verification checkpoint
Actual Run9 D3D11 native four jobs PASS; actual Run10 existing full WebGL2 executor20/20 PASS, exit0. Independent test-only pinned Heaps circle/own48 GPU width reference byte-matches full images at both framebuffer factors. Production-only radius+1 off-axis width16 fault produces1138/2400 mismatches; reference unchanged, original width/public final image restored byte-identically. Hardware sampler shared; the reference body is written apart from `outlineWidthFs` (a uv-space radius, its own loop). Since 2026-10-18 it reaches the GPU through the same emitter and sokol-shdc (`tests/integration/forwardOutlineReference.ms`, `shaderProgram`), so a fault in the emitter that both stages share is not caught here; the emitter's pins and the goldens cover that.

Copy browser timeout measured request160x120 versus actual framebuffer320x240, triggering existing strict capture size guard and plain exit. Test-page input delivery now selects160x120 for Copy; other pages stay320x240 and Outlinefactor2 selects640x480. Copy backend3 now measures request/frame160x120 and passes exact RGBA/clamp controls; both Outline factors pass at actual320x240/640x480. Capture guard, executor, shaders and runtime unchanged. Historical reds retained, not rebaselined.

Only12 HTML hashes changed after Run9;60 non-HTML hashes remain identical. Parent approved carrying actual Run9 native evidence into Run10 browser-only affected checks. Run10 did not rerun native jobs. Compiler/support9a4775dc and BEGIN/FREEZE/END identities match.

Technical verdict: D3D11native4PASS + GL20readback + WGPUbuildPASS,captureNOTRUN. Separate Yoga `tests/layout.test.ms` was not run in this bounded GPU phase; index success does not prove full repo gate. Metal/MacGeass/assets/reference picture/phone60fps/FPS/visual no-crawl acceptance remains NOT RUN. Parent independent audit/publication/integration remains separate.
