# bench/web — Void against itself and other web renderers

This is not a test. Nothing here passes or fails, and no gate runs it. `tests/` and `scripts/gate.sh`
say whether Void is correct. This directory says how Void feels to an app author next to the
alternatives: bytes to download, time to the first frame, CPU per frame, frame rate, memory. It is kept
up to date so that the comparison can be repeated after any change, on either side.

The layout follows the bench convention proposed for recompiler `src/bench/<area>/` (card
`std-unix-socket`, awaiting the person): `bench/<area>/cases/` holds Void's version of each case beside
the other projects' versions, a runner prints numbers and never fails, and `baseline/` keeps each
measurement with its commit, machine and load. This area is `web`.

## What runs

Each scene is a directory under `cases/`, written once per implementation. All implementations do the same work, and each one uses
its library's usual fast path, because that is what an author of that library would write.

| implementation | what the page downloads |
|---|---|
| `void-wasm-webgpu`, `void-wasm-webgl` | emscripten builds of `cases/<scene>/void/<scene>.ms` (`scripts/build-web.sh`, `--release`) |
| `void-js-webgpu`, `void-js-webgl` | `--target=js` builds of `cases/<scene>/void/<scene>Web.jms`, shipped through `scripts/jsMinify.sh` |
| `pixi-webgpu`, `pixi-webgl` | `cases/<scene>/pixi.js` bundled by esbuild, minified |
| `three-webgpu`, `three-webgl` | `cases/<scene>/three.js`: `WebGPURenderer` from three's WebGPU build, or the classic `WebGLRenderer` |

Library versions are pinned in `package.json`. Each baseline file records them, with Chrome's
version and the msc build.

### `sprites`

- 10 000 sprites of 16×16 px on a 1280×720 canvas at device scale 1.
- Every sprite samples one 32×32 RGBA checker texture, with alpha blending on.
- Starting positions and velocities come from one LCG (`seed * 1664525 + 1013904223`, seed 1, drawn in
  the order x, y, vx, vy). Each velocity component is in [-2, 2] px per frame.
- Every frame, each sprite moves by its velocity and bounces off the canvas edges.
- The app code runs the same arithmetic on every implementation. The parameters live in
  `cases/sprites/scene.js` and `cases/sprites/void/spritesScene.ms`. Each page prints `bench.scene sprites count=… size=…`,
  and the runner refuses a page whose line differs.
- The usual fast path differs by library:
  - Void: one `Scene2D` sprite node per sprite, moved with `setPosition`.
  - Pixi: one `Sprite` per sprite in the stage, with Pixi's own batching.
  - Three: one `InstancedMesh` of textured quads, written with `setMatrixAt`. Three has no batching
    2D sprite path; `THREE.Sprite` would make 10 000 draw calls.

## What is measured, and how to read it

`driver.js` loads before any library. It wraps `requestAnimationFrame`, so one clock measures
every library without changing its loop. The runner (`run.mjs`) serves each page with COOP/COEP
headers, so `performance.now()` keeps its fine resolution; a row whose `isolated` is false had a coarse
timer.

- **gzip KB**: every file the page downloads (JS, wasm), each gzipped with `-9`, then summed. The scene
  has no assets.
- **first frame ms**: from navigation start to the end of the first animation-frame callback. It
  includes download from localhost, compile, and setup.
- **CPU/frame ms**: time spent inside the animation-frame callbacks of one frame, median and p95 over 600
  frames after 120 warm-up frames. This is main-thread JS and wasm work only. The GPU, and the browser's
  own compositing work, are not in it.
- **frame interval ms**: time between frames, with Chrome's frame limit and vsync turned off
  (`--disable-frame-rate-limit --disable-gpu-vsync`). It is the throughput the whole pipeline sustains,
  GPU included: 1000 / interval is the frame rate.
- **JS heap MB**: `performance.memory.usedJSHeapSize` at the end of the run. A wasm build's linear memory
  is not in it.
- **load**: the host's 1-minute load average, the higher of the samples taken before and after each run.
  A row measured beside other jobs reads slower; compare it with its load.

Compare numbers only within one baseline file, or across files from the same host. Headless Chrome on
another machine has another GPU and another clock.

## Running

Bench runs open Chrome on the GPU, so they run on a Mac through the workspace's remote runner, never on
the Mac the person works on:

```sh
~/metascript/.gate-host/run-remote.sh --mac --host m1m --cores 8 --job '<who>: bench sprites' -- \
	bash -c 'cd bench/web && npm ci && cd ../.. && BENCH_HOST=m1m node bench/web/run.mjs --scene sprites --runs 3'
```

- `--only void-js-webgpu,pixi-webgl` picks implementations.
- `--no-build` reuses `out/bench/`.
- `BENCH_VOID_COMMIT` and `BENCH_MSC` name the tree and the msc build in the result, because a remote
  copy has no `.git`.

The runner prints a table, writes `baseline/<scene>-<host>-<date>.json` and keeps a screenshot of
each page's last frame in `out/bench/shots/`, so a number can be checked against what was drawn. Set
`BENCH_HOST` to the machine's workspace name (`m1m`). Commit the baseline file:
it is the history this directory keeps. An implementation that stops records why it stopped instead of
numbers.
