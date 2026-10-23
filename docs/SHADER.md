# Shaders — authoring tiers

How shader code gets written for Void. Every tier ends in the shader IR (`src/shader/ir.ms`), which Void's own printers write out per backend ([SHADER-IR.md](SHADER-IR.md)); the tiers differ only in *how a stage is authored*. Tier 3's design lives in [src/shader/CLAUDE.md](../src/shader/CLAUDE.md); this doc records where each tier stands and why Tier 3 took the shape it has.

## Where it sits

```
author shaders ──┐
                 ├─ Tier 1  hand-written GLSL  (.glsl, @vs/@fs)               stages not ported yet
                 ├─ Tier 2  über-shader terms (colorMatrix/colorAdd/colorKey) ✅ void2d
                 └─ Tier 3  MetaScript shader fns → GLSL (shady-style)        ✅ void3d lit, textured, post; void2d
                              │  glslIr(fn) macro → shader IR (src/shader/ir.ms)
                              ▼
                   IR printers  (offline, tools/irPrograms.ms via scripts/regen-shaders.sh)
                              │  IR → MSL · HLSL · GLSL 430 / ES 300 · WGSL + reflection
                              ▼
                   Void GPU layer  (GPUShaderModuleDescriptor, src/webgpu/types.ms)
                              │  src/gpu/doorGpu.ms, src/webgpu/<backend>, src/void2d, src/void3d
                              ▼
                   Metal · D3D11 · GL · WebGPU · WebGL2
```

The backend is picked at **compile time** and the printers run **offline** (or in the `shaderProgram` macro while msc compiles the app), so every tier, Tier 3 included, reaches the binary as generated per-target source.

## Tier 1 — hand-written GLSL

Annotated GLSL (`@vs` / `@fs` / `@cs`, separate `texture` + `sampler`) that sokol-shdc cross-compiled. Tier 3 has taken every stage, the hand-written `.glsl` files are gone, and no build path runs shdc; which programs exist is `src/void3d/programKeys.txt` and `tools/irPrograms.ms`'s program lists.

void2d runs **one shader × pipeline-per-blend-mode** (`VOID2D_BLEND_COUNT` in `src/void2d/batcher.c`), flushing the batcher on a blend or view change. A new effect is a new pipeline variant, not a new architecture.

## Tier 2 — über-shader terms (done in void2d)

Heaps' `h2d.Drawable` colour pipeline (`color` multiply, `colorAdd`, `colorMatrix`, `colorKey`) is a set of terms in the void2d fragment shader (`src/void2d/shader2d.ms`), with the matrix factories in `src/void2d/effect.ms`. It needed no shader DSL and no new compile path.

## Tier 3 — MetaScript shader functions → GLSL (shady-style, in use)

A shader is an ordinary MetaScript function. The macro `glslIr(fn)` (`src/shader/emit.ms`, with `glslLinkedIr` and `glslComputeIr`) reads its typed body and lowers it to the IR, and the same function runs on the CPU as a tolerance oracle in the native gate. Modeled on **[treeform/shady](https://github.com/treeform/shady)**, which does the same for Nim procs with Nim macros; the vocabulary is TypeGPU's ([VOCABULARY.md](VOCABULARY.md)). Every stage is written this way: void3d's core programs (`src/void3d/shader3d.ms`), its tone map, bloom and outline passes (`src/void3d/post3d.ms`) and the pixel-art preset (`src/void3d/pixelArt3d.ms`), and void2d's programs (`src/void2d/shader2d.ms`). `scripts/regen-shaders.sh` runs `tools/irPrograms.ms`, which writes the generated modules (`src/void3d/programModules.ms`, `src/void2d/shader2dModules.ms`); `--check` fails when one is stale.

**A macro library in Void, not a compiler backend.** This doc first planned Tier 3 as a GLSL codegen target inside msc. That proved unnecessary: inside a macro, `getImpl(bindSym(...))` returns the function with checker types on every expression (first measured on msc `244ef48c`), so the emitter is a library and the compiler supplies only the macro surface listed in src/shader/CLAUDE.md, "Compiler surface the emitter relies on". Shady prints GLSL only; the per-backend printers follow Mach sysgpu's split instead ([SHADER-IR.md](SHADER-IR.md) "One IR, five printers").

**Composition is function calls.** HXSL needs a macro to merge N shaders into one. Here an entry calls helpers, and the emitter defines each helper it reaches once, above `main()`. Feature variants come from one function too: a `@feature` program key emits `#ifdef` blocks, so one entry serves every row of `src/void3d/programKeys.txt`.

**Write → run for an app's own program.** `shaderProgram(wave, waveVs, waveFs);` (`src/shader/program.ms`) runs the lowering, the printers and the door's registration while msc compiles the app, and declares `wave`, the program id a pipeline names; no regen step and no generated file to commit. It builds one program, so a `@feature` family stays on the generator; src/shader/CLAUDE.md "Design" has its limits.

**Subset, refused loudly.** A shader is the GLSL-expressible subset of MetaScript, and the lowering refuses what a target cannot express at the author's code; src/shader/CLAUDE.md "Design" lists the rules.

**Coverage against shady.** Every case of shady's tests and shader-toy/compute examples has a Void stage, run on the CPU and pinned as GLSL; the case-by-case table, with what Void writes differently, is src/shader/CLAUDE.md "Measured — coverage against shady".

## Scope discipline

All three tiers live **in Void**: shaders, uniforms and the emitter are part of the render layer, and the compiler contributes only the macro facilities. Void stays the thin narrow-waist render layer: no shader-graph editor, no material-asset pipeline (tooling layers above, pulled in per use case).

## Reference

- [src/shader/CLAUDE.md](../src/shader/CLAUDE.md) — Tier 3's design, measurements and rejected paths.
- [SHADER-IR.md](SHADER-IR.md) — what the shader IR fixes before its five printers, the reflection markers, validators and the shdc oracle.
- [VOCABULARY.md](VOCABULARY.md) — the TypeGPU vocabulary Tier 3 uses.
- [HEAPS.md](HEAPS.md) — HXSL (Haxe-macro shader DSL with `addShader` composition).
- [treeform/shady](https://github.com/treeform/shady) — Nim→GLSL via macros; Tier 3's blueprint.
- sokol-shdc — https://github.com/floooh/sokol-tools — the cross-compiler Tier 1 fed, now only the reflection oracle ([SHADER-IR.md](SHADER-IR.md) "The oracle and when it goes").
- [VOID2D.md](VOID2D.md) — the batcher and pipeline-per-blend-mode mechanism.
