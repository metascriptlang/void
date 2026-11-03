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

## Not measured yet

- **CPU per frame per flow** (walk, layout, shaping, upload) against wasm on the editor scene: the JS
  page stops at init on compiler card
  `2026-10-27-js-exported-let-struct-boxed-for-ref-read-unboxed-by-importer`, so no frame runs.
- **Re-measure the bytes** after compiler-batch-1028 syncs (the card above, a class display name a
  bundler can drop, operator mangling) and the const-array fix: each moves the JS bundle.
