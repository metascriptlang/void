# Shaders — authoring tiers

How shader code gets written for Void. Every tier ends in one GLSL source that **sokol-shdc** cross-compiles offline to every backend; the tiers differ only in *how that GLSL is authored*. Tier 3's design lives in [src/shader/CLAUDE.md](../src/shader/CLAUDE.md); this doc records where each tier stands and why Tier 3 took the shape it has.

## Where it sits

```
author shaders ──┐
                 ├─ Tier 1  hand-written GLSL  (.glsl, @vs/@fs)               stages not ported yet
                 ├─ Tier 2  über-shader terms (colorMatrix/colorAdd/colorKey) ✅ void2d
                 └─ Tier 3  MetaScript shader fns → GLSL (shady-style)        ✅ void3d lit, textured, post; void2d
                              │  glsl(fn) macro → GLSL 450 on disk (tools/genShaders.ms)
                              ▼
                   sokol-shdc  (offline cross-compile, scripts/regen-shaders.sh)
                              │  GLSL → Metal · D3D · GL · WGSL + desc header
                              ▼
                   Void GPU bridge  (sg_make_shader / sg_make_pipeline)
                              │  src/sokol/{bridge,gpu}, src/void2d/batcher, src/void3d
                              ▼
                   Metal · D3D11 · GL · WebGPU · WebGL2
```

sokol picks its backend at **compile time**, and sokol-shdc cross-compiles **offline**, so GLSL generated at runtime would reach only the GL backend. That is why every tier, Tier 3 included, writes its GLSL to disk before shdc runs.

## Tier 1 — hand-written GLSL

Annotated GLSL (`@vs` / `@fs` / `@cs`, separate `texture` + `sampler`), cross-compiled by `scripts/regen-shaders.sh` to a generated `*.glsl.h` desc header. Tier 3 has taken every stage: what stays hand-written is the frame around the generated programs, `src/void2d/shader2d.glsl`'s `@program` lines and includes.

void2d runs **one shader × pipeline-per-blend-mode** (`VOID2D_BLEND_COUNT` in `src/void2d/batcher.c`), flushing the batcher on a blend or view change. A new effect is a new pipeline variant, not a new architecture.

## Tier 2 — über-shader terms (done in void2d)

Heaps' `h2d.Drawable` colour pipeline (`color` multiply, `colorAdd`, `colorMatrix`, `colorKey`) is a set of terms in the void2d fragment shader (`src/void2d/shader2d.glsl`), with the matrix factories in `src/void2d/effect.ms`. It needed no shader DSL and no new compile path.

## Tier 3 — MetaScript shader functions → GLSL (shady-style, in use)

A shader is an ordinary MetaScript function. The macro `glsl(fn)` (`src/shader/emit.ms`) reads its typed body and emits GLSL 450 for sokol-shdc, and the same function runs on the CPU as a tolerance oracle in the native gate. Modeled on **[treeform/shady](https://github.com/treeform/shady)**, which does the same for Nim procs with Nim macros; the vocabulary is TypeGPU's ([VOCABULARY.md](VOCABULARY.md)). Every void3d stage is written this way: the core's programs (`src/void3d/shader3d.ms`) and its tone map, bloom and outline passes (`src/void3d/post3d.ms`), generated into `src/void3d/shader3dGen.glsl`, and the pixel-art preset's (`src/void3d/pixelArt3d.ms`) into `src/void3d/pixelArt3dGen.glsl`; void2d's four programs (`src/void2d/shader2d.ms`) into `src/void2d/shader2dGen.glsl`, which `shader2d.glsl` includes. Their hand-written GLSL is deleted.

**A macro library in Void, not a compiler backend.** This doc first planned Tier 3 as a GLSL codegen target inside msc. That proved unnecessary: inside a macro, `getImpl(bindSym(...))` returns the function with checker types on every expression (first measured on msc `244ef48c`), so the emitter is a library and the compiler supplies only the macro surface listed in src/shader/CLAUDE.md, "Compiler surface the emitter relies on". Shady's own per-backend HLSL/MSL/GLSL writers were rejected for the same reason Tier 1 uses shdc; both rejections are recorded there under "Rejected".

**Composition is function calls.** HXSL needs a macro to merge N shaders into one. Here an entry calls helpers, and the emitter defines each helper it reaches once, above `main()`. Feature variants come from one function too: a `@feature` program key emits `#ifdef` blocks, so one entry serves every row of `src/void3d/programKeys.txt`.

**Write → run for an app's own program.** `shaderProgram(wave, waveVs, waveFs);` (`src/shader/program.ms`) runs the emitter, sokol-shdc and the door's registration while msc compiles the app, and declares `wave`, the program id a pipeline names; no regen step and no generated file to commit. It builds one program, so a `@feature` family stays on the generator; src/shader/CLAUDE.md "Design" has its limits.

**Subset, refused loudly.** A shader is the GLSL-expressible subset of MetaScript, and the emitter checks shdc's dialect at the author's code; src/shader/CLAUDE.md "Design" lists the rules.

**Coverage against shady.** Every case of shady's tests and shader-toy/compute examples has a Void stage, run on the CPU and pinned as GLSL; the case-by-case table, with what Void writes differently, is src/shader/CLAUDE.md "Measured — coverage against shady".

## Scope discipline

All three tiers live **in Void**: shaders, uniforms and the emitter are part of the render layer, and the compiler contributes only the macro facilities. Void stays the thin narrow-waist render layer: no shader-graph editor, no material-asset pipeline (tooling layers above, pulled in per use case).

## Reference

- [src/shader/CLAUDE.md](../src/shader/CLAUDE.md) — Tier 3's design, measurements and rejected paths.
- [VOCABULARY.md](VOCABULARY.md) — the TypeGPU vocabulary Tier 3 uses.
- [HEAPS.md](HEAPS.md) — HXSL (Haxe-macro shader DSL with `addShader` composition).
- [treeform/shady](https://github.com/treeform/shady) — Nim→GLSL via macros; Tier 3's blueprint.
- sokol-shdc — https://github.com/floooh/sokol-tools — the offline cross-compiler all tiers feed.
- [VOID2D.md](VOID2D.md) — the batcher and pipeline-per-blend-mode mechanism.
