# PENDING3D — void3d's known divergences and gaps, read by the gate

One entry per known divergence from Heaps, deliberate deferral, or measurement this port does
not have yet. The rule is rexa's, unchanged, and is the same one
[tests/PENDING.md](PENDING.md) states for void2d:

> **A listed case that stops holding fails the run**, and its entry is deleted in the same
> commit as the fix.

That is what keeps the list from going stale, and it is why the list can be seeded
aggressively. void2d keeps its own list; this file is void3d's, so the two never collide the
way `docs/REVIEWS.md` and `docs/REVIEWS-3D.md` are kept apart.

**How a row is enforced.** Each row carries a **sentinel**: a `// PENDING3D: <id>` comment at
the site of the divergence, or a sentence in a doc that states the gap. The `pending` stage of
`scripts/gate3d.sh` checks both directions and fails on either:

- a row here whose sentinel is **gone** — the divergence was fixed and the row was not deleted;
- a sentinel in the tree with **no row** here — a divergence was marked and never written down.

So deleting the code comment without deleting the row turns the gate red, and so does the
reverse. A prose list has no forcing function; this one does. There is no escape hatch: the
`pending` stage's default branch requires a tag for every id it does not special-case, so a row
naming a sentinel nobody wrote fails rather than being skipped.

**How far that reaches, measured rather than implied.** The `pending` stage observes that a
**sentinel is present**, not that the **divergence still holds**. Those are different claims,
and only three of the rows below have the second one enforced: `bounds-transformed-or`,
`bounds-empty-size-zero` and `bounds-sphere-rescale` each carry a `diverges=` case in
`tests/oracle/bounds3d.cases`, which the `oracle` stage checks in both directions against real
Heaps. The control: making `size()` answer Heaps' −2e20 while leaving its `// PENDING3D:` line
untouched leaves `pending` **green** and turns `oracle` **red** with two GRADUATED lines. For
the other six rows there is no second stage, so fixing the divergence and forgetting the
comment keeps the gate green — the row would survive until a reader noticed. The two rows
whose sentinel is a sentence in `docs/VOID3D.md` are weaker still: they track the *prose*, so
rewording the sentence reddens the gate and changing the world behind it does not.

Where a row can be given a behavioural sentinel, it should be. That is what an oracle case is
for, and it is why the three bounds rows are the ones to copy.

## Rows

| id | what holds today, and why | sentinel | removed by |
|---|---|---|---|
| `bounds-transformed-or` | `transformed` treats a box empty on **any** axis as empty, where Heaps (`Bounds.hx:159`) tests all three with AND and transforms it anyway. **Measured against real Heaps** (`tests/oracle/bounds3d.cases`, `negative-axis-transformed`): a box with a negative size on one axis, translated by +10x, gives Heaps `10 -1 0` and this port `0 0 0`. Narrower than first written — a *flat* axis (min == max) is empty under neither rule, so the divergence needs a genuinely negative extent. | `src/void3d/bounds.ms` | deliberate — deleted only if Heaps parity is chosen over it |
| `bounds-empty-size-zero` | `size()` and `dimension()` answer zero on an empty box; Heaps answers −2e20 per axis. **Measured, not cited**: real Heaps at `2b84cc2` returns `-200000000000000000000` for both (`tests/oracle/bounds3d.snapshot`). | `src/void3d/bounds.ms` | deliberate |
| `bounds-sphere-rescale` | `boundingSphereRadius` scales by the longest edge before squaring, because `Bounds.all()` spans 2e20 and its square is infinity in float32; Heaps squares directly on float64. **The oracle corrected this row**: the two *answers* agree to 4.6e-9 relative (`1.7320508075688775e20` against `1.7320508156113480e20`), so this is a divergence in method and not in behaviour. The row stays because simplifying the code back to Heaps' form returns infinity, and `unbounded-sphere` is the case that would then go red. | `src/void3d/bounds.ms` | deliberate |
| `upload-mesh-leaks-on-replace` | `uploadMesh` never destroys the buffers it replaces. Correct for a real context loss, where they are already gone; a leak of two buffers per swap once something re-uploads a live mesh. | `src/void3d/draw.ms` | M9, which is the first to re-upload live meshes |
| `scene-flags-not-bitset` | Node flags are bits in an `int32` where CODE-STYLE §4 asks for `BitSet<E>`. A version floor: msc 0.2.53 has no `BitSet`. | `src/void3d/scene.ms` | whichever msc first ships `BitSet` |
| `mesh-node-name-collision` | The scene's mesh writer is `addMeshNode` rather than Heaps' name, because two `ref`-receiver free functions with one name resolve to the wrong one **silently** (compiler card `2026-09-20-ref-receiver-not-an-extension.md`). | `src/void3d/scene.ms` | when a `ref this` receiver parses |
| `light-params-divergence` | A light node carries `radius` and `power` where Heaps' fwd PointLight carries `params` (constant, linear, quadratic attenuation) and its DirLight folds intensity into color: the toon shader quantizes total energy before multiplying color, and folding power in would quantize at a different place. The block holds one directional and four point slots, and a scene past that is an error rather than the silent top-N drop fwd.LightSystem does. | `src/void3d/scene.ms` | deliberate |
| `baselines-adopted-circular` | `m3preview_*`, `m3direct_*` and `m3depth_*` were adopted at `16c6546` because the M4 worktree's copies were never carried over. Comparing against an adopted image is circular; the non-circular evidence is gone. | `docs/VOID3D.md` phrase `plausible* M4 images` | never — it is a permanent hole in the record, kept visible |
| `gles3-emulator-only` | The GLES3 path now runs — `tests/device/gles3Campfire.png` is the frame — but on the **Android emulator** (`ro.hardware.egl=emulation`, arm64 under binary translation), not on a device, and against no baseline. Every byte-identity claim in this port remains D3D11-only, including the FMA result. | `docs/VOID3D.md` phrase `not a device` | a run on the Seeker, compared against something |

## Not covered here, deliberately

`docs/VOID3D.md` "Still missing" carries the narrative gaps that are milestones rather than
divergences — lights, glTF, animation, picking, particles. A milestone that has not happened is
not a pending divergence; it is the roadmap. The distinction matters because this list is meant
to be short enough that every row is read.
