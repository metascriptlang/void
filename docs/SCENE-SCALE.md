# Scene model at scale — measurements and what they force (2026-09-15)

Numbers behind the choice of a columnar `Scene` over one object per node, the same benchmark run against real Heaps, and the design corrections that came out of reading Bevy. Measured because "does it scale to a million nodes" is not answerable by argument, and because the first benchmark run flattered the columnar model and had to be corrected.

## What was and was not measured

**MetaScript layouts**: `msc build --release` (`-O2`) on msc 0.2.54, single thread, one run each, no averaging, one machine.

**Heaps**: real `h3d.scene.Object` from `heaps@2b84cc2`, Haxe 4.3.7, compiled to **JS and run on node/V8** — not HashLink. HashLink's JIT does not exist on ARM, HL/C generation fails on hello world, and `haxelib` segfaults (exit 139) on this machine, so the library had to be cloned and passed with `-cp`. HL native would be faster than these figures. 1M did not complete in five minutes; **100k was measured and scaled ×10**, and extrapolated figures are marked as such.

**Bevy**: read, not benchmarked. Findings below are from source at `2bddbdfd7` with citations.

Not measured anywhere: multi-threading, GPU upload, and — see Open — tree traversal.

## The two MetaScript models

**Columnar** — one `interface Scene` holding parallel arrays, a node is a row index:

```ms
interface Scene {
	kind: uint32[]; flags: uint32[]; parent: uint32[];
	local: Transform[]; world: Transform[];
	payload: uint32[]; generation: uint32[];
	dirty: uint32[];
}
```

**Fat** — one `interface` per node, 40 fields inline plus a `children` array; 1M nodes is 1M heap allocations (2M counting each node's `children`).

## Results, N = 1,000,000

| | Columnar | Fat | |
|---|---|---|---|
| Build | 24.3 ms | 74.1 ms | cols 3.0× |
| Sweep touching **2 of 40** fields | **3.67 ms** | **35.9 ms** | cols **9.8×** |
| — same sweep, columns hoisted to locals | **0.92 ms** | — | 4× over the un-hoisted form |
| Sweep touching **20 of 20** fields | **41.1 ms** | **6.67 ms** | **fat 6.2×** |
| 1M random-index write + dirty mark | **7.97 ms** | 21.6 ms | cols 2.7× |
| Idle frame, scan 1M flags | **0.21 ms** | 4.62 ms | cols 22× |
| Flush 1M dirty entries | 2.06 ms | — | |
| Peak RSS | 181 MB* | 272 MB | |
| Bytes per node (data only) | **60 B** | ~272 B | cols ~4.5× |

\* the columnar program also allocated two spare 1M `Transform` arrays for a control measurement (~32 MB), and `Vec` doubling makes the peak roughly twice the live size.

The fat model carried 40 fields. `void2d/node.ms` carries **71**.

## The reversal, and why it is the important row

The 2-of-40 sweep is the columnar model's best case and the first benchmark measured only that. Touching all 20 fields of 20 columns reverses the result: **41.1 ms columnar against 6.67 ms fat, a 6.2× loss.** Twenty columns are twenty separate streams and twenty cache-line misses per node; twenty fields of one object are one or two lines.

The rule that falls out is therefore not "columns are faster". It is:

> **Group columns by access pattern, not by field.** Fields that a pass reads together belong in one struct column.

`local: Transform[]` — x, y, z, scale in 16 bytes, one column, one cache line — is why the transform sweep measured 3.67 ms and not 41. Splitting it into `x[]`, `y[]`, `z[]`, `scale[]` would have produced the bad row.

The random-access row was not predicted: the fat model loses (21.6 ms against 7.97 ms) because an `interface` element is a pointer, so `fat[k]` costs two dependent cache misses where `column[k]` costs one. Per-node heap allocation, not field layout, is what makes the fat model slow at scattered access.

## Real Heaps, measured

100k real `h3d.scene.Object`, Haxe → JS, node/V8:

| | 100k measured |
|---|---|
| Build | 41.6 ms |
| `o.x = v` (set + `posChanged`) | 1.88 ms |
| `syncPos()` | 16.5 ms |
| Random `o.x = v` | 5.23 ms |
| Idle scan | 4.72 ms |
| Heap | 53 MB → **530 B/node** |

Scaled ×10 against the columnar figures measured at 1M:

| | Heaps (×10, extrapolated) | Columnar (measured) | |
|---|---|---|---|
| Build a scene | ~416 ms | **24.3 ms** | 17× |
| **Set one property** | **~19 ms** | 23.3 ms | **Heaps faster** |
| Whole change cycle (set + sync/flush) | ~184 ms | **25.4 ms** | **7.2×** |
| Idle frame | ~47 ms | **0.21 ms** | 224× |
| Bytes per node | 530 B | **60 B** | 8.8× |

**The middle row is the one to learn from.** Heaps' setter is

```haxe
inline function set_x(v) { if( x != v ) posChanged = true; x = v; return v; }
```

— an inlined field write plus one flag bit. The binder is slower because `markDirty` **pushes to a `Vec`**. Heaps keeps no dirty list, so it must walk the tree to find dirty nodes and pays at sync time instead (~165 ms/1M for `syncPos`).

The trade is therefore: **pay at set time and keep a list, or pay at sync time and walk the tree.** The columnar model wins the whole cycle 7.2×, but not because its setter is faster. It is not.

Each `h3d.scene.Object` allocates four times — itself, `absPos` (a `Matrix`), `qRot` (a `Quat`), and `children` (an `Array`). That is where 530 B/node comes from.

## Design rules these numbers force

1. **Group by access pattern.** The decision that matters most.
2. **Columns are `Vec<T>`; passes take `Span<T>`.** `Vec` is 2.6× faster than `Array<T>` (which is what `T[]` means), and `Span` is the only parameter form that both compiles and writes through. Never bind a `Vec` column to a plain local — that copies it and silently discards the writes. Hoisting buys no speed; see the next section, where the earlier two versions of this rule were both wrong.
3. **The binder path costs ~23 ns per node** (`setX` plus `markDirty`), against ~1–4 ns per node for a direct column sweep.
4. Therefore **continuous per-frame state must not go through binders.** At a 16.7 ms budget the binder path carries thousands of nodes, not millions; transform and animation are column sweeps. Routing animation through binders recreates the particle problem at smaller scale.
5. **Preallocate columns.** `Vec` doubling gives a 2× memory spike at realloc, multiplied by the column count.
6. **Idle is free.** 0.21 ms to scan 1M flags, and with the `dirty` list there is nothing to scan at all.

## Which array kind a column should be

`T[]` and `Array<T>` are the same type — a reference, `createRef(createArray(T))` at `src/checker/resolvePass.ms:582-584`. `Vec<T>` is a different type: a **value** array, `createArray(T)` at `:585-587`. `Span<T>` is a third: a non-owning view.

1M sweep, one process per variant, a full untimed warm-up sweep before timing, 7 timed repetitions × 5 interleaved rounds = 35 samples each. Machine under load average 14–17, so absolute milliseconds are pessimistic.

| variant | min | median | p90 |
|---|---|---|---|
| `T[]`, direct | 1.523 | 1.640 | 2.082 |
| `Array<T>`, direct | 1.509 | 1.695 | 2.283 |
| **`Vec<T>`, direct** | 0.502 | **0.643** | 0.886 |
| `T[]`, hoisted to a local | 1.546 | 1.591 | 4.599 |
| `Array<T>`, hoisted to a local | 1.512 | 1.580 | 2.618 |
| **`Vec<T>` bound to a `Span<T>`** | 0.505 | **0.639** | 0.918 |

- **`Vec<T>` is 2.6× faster than `Array<T>`**, and `T[]` measures identically to `Array<T>` because it *is* `Array<T>`.
- **Hoisting is not a performance technique.** For reference arrays it changes nothing (1.640 → 1.591, inside the noise). `Span` is not faster than direct `Vec` access either (0.639 vs 0.643); it exists for correctness, below.
- **`const loc = s.local` on a `Vec` column copies it, and writes through the copy are lost.** Measured directly: write 99 through the hoisted name, read 10 back from the column. The same line on an `Array` column writes through (99), and via a `Span` it writes through (77). This is value semantics working as designed, but it is a silent data-loss trap for anyone carrying the habit over from JS.
- **Passing a column to a function**: a `Vec<T>` parameter is correctly rejected at compile time ("cannot mutate value-type parameter" — the copy would swallow the write); `ref c: Vec<T>` crashes codegen with `internal: unresolved type (kind=48)`, a known open bug; `Span<T>` works; `Array<T>` works but carries the slower storage. **`Span<T>` is the only working way to pass a `Vec` column into a pass.**

Two corrections to what is written above:

- **The first version of design rule 2 was wrong twice.** It first claimed hoisting gives 4× (3.67 → 0.92) — that was one un-repeated run with a warm cache; repeated properly, hoisting gives nothing. The correction that replaced it then claimed `Span` speeds a `Vec` up 1.56 → 0.55; that was an order-of-execution artifact too. Hoisting buys no speed at all. What it buys is the difference between a copy and a view.
- **Every other benchmark in this document used `T[]`**, i.e. `Array<T>`. The columnar figures are therefore ~2.6× pessimistic against a `Vec` + `Span` implementation, and the columnar-versus-fat gaps would widen accordingly. They have not been re-run; do that before quoting the headline numbers as the model's real cost.

A full 1M-node column sweep is 0.9–3.7 ms and fits with room for cull, sort, upload and draw. The same sweep on the fat model is 35.9 ms — over budget twice before a pixel is drawn. That is a statement about the layout at a scale h3d was never aimed at, not a defect in Heaps.

## The tree-traversal risk, and Bevy's answer

Walking `firstChild`/`nextSibling` over 1M nodes is pointer-chasing through random indices with a cache miss per step. Three changes remove the risk; all three are read out of Bevy at `2bddbdfd7`.

### Drop sibling links for a child arena

Bevy has no sibling links anywhere. `crates/bevy_ecs/src/hierarchy.rs:154` is `pub struct Children(Vec<Entity>)` — children are a contiguous array, and even the descendant iterator uses an explicit stack rather than links.

Do not copy the shape exactly: a `Vec` per parent is one allocation per parent, and child removal is a `position()` scan plus an order-preserving `Vec::remove`, O(n) per child. Instead keep two columns `childStart: uint32[]` and `childCount: uint32[]` indexing one shared `childIndices: uint32[]` arena, so a node's children are a contiguous slice with no per-node allocation. Reparenting appends and leaves a hole; compact when waste crosses a threshold.

### Mark dirty upward with an early-out, then prune on descent

`crates/bevy_transform/src/systems.rs:43-70`. The `break` is the whole algorithm:

```rust
let mut next = entity;
while let Ok((child_of, mut tree)) = transforms.get_mut(next) {
    if tree.is_changed() && !tree.is_added() { break; }
    tree.set_changed();
    if let Some(parent) = child_of.map(ChildOf::parent) { next = parent; } else { break; };
}
```

Total work is not `changed × depth` but the size of the union of ancestor paths: of 1000 changed siblings under one parent, the first pays `depth` and the other 999 pay one step.

Descent then enters only roots carrying the bit and prunes twice (`systems.rs:450-459`) — once on the subtree bit, once on value equality via `set_if_neq`, so a parent whose world matrix did not actually move stops its children even when flagged. Leaves are computed inline and never enqueued (`systems.rs:461-466`), and nodes with neither parent nor children run as a separate flat pass (`sync_simple_transforms`, `systems.rs:12-41`).

Recorded caveat, commit `8130b229b`: *"This causes a performance regression when spawning many entities, or when the scene is entirely dynamic."* It landed, was reverted (#18363), and re-landed.

The alternative Bevy also ships: `visibility_propagate_system` (`crates/bevy_camera/src/visibility/mod.rs:419-456`) does **no** upward marking at all — it descends straight from the changed set, pruned only by value equality. For serial propagation that is simpler and cheaper, and it maps directly onto the existing sparse `dirty` list. **Measure both.**

### Flatten traversal order once per structural change

`crates/bevy_ui/src/stack.rs:11-19` — `UiStack` is a `Vec<Entity>` in draw order rebuilt by DFS, with each node's position written back into it (`stack.rs:94`), and scratch buffers pooled rather than allocated per node (`stack.rs:21-33`).

A `drawOrder: uint32[]` rebuilt only when structure changes is what actually converts a tree walk into an array scan: cull, batch and submit all iterate it linearly. It composes with the dirty-subtree work, because structure changes rarely.

## Corrections to the model that Bevy forces

- **Grouped columns produce false dirties.** One flag over `Transform` covers four fields. Bevy hit this with `ComputedNode` (ten co-computed fields) and needed an explicit escape: `bypass_change_detection` (`change_detection.rs:153`), used for real at `crates/bevy_ui/src/ui_node.rs:46-73` and `stack.rs:94`. The binder needs **two** setters — a dirtying one and a quiet one — plus `set_if_neq` (`change_detection.rs:198-210`) on whole groups.
- **The flag-plus-list has exactly one reader.** A bit answers one question for one consumer and someone must clear it. Bevy stores `added_ticks` and `changed_ticks` as parallel `u32` columns (`storage/table/column.rs:18-23`), which answers "changed since *my* last run" independently for consumers on different cadences. Adding one `changedTick: uint32[]` **per column group** (not per field) costs 4 B/node and closes this; skip added-ticks, since `generation` already answers "is this new". Handle wraparound Bevy's way — `wrapping_sub` comparison plus a periodic clamping sweep (`component/tick.rs:53-86`, `change_detection.rs:19-32`) — and note the determinism argument recorded at `tick.rs:58`: an unclamped comparison is a silent correctness bug that appears after an hour of runtime.
- **Generation wrap is unhandled.** Bevy detects and warns (`entity/mod.rs:885-892`). A silently aliased `NodeId` in a scene graph is unfindable from a symptom.
- **`NodeId` layout.** Put `index` first, align to 8, and compare as one `uint64` (`entity/mod.rs:375-394`, with the recorded reason that derived comparison codegen was worse). Sorting `NodeId`s then also sorts by row, i.e. ascending in memory.

## Confirmed, not challenged

- **Grouping columns by pass.** Bevy's `Transform` is one component holding translation, rotation and scale; `GlobalTransform` is a single `Affine3A`; `ComputedNode` is ten fields in one struct. Bevy splits by component, never by field — the same conclusion as the 6× measurement above.
- **Stable rows with a generation and a free list.** Bevy uses `swap_remove` so tables never have holes, and pays an `Entity → EntityMeta → EntityLocation → row` indirection on every random access. It can do that only because `Query` iteration never names a row. A scene node is named by handles, parent links and script; keep stable rows and accept holes. The free list should stay a separate dense LIFO stack, as Bevy's `pending: Vec<EntityRow>` is (`entity/mod.rs:710-755`), so freeing never touches a cold payload row.
- **`payload: uint32` into a per-kind side table.** This is the sparse-set pattern, and the useful datapoint is how little Bevy uses it: exactly one non-test production component in the engine (`SyncToRenderWorld`) chooses sparse-set storage; everything else is a table. The bar for splitting an attribute into a side table is high — anything a full-scene pass touches belongs in a real column even if rows are wasted.

## For the `Instances` node

`crates/bevy_render/src/batching/gpu_preprocessing.rs:267-284` is the same shape: a persistent slot array plus a `uint32` LIFO free list, **never cleared per frame** (`:1160-1165`, *"we want to reuse those allocations"*), with only changed entries rewritten.

Two flaws there not to copy: the free check is `free_uniform_indices.contains(&i)`, a linear scan (`:334`), and the buffer never shrinks.

One gap worth exploiting: `RawBufferVec::write_buffer_range` exists (`render_resource/buffer_vec.rs:186-209`) and a repo-wide search finds **no call sites** — Bevy re-uploads the whole instance array every frame even when three entities moved. A dirty list already exists here, so uploading ranges is a straightforward win over what Bevy ships.

Also worth taking: `UninitBufferVec` (`buffer_vec.rs:453-473`) reserves GPU slots with no CPU mirror, for buffers only the GPU writes; and keep on the CPU only what CPU logic reads — Bevy's GPU path keeps just `translation` per instance, for distance sorting (`crates/bevy_pbr/src/render/mesh.rs:692-707`).

## Open

- The child arena, upward dirty marking and flattened draw order are **read, not measured**. Build them and measure, including Bevy's recorded spawn-heavy regression, and against the simpler descend-from-the-dirty-list alternative.
- 0.92 ms benefits from a cache warmed by the preceding loop; ~3.7 ms is the honest figure for a cold full sweep.
- Heaps figures are JS/V8 and extrapolated ×10 from 100k. A HashLink number would be better and could not be obtained on this machine.
- Single run, single thread, no averaging, except the column-kind table, which is a median of six. The single-run figures are the ones that produced the one wrong rule in this document; treat any of them that carries a decision as provisional until repeated.
- The machine carried a load average of 14–17 throughout (other sessions, MCP servers). Absolute milliseconds are pessimistic; ratios measured in the same run are not.
- The headline columnar figures were taken with `T[]` columns and should be re-run with `Vec<T>` + `Span<T>`.

## Reproducing

MetaScript: four programs, each a `main()` printing `performance.now()` deltas around the loop under test — build-and-sweep columnar; the same against a 40-field fat node; 20 columns against 20 fields; and a strided random pass (`k = (k + 7919) % N`) to defeat prefetch.

Heaps: clone `heaps` and `HaxeFoundation/format`, pass both with `-cp` (haxelib is unusable here), subclass `h3d.scene.Object` to expose the private `syncPos()`, and compile with `haxe -js bench.js -main Bench -cp heaps -cp format -D js-es=6`. `Sys.println` is unavailable on the JS target; `untyped console.log` works. Run under `node --max-old-space-size=8192`, and write output to a file rather than a pipe — a killed run loses buffered stdout, which reads as a hang.

All of it was run from a session scratchpad and is not checked in.
