# Shaders — Authoring Story (current + planned)

How shader code gets written, composed, and cross-compiled for Void. The GPU bridge already cross-compiles GLSL to every backend via **sokol-shdc**; this doc records the authoring layers on top of that — what exists now, and the planned MetaScript-native path (the "steal shady" direction).

## Where it sits

```
author shaders ──┐
                 ├─ Tier 1  hand-written GLSL  (.glsl, @vs/@fs)        ✅ DONE
                 ├─ Tier 2  über-shader + uniforms (colorAdd/matrix)   ← next
                 └─ Tier 3  MetaScript shader fns → GLSL (shady-style)  ← deferred
                              │  comptime AST → GLSL emit
                              ▼
                   sokol-shdc  (offline cross-compile)
                              │  GLSL → Metal · D3D · GL · WGSL + desc header
                              ▼
                   Void GPU bridge  (sg_make_shader / sg_make_pipeline)
                              │  src/sokol/{bridge,gpu}, src/void2d/batcher
                              ▼
                   Metal · D3D11 · GL · WebGPU · WebGL2
```

sokol picks its backend at **compile time**, and sokol-shdc cross-compiles **offline** — so every tier ultimately produces one GLSL source that sokol-shdc fans out. The tiers differ only in *how the GLSL is authored*.

## Tier 1 — hand-written GLSL (done)

Author annotated GLSL (`@vs` / `@fs` / `@cs`, separate `texture` + `sampler`), cross-compile with sokol-shdc to a generated `*.glsl.h` desc header. Used today by both the cube (`src/sokol/shader.glsl`) and void2d (`src/void2d/shader2d.glsl`).

```
deps/sokol-tools-bin/bin/osx_arm64/sokol-shdc -i X.glsl -o X.glsl.h -l metal_macos:glsl300es:wgsl -f sokol
```

void2d runs **one shader × pipeline-per-blend-mode** (`s_pips[VOID2D_BLEND_COUNT]`), flushing the batcher on a blend or view change. That same "pipeline-per-variant + flush" mechanism is the hook for per-material shaders later — a new effect is a new pipeline variant, not a new architecture.

## Tier 2 — über-shader + uniforms (next, cheap)

Heaps' `h2d.Drawable` color pipeline (`color` multiply, `colorAdd`, `colorMatrix`, `colorKey`) is the breadth gap vs our current flat tint. Closing it does **not** need a shader DSL — add the terms as **uniforms** to the void2d fragment shader and branch/multiply on them. One über-shader, a handful of uniforms, no new compile path. This is the highest-value-per-effort shader work and should land before Tier 3.

## Tier 3 — MetaScript shader functions → GLSL (the "shady" direction, deferred)

The true [HXSL](HEAPS.md)-equivalent: write shaders **in MetaScript** (typed, with `Vec2`/`Vec4`, real functions), and transpile the AST → GLSL at comptime. Modeled on **[treeform/shady](https://github.com/treeform/shady)** — a Nim library that turns Nim procs into GLSL via Nim macros (bonus: the same code runs on CPU for debugging/tests).

**Why this fits MetaScript specifically:**

- MetaScript is **already a multi-backend compiler** (C / JS / WASM). A GLSL emitter for shader-annotated functions is **another codegen target** — the heavy lifting (parse, AST, type info) already exists; the work is the GLSL emitter, modeled on the existing C/JS backends.
- This makes Tier 3 a **compiler co-evolution** project (we own the whole stack — see CLAUDE.md Co-Evolution Policy), **not** a library inside Void. Void stays thin: it only *consumes* the generated shader desc.

**Composition comes for free.** HXSL needs a macro to *merge* N shaders into one. With shaders as MetaScript functions, composition is ordinary function composition — write effects as functions, compose by **calling** them, and the transpiler inlines/flattens when it emits GLSL. Cleaner than HXSL's merge model.

**Pipeline.** MetaScript shader fns → (comptime) GLSL → sokol-shdc → all backends. Stays offline, stays cross-backend, matches sokol's model. (Runtime-generated GLSL would only run the GL backend, so the comptime path is the one to take.)

**Caveats (honest scope).** A shader is a *subset* of the language — Tier 3 transpiles only GLSL-expressible constructs (vec math, builtins, swizzles, control flow, uniforms/attributes/varyings, texture sampling). That subset restriction is exactly why shady itself is subset-only. It's a real mini-backend effort.

## Sequencing

1. **Now:** Tier 1 (have it) + Tier 2 (über-shader uniforms) → ship real shader power and close the Heaps color-depth gap without a DSL.
2. **Later:** Tier 3 (shady-for-MetaScript GLSL backend) when shader volume makes hand-writing GLSL painful, or when CPU-testable / type-shared / composable shaders are wanted. This is the genuine differentiator of a MetaScript engine — but it should not block current Void work.

## Scope discipline

Authoring tiers 1–2 live **in Void** (shaders + uniforms are part of the render layer). Tier 3's transpiler lives **in the compiler** (a GLSL backend), with Void merely consuming its output. Either way Void stays the thin narrow-waist render layer — no shader-graph editor, no material-asset pipeline (those are tooling layers above, pulled in per use case).

## Reference

- [HEAPS.md](HEAPS.md) — HXSL (Haxe-macro shader DSL with `addShader` composition); the design reference Tier 3 generalizes.
- [treeform/shady](https://github.com/treeform/shady) — Nim→GLSL transpiler via macros; the concrete blueprint for Tier 3.
- sokol-shdc — https://github.com/floooh/sokol-tools — the offline cross-compiler all tiers feed.
- [VOID2D.md](VOID2D.md) — the batcher + pipeline-per-blend-mode mechanism Tier 2's variants extend.
