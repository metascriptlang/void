# Void

A thin cross-platform GPU layer, written in [MetaScript](https://github.com/metascriptlang) on top of [Sokol](https://github.com/floooh/sokol).

Write rendering code once, run it on desktop, mobile and the browser — including browsers without WebGPU.

> **Status: early, internal.** Void is built alongside its own use cases, and the API still moves without notice. Some of it — the Android backend, `void3d` — hasn't landed in this repo yet. Read it, don't depend on it.

## What it is, and isn't

Void is the narrow waist between your code and the GPU: buffers, pipelines, passes, a window and a frame loop. It is **not** a game engine — no scene graph, ECS, physics, asset pipeline or editor. Those belong in layers above, pulled in per use case.

`void2d` is one such layer, shipped here: a quad batcher with a `Node2D` tree and text, drawing identical pixels on every backend. `void3d` (camera, mesh, material) is early.

## Targets

| Platform | Backend |
| --- | --- |
| macOS, iOS | Metal |
| Windows | D3D11 |
| Linux | GL |
| Android | GLES3 |
| Browser | WebGPU, plus a WebGL2 build for older browsers |

sokol picks its backend at compile time, so the web ships two wasm artifacts and a loader that feature-detects `navigator.gpu`. The floor is GLES3 / WebGL2 — roughly 97-98% of browsers.

## Layout

```
src/sokol/      GPU bridge — sokol_gfx + sokol_app primitives
src/void2d/     2D layer — batcher, Node2D tree, text
src/void3d/     3D layer — camera, mesh, material
src/examples/   thin entries: voidRun(w, h, init, frame)
```

## Build

Needs `msc`, the MetaScript compiler.

```sh
msc build src/examples/mainSokol2d.ms   # native
scripts/build-web.sh                    # both web backends → web/wgpu/, web/gl/
```

## Docs

[void2d](docs/VOID2D.md) · [void3d](docs/VOID3D.md) · [shaders](docs/SHADER.md) · [C interop](docs/CINTEROP.md)

## License

MIT
