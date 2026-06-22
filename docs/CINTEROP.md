# C Interop Design — Self-Hosted Compiler

How the self-hosted MetaScript compiler should handle C FFI, informed by real-world usage in the Void engine (WebGPU/Dawn rendering library).

## Problem Statement

The current Zig-based compiler has 3 disconnected C interop mechanisms:
1. `@cImport("header.h")` — emits `#include`, no parsing
2. `@include("./file.h")` — emits `#include` + auto-compiles companion `.c`, no parsing
3. `import { X } from "./file.h"` — parses C via libclang, but enum codegen is broken

The type system has no bridge between TypeScript string literal unions and C integer enums. WebGPU spec uses `"back"`, Dawn C API uses `WGPUCullMode_Back = 3` — the compiler can't connect them.

Result: users write 600+ lines of manual C bridge code (opaque `void*` handles, integer constants, flattened params) instead of using the C API directly.

## Goal

Same MetaScript source compiles to:
- **C backend**: Dawn C API calls with proper struct/enum marshalling
- **JS backend**: browser WebGPU API calls (strings, objects, arrays as-is)

Zero manual bridge code. The compiler handles all FFI marshalling.

---

## Design Changes by Compiler Phase

### Phase 1 — Parser

#### 1.1 Store optional flag on interface fields

Current bug: `?` is consumed but discarded in `parser/statements/declaration.ms`.

```typescript
// This:
interface Descriptor {
    vertex: VertexState;
    depthStencil?: DepthStencilState;  // ? is parsed but NOT stored
}
```

Fix: Add `interfaceFieldOptional: boolean[]` to `InterfaceDeclData` in `ast/node.ms`. Set `true` when `?` is consumed after field name.

#### 1.2 `extern interface` declaration

New AST node kind: `ExternInterfaceDecl`. Syntax:

```typescript
extern interface WGPUBufferDescriptor {
    size: uint64;
    usage: uint32;
    mappedAtCreation: boolean;
}
```

Properties:
- C-layout (fields in declaration order, no vtable, no RC)
- Stack-allocatable (not heap-allocated like classes)
- Passable by pointer to C functions
- Optional fields zero-initialized when absent

Can also be auto-generated from C header parsing (see Phase 2).

#### 1.3 String literal types in type annotations

The type annotation parser (`parser/typeAnnotation.ms`) should recognize quoted strings as literal types:

```typescript
type GPUCullMode = "none" | "front" | "back";
//                  ^^^^    ^^^^^    ^^^^  — these are StringLiteral types, not identifiers
```

Currently these would be parsed as identifiers and become `TypeReference("none")`. They should become `StringLiteral("none")`.

---

### Phase 2 — Type Checker

#### 2.1 Add `TypeKind.StringLiteral`

In `checker/types.ms`, add:

```typescript
// New TypeKind value
StringLiteral  // represents a specific string value as a type, e.g., "back"
```

The `typeName` field stores the literal value (e.g., `"back"`).

#### 2.2 Resolve string literal unions properly

In `checker/resolvePass.ms`, `resolveAnnotation` currently splits on `|` and looks up each part as an identifier. When a part is a quoted string, it should create `TypeKind.StringLiteral`:

```
"none" | "front" | "back"
→ Union([StringLiteral("none"), StringLiteral("front"), StringLiteral("back")])
```

#### 2.3 `extern interface` type registration

During collect pass:
- Register `extern interface` as `SymbolKind.ExternInterface`
- During resolve pass: create `TypeKind.Object` with `typeFlags` bit for `isExternInterface`
- Track field optionality (from parser's `interfaceFieldOptional`)

#### 2.4 C header import module loading

When `import { X } from "./file.h"` is encountered in the module loader:

1. Parse C header (via libclang extern call or built-in C header parser)
2. For C enums: expose each member as an importable `const uint32` with its original C name and integer value
3. For C enum types: create a `TypeKind.CEnum` that tracks the valid integer values
4. For C structs: create extern interface types with C-layout fields
5. For C functions: create extern function declarations with full parameter types
6. For C `#define` constants: create const variable declarations

C enum members are global constants in C (not namespaced). The compiler preserves this:
```typescript
// C header has: WGPUCullMode_None = 1, WGPUCullMode_Back = 3
// Compiler exposes them as importable constants with their EXACT C names:
import { WGPUCullMode_Back, WGPUCullMode_Front, WGPUCullMode_None } from "webgpu.h"

desc.primitive.cullMode = WGPUCullMode_Back;
// C codegen emits: desc.primitive.cullMode = WGPUCullMode_Back;  (verbatim)
```

No naming convention assumptions. No prefix stripping. No string mapping. The compiler is a transparent pass-through for C enum constants.

If users want prettier names (e.g., `CullMode.Back` instead of `WGPUCullMode_Back`), that's a **library-level concern** — the library wraps C constants in a MetaScript enum with user-friendly names. Not the compiler's job.

---

### Phase 3 — Transform

#### 3.1 No major changes needed

Most C interop lowering happens in codegen (Phase 5), not transforms. However:

- The existing `transform/c/optionalCoercion.ms` should be extended to handle extern interface optional fields
- The existing `transform/c/pointerParam.ms` should recognize extern interface pointer parameters

---

### Phase 5 — Codegen (C Backend)

This is where all the marshalling logic lives.

#### 5.1 C enum constants — verbatim emission

When a C enum constant (imported from a `.h` file) is used in MetaScript, the C codegen emits the original C name verbatim:

```typescript
// MetaScript source:
import { WGPUCullMode_Back } from "webgpu.h"
desc.primitive.cullMode = WGPUCullMode_Back;

// C codegen emits:
desc.primitive.cullMode = WGPUCullMode_Back;  // original C name, no transformation
```

The `#include` for the header is emitted automatically since the symbol was imported from it. On the JS backend, the integer value is emitted (e.g., `3`).

#### 5.2 Extern interface → C struct emission

```typescript
// MetaScript source:
const buf = wgpuDeviceCreateBuffer(device, {
    size: 64,
    usage: 0x48,  // UNIFORM | COPY_DST
    mappedAtCreation: false,
});

// C codegen emits:
WGPUBufferDescriptor _desc_1 = {0};
_desc_1.size = 64;
_desc_1.usage = 0x48;
_desc_1.mappedAtCreation = false;
WGPUBuffer buf = wgpuDeviceCreateBuffer(device, &_desc_1);
```

Rules:
- Object literal matching an extern interface → stack-allocated C struct
- Fields set from object literal properties
- Unset fields remain zero-initialized (`{0}`)
- Passed by `const T*` pointer to C functions
- Temporary lives until end of enclosing statement/block

#### 5.3 Optional fields → NULL pointer or omission

For extern interface fields marked optional:

```typescript
extern interface WGPURenderPipelineDescriptor {
    vertex: WGPUVertexState;          // required → embedded by value
    depthStencil?: WGPUDepthStencilState;  // optional → pointer, NULL if absent
}
```

When the optional field IS set:
```c
WGPUDepthStencilState _depth_1 = {0};
_depth_1.format = WGPUTextureFormat_Depth24Plus;
_depth_1.depthWriteEnabled = true;
_depth_1.depthCompare = WGPUCompareFunction_Less;
desc.depthStencil = &_depth_1;
```

When the optional field is NOT set:
```c
desc.depthStencil = NULL;  // {0} already sets this
```

#### 5.4 Array → pointer + count at FFI boundary

When `Array<T>` is passed to an extern function expecting `Ptr<T>` + count:

```typescript
// MetaScript source:
wgpuQueueSubmit(queue, commands.length, commands);

// C codegen emits (if commands is Array<WGPUCommandBuffer>):
wgpuQueueSubmit(queue, _arr.len, _arr.p->data);
```

For array literals at call sites:
```typescript
// MetaScript source:
queue.submit([cmd1, cmd2]);

// C codegen emits:
WGPUCommandBuffer _tmp_1[] = { cmd1, cmd2 };
wgpuQueueSubmit(queue, 2, _tmp_1);
```

#### 5.5 Nested descriptor lowering

WebGPU descriptors are deeply nested. The codegen must recursively flatten:

```typescript
// MetaScript source:
import {
    WGPUVertexFormat_Float32x3, WGPUCullMode_Back,
    WGPUTextureFormat_Depth24Plus, WGPUCompareFunction_Less,
    wgpuDeviceCreateRenderPipeline
} from "webgpu.h"

device.createRenderPipeline({
    vertex: {
        module: shader,
        buffers: [{
            arrayStride: 24,
            attributes: [
                { format: WGPUVertexFormat_Float32x3, offset: 0, shaderLocation: 0 },
                { format: WGPUVertexFormat_Float32x3, offset: 12, shaderLocation: 1 },
            ]
        }]
    },
    primitive: { cullMode: WGPUCullMode_Back },
    depthStencil: { format: WGPUTextureFormat_Depth24Plus, depthWriteEnabled: true, depthCompare: WGPUCompareFunction_Less },
});

// C codegen emits:
WGPUVertexAttribute _attrs_1[] = {
    { .format = WGPUVertexFormat_Float32x3, .offset = 0, .shaderLocation = 0 },
    { .format = WGPUVertexFormat_Float32x3, .offset = 12, .shaderLocation = 1 },
};
WGPUVertexBufferLayout _vbl_1 = {0};
_vbl_1.arrayStride = 24;
_vbl_1.attributeCount = 2;
_vbl_1.attributes = _attrs_1;
WGPUVertexState _vert_1 = {0};
_vert_1.module = shader;
_vert_1.bufferCount = 1;
_vert_1.buffers = &_vbl_1;
WGPUPrimitiveState _prim_1 = {0};
_prim_1.cullMode = WGPUCullMode_Back;
WGPUDepthStencilState _depth_1 = {0};
_depth_1.format = WGPUTextureFormat_Depth24Plus;
_depth_1.depthWriteEnabled = true;
_depth_1.depthCompare = WGPUCompareFunction_Less;
WGPURenderPipelineDescriptor _desc_1 = {0};
_desc_1.vertex = _vert_1;
_desc_1.primitive = _prim_1;
_desc_1.depthStencil = &_depth_1;
WGPURenderPipeline pipeline = wgpuDeviceCreateRenderPipeline(device, &_desc_1);
```

The codegen walks the object literal bottom-up, emitting temporaries for each nested struct, then assembles the outer struct with references to the temporaries.

#### 5.6 Unified `#include` + companion `.c` compilation

When `import { X } from "./foo.h"` is used:
- Emit `#include "foo.h"` (replaces `@cImport`)
- Auto-compile `foo.c` if it exists alongside `foo.h` (replaces `@include`)
- Add `-I<dir>` for the header directory

This unifies the three current mechanisms into one.

---

## What This Eliminates (Void Engine Perspective)

With these compiler changes, the Void engine no longer needs:

| Current workaround | Lines | Replaced by |
|---|---|---|
| `src/gpu/dawn.h` (C bridge declarations) | ~150 | Direct `import from "webgpu.h"` |
| `src/gpu/dawn.c` (C bridge implementations) | ~750 | Compiler-generated marshalling |
| `src/gpu/constants.ms` (manual integer enums) | ~140 | Direct import of C enum constants |
| `src/gpu/descriptors.ms` (manual descriptor interfaces) | ~80 | Auto-generated extern interfaces from C structs |
| Flattened param pattern (`_1vb`, `_ext2`) | ~200 | Proper struct passing |

Total eliminated: ~1300 lines of manual bridge code.

Void still provides a library-level wrapper (e.g., `CullMode.Back` → `WGPUCullMode_Back`) for cross-platform API ergonomics. The string-based WebGPU spec API (`"back"`) is Void's JS-backend adapter, not a compiler concern.

---

## Implementation Priority

1. **Store optional field flag in parser** — trivial fix, unlocks everything else
2. **Add `TypeKind.StringLiteral`** — needed for string literal types in the type system
3. **Phase 5 C codegen foundation** — basic C emission (the whole next phase)
4. **Extern interface + C struct emission** — unlocks descriptor passing
5. **C enum constant emission** — verbatim pass-through of imported C enum names
6. **Array FFI lowering** — unlocks buffer/attribute arrays
7. **Nested descriptor flattening** — unlocks full WebGPU descriptor passing
8. **C header import** — unlocks `import from ".h"` (can defer if manual extern declarations work)

Items 1-2 are Phase 1-2 fixes (days). Items 3-7 are Phase 5 work (the main codegen effort). Item 8 can be deferred — manual `extern interface` declarations work as a stopgap.

---

## Reference

- Current Zig compiler: `~/projects/metascript/src/codegen/c/cgen.zig`
- WebGPU types (TypeScript spec): `~/projects/webgpu-types/dist/index.d.ts`
- Dawn C API header: `~/metascript/void/deps/dawn/include/dawn/webgpu.h`
- Void engine (current manual bridge): `~/metascript/void/src/gpu/`
- Nim FFI patterns (inspiration): `{.header.}`, `{.compile.}`, `{.importc.}`, `{.passC.}`, `{.passL.}`
