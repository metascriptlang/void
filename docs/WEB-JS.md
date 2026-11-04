# Void on the browser's JS target — size and speed against wasm

The same demo runs in a browser two ways: the emscripten build (`--os=emcc`, `web/wgpu/`, `web/gl/`)
and the `--target=js` build (`web/js-wgpu/`, `web/js-gl/`, `web/void2d.html?js`), both from
`scripts/build-web.sh`. This file holds what was measured between them; the code paths are in
`src/examples/main2d.ms` and `src/examples/main2dWeb.jms`.

## Bytes, main2d (2026-11-03)

Tree `b745b9a755ed612862d7fb57c32acd50f268b956`, msc BUILD `a0f6f1be1e3`, emscripten 5.0.5, macOS.

Commands: `VOID_WEB_DEST=out/sizeShip sh scripts/build-web.sh` (all four backends); for the wasm
split a second build with `VOID_WEB_PRELOAD="--preload-file assets/test.png --preload-file
assets/font.ttf --profiling-funcs"`, then
`llvm-nm --print-size main2d.wasm > nm.txt; node scripts/jsBudgetMeasure.mjs wasm-split nm.txt`.
JS: `node scripts/jsBudgetMeasure.mjs size` on the shipped file and `split` on the msc bundle
(`out/release/main2dWeb-js-<backend>.js`). gzip is `-9`.

What a page downloads, code only (the assets, 434 183 B raw / 223 487 B gzip, are the same files
both ways: emscripten packs them into `main2d.data`, the JS page fetches them):

| backend | wasm + glue, raw | wasm + glue, gzip | JS shipped, raw | JS shipped, gzip |
|---|---|---|---|---|
| WebGPU | 1 241 524 + 139 586 | 451 526 + 33 965 = 485 491 | 920 281 | 210 551 |
| WebGL2 | 1 237 624 + 137 102 | 450 877 + 34 227 = 485 104 | 964 522 | 221 274 |

The JS page is 43 % (WebGPU) and 46 % (WebGL2) of the wasm page's gzip bytes. The wasm build is
the one `build-web.sh` ships, without `--release`, the same profile `tests/bench/wasmBudget.txt`
records.

Split by source directory, WebGPU. JS columns are gzip bytes each module adds to the msc bundle
(before `scripts/jsMinify.sh`, which shrinks the whole by 2.15x gzip); wasm columns are raw code
bytes per function's module, because a wasm file gzips as one stream. The JS column sums to the
bundle's 452 461 B gzip:

| share | JS gzip | wasm raw |
|---|---|---|
| `src/void2d` (2D batcher, text stack: font, glyph, shaper, layout) | 235 528 | 545 104 |
| GPU layer: `src/webgpu` + `src/gpu` + `src/host` + `src/platform` | 129 157 | 152 658 |
| `std` | 41 139 | 8 889 |
| `src/assets` (png, jpeg decode) | 31 926 | 77 574 |
| rest: `src/math`, `src/examples`, `../yoga`, `src/shader`, `src/module` | 14 633 | 87 520 |
| C, libc and emscripten runtime (wasm links yoga's C++, JS its MetaScript port) | 78 | 206 576 |
| data segments | — | 151 329 |

What the split says:

- **std costs JS 41 KB gzip and wasm 9 KB raw.** The JS bundle carries 44 std modules whatever the
  program reaches: compiler card `2026-10-27-js-bundle-carries-all-std` (design).
- **The C runtime is wasm's own cost**: 207 KB of libc, emscripten and Void's C (`window.c`, the
  bridges) that the JS page replaces with the browser's own API.
- **`src/examples` is 82 KB in wasm** because `init2d` and `frame2d` inline most of the demo; in JS
  the same code stays in its own modules.

## JS-only build and bytes (2026-11-04)

Production source at `79c78587`, tree `e2d2d8074a1c03752dd9566c53275c09347077fd`,
msc v0.4.0 BUILD `f357ebc1c7a`, m1m, esbuild 0.28.2, gzip level 9. The real bundles were built
before the last test-only edit; the production script's SHA256 matched the committed script.
No wasm bundle was rebuilt, so the older table above is not a current paired comparison.

One remote call ran the setup contract, then:

```sh
EMSDK_DIR=/void-js-sdk-must-not-be-needed VOID_WEB_BACKENDS='js-wgpu js-gl' \
VOID_WEB_JS_ASSETS='' VOID_WEB_DEST=out/js-endgame-ship \
VOID_WEB_LOGDIR=out/js-endgame-logs sh scripts/build-web.sh
node scripts/jsBudgetMeasure.mjs size out/js-endgame-ship/js-wgpu/main2dWeb.js
node scripts/jsBudgetMeasure.mjs size out/js-endgame-ship/js-gl/main2dWeb.js
```

Both real builds and `node --check` of both shipped scripts passed without an SDK. The final
`sh scripts/buildWeb.test.sh` returned `PASS build-web setup: 4 cases (JS-only without SDK,
GL-only, mixed backends, wrong wasm pin); stub builds, Unix setup branch`. The Windows setup
branch was preserved, not executed by that check. SDK independence is a build result, not a
render or speed result.

| backend | shipped raw | shipped gzip |
|---|---:|---:|
| JS-WebGPU | 1 035 168 | 241 883 |
| JS-WebGL2 | 1 079 819 | 252 234 |

Attribution from `node scripts/jsBudgetMeasure.mjs split out/release/main2dWeb-js-<backend>.js`,
before minification; these gzip-prefix deltas sum to the raw compiler bundle's gzip, **not** the
shipped gzip above. They do not establish which bytes survive minification.

| share | WebGPU gzip | WebGL2 gzip |
|---|---:|---:|
| text/2D (`src/void2d`) | 287 265 | 286 219 |
| GPU/host (`src/webgpu`, `src/gpu`, `src/host`, `src/platform`) | 129 716 | 157 571 |
| std | 45 886 | 45 920 |
| assets | 31 905 | 31 914 |
| rest | 101 675 | 101 686 |

Of “rest”, shader helpers account for 87 051 / 87 055 B before minification. That is an
attribution lead, not proof that all those bytes reach the shipped page. The compiler's
std/DCE and class-display-name inbox cards track the existing size questions; design cards
are not permission to invent a new representation or strip runtime behavior.

### Current byte-cause probe

On the same host/compiler, this small input at `out/tmp/js-dce-reprobe/main.ms` separates
compiler output from the artifact the browser receives:

```ms
class Unused {
	value: int32 = 0;
}
class Used {
	value: int32 = 1;
}
const u = new Used();
console.log(u.value);
```

Build with `msc build --target=js out/tmp/js-dce-reprobe/main.ms --output=default.js`, then
repeat with `--release` and `--danger` into separate files; measure through
`node scripts/jsBudgetMeasure.mjs size <file>`.

| compiler profile | raw bytes | gzip bytes |
|---|---:|---:|
| default | 269 738 | 37 987 |
| release | 269 738 | 37 987 |
| danger | 259 642 | 37 668 |

Default and release are byte-identical; danger is not. The old report that all three profiles
emit the same checks/bytes is no longer true on this probe. No shipping profile was changed.

`sh scripts/jsMinify.sh default.js default.min.js` reduces the default to **5 052 B raw /
1 519 B gzip**; Node prints `1`. Yet the minified script still contains the literal `Unused`,
and the raw class has `static [globalThis.Symbol.for("metascript.typeDisplayName")] = "Unused"`.
This reproduces the existing class-display-name DCE issue, not a measured saving for main2d.
No metadata-stripping workaround or nonshipping removal control was used. The pre-bundle
44-module size does not mean all those bytes reach the browser.

## Remaining proof

Compiler fixes for the three reproduced issues below are delivered in installed BUILD
`56ad1fdf80f`. The new GL consumer check did **not** run: its provenance wrapper returned
`REFUSED expected binary/support 56ad1fdf80f, got binary= support=` (rc 86) before build,
despite printing the matching BUILD lines. No consumer success on the new compiler is
claimed; the earlier measurements retain their named `f357ebc1c7a` scope.

- **JS initialization:** on `f357ebc1c7a`, the exported-global/ref three-module repro and the real
  WebGL2 frame stub still fail with unboxed `Pool.slots` reads. The stub reports the error in
  `Pool_alive → Pool_slotIndex → Pool_record → adoptSwapchainTexture`; no draw submits.
  Compiler-worker delivered the corresponding fix `9f367ef718f` in `56ad1fdf80f`; the real
  Void consumer still needs its new-toolchain rerun.
- **3D/golden compilation:** the small macro `readFileBytes` repro now builds on JS and prints
  `yes`. Campfire instead stops with `MacroInvocation` unsupported at comptime. A scalar-Node
  macro calling `execFileResult("git", ["--version"])` checks on C and fails identically on JS;
  this followed the macro-on-JS / execFileResult issue, not the old two-Error-class diagnosis.
  Its fix `dfc68046ca3` is delivered in `56ad1fdf80f`; macros reading platform/exec/env/cwd remain
  a separate open issue, not yet observed in a new Campfire run. No workaround was applied.
- **Browser pixels and CPU per flow** (walk, layout, shaping, upload) against wasm on the editor
  scene remain unmeasured. The current actual-browser smoke attempt did not start: Aside was
  not running and this session had no linked Rexa terminal. No screenshot/render result is
  claimed. The landed sprite timings in VOID2D.md are wasm-WebGL2, not pure-JS measurements.
