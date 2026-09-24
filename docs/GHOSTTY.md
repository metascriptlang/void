# Ghostty — Reference for void2d text (2026-09-20)

[Ghostty](https://github.com/ghostty-org/ghostty) is a terminal emulator (Zig; Metal and OpenGL renderers). It is a reference for **one thing**: dense text that is sharp, fast and smooth — its font stack, its atlas, its blend-space handling, and its frame discipline. It is a pixel-aligned monospace **cell grid**, not a UI renderer: boxes, shadows, layout, z-order and scroll do not map. The entry point for void2d's decisions is [VOID2D.md](VOID2D.md); the model Ghostty is cross-checked against is [GPUI.md](GPUI.md).

Source: `~/projects/ghostty` (shallow clone) at `a301054`. Paths are relative to `src/`. Read from source on 2026-09-20; nothing was built or benchmarked.

## What Ghostty is

| | |
|---|---|
| Backends | Metal, OpenGL **4.3 core** (needs SSBOs and `sampler2DRect`, `renderer/OpenGL.zig:37-39`). One generic renderer over a comptime `GraphicsAPI` (`renderer/generic.zig:48-99`). A `webgl` backend is declared for wasm (`renderer/backend.zig:5-22`) but `renderer/WebGL.zig` is two lines — no browser renderer exists. |
| Shaders | Two hand-written ports, `shaders.metal` and GLSL. They have drifted: the cursor-cell colour is loaded with `use_linear_blending` in GLSL and `true` in Metal (`shaders/glsl/cell_text.v.glsl:144` vs `shaders/shaders.metal:668-672`). |
| Frame | **Three draws**: one full-screen triangle for the global background, one full-screen triangle that looks up `bg_cells[floor(fragCoord / cell_size)]`, one instanced strip for all text (`generic.zig:1850-1949`, `shaders/glsl/cell_bg.f.glsl:13-57`). No batching logic: a grid has a fixed z-order. |
| Instances | `CellText`, **32 bytes**: atlas pos/size `u32×4`, bearings `i16×2`, grid pos `u16×2`, colour `u8×4`, atlas kind, flags (`renderer/metal/shaders.zig:262-289`). Backgrounds are a flat `rows × cols` array of `[4]u8` — no geometry. |
| Font backends | CoreText (macOS), FreeType + fontconfig (Linux), FreeType + a directory scan (Windows), chosen at comptime (`font/backend.zig:3-61`). Shaping: HarfBuzz or CoreText. |
| Threads | One renderer thread per surface, woken by coalescing async notifications (`renderer/Thread.zig:200-257`). |

## Mechanisms

### Font collection and fallback

- Four styles (regular, bold, italic, bold-italic), each a priority-ordered list of faces (`font/Collection.zig:37, 698`). Construction order is fixed: the user's families, then an embedded mono font, an embedded symbols font, then emoji (`font/SharedGridSet.zig:158-409`).
- **Deferred faces** answer "do you have this codepoint, in this presentation?" without loading the font (`font/DeferredFace.zig:326-420`).
- **Explicit vs fallback**: a face the user chose accepts any presentation; a fallback face must match text-vs-emoji presentation exactly (`Collection.zig:737-751, 804-835`).
- Codepoint → face is a seven-step resolver (`font/CodepointResolver.zig:87-228`): override map → sprite → presentation → loaded faces in order → *regular style of a loaded face before any system fallback*, because "styles in other fonts often change metrics like glyph widths" (`:106-111`) → system discovery → last resort.
- The result is cached per `(style, codepoint, presentation)`, **misses included**, behind an `RwLock` (`font/SharedGrid.zig:42, 163-198`).
- A multi-codepoint grapheme takes the first font that covers all of it (`font/shaper/run.zig:318-382`).
- **Fallback size harmonisation**: a fallback face is scaled so its `ic_width`, else `ex_height`, else `cap_height`, else `line_height` matches the primary's, in em units — CSS `font-size-adjust` (`Collection.zig:572-664`). GPUI has nothing like it.
- **Variable-font axes** are first-class (`font-variation*`, applied at deferred load; `font/face/freetype.zig:278-318`), and bold/italic are derived from axes for matching (`font/discovery.zig:748-844`).
- **Synthetic styles** when a family lacks one: outline embolden by `ceil(height · 64/2048)`, a 12° outline skew, else an alias to regular (`Collection.zig:321-467`, `freetype.zig:441-449, 538-569`).
- Discovery is per OS. The Windows one is a stopgap: it walks the fonts directories and opens every file on each query, ignores style, and admits "tens of milliseconds" per name query (`discovery.zig:954-1166`).

### Shaping

- A run never crosses a row and breaks on **any style difference except background** — "This prevents a single glyph for `>=` to be rendered with one color when the two components have different styling" (`font/shaper/run.zig:109-147, 385-396`). It also breaks at the **cursor cell** (`:178-209`), at selection edges, on a font change, and on a hard-coded list of unwanted ligatures (`fi`, `fl`, `st`, `:115-137`).
- **Run cache**: a u64 hash of `(codepoint, cluster relative to the run start)` pairs plus length and font — **position-independent**, so it hits across rows and survives scroll. Fixed size, 256 buckets × 8, LRU inside a bucket (`run.zig:87-91, 288-310`, `font/shaper/Cache.zig:33-45`). The motivation: "shaping was the most expensive part of rendering text (accounting for 96% of frame time on my machine)" (`Cache.zig:3-6`).
- Shaped positions are **rounded to whole pixels** (`font/shaper/harfbuzz.zig:229-251`). LTR only.

### Rasterization

- **Two policies ship.** macOS: CoreText, unhinted, quantisation off, the glyph's fractional offset baked into the raster (`font/face/coretext.zig:398-413, 485-494`). Everywhere else: FreeType with `hinting = true, autohint = true, light = true` as defaults (`config/Config.zig:9832-9844`). The stated reason for `light` is conformity — it "appears to be the effective default with most Fontconfig-aware software" — not a measurement.
- **Hinting and outline transforms do not mix.** Hinting is turned off whenever a glyph is scaled or moved by a constraint (`freetype.zig:357-361`), and a centring offset is rounded to a whole pixel because a fractional move "completely ruins the hinting" (`:503-512`). Outlines are transformed first, then rendered (`:530-576`).
- **No subpixel variants** — not needed: on an integer grid every occurrence of a glyph sits at the same fractional phase. Glyphs are drawn 1:1, texel-exact, with nearest sampling at pixel coordinates (`cell_text.v.glsl:100-108`, `shaders.metal:684-688`).
- Cell metrics are integers: `cell_width = round(max ASCII advance)`, integer baseline (`font/Metrics.zig:236-283`).
- No LCD/ClearType anywhere. No stem darkening on FreeType; `font-thicken` is CoreText-only.
- Colour emoji: FreeType `FT_LOAD_COLOR`, no SVG glyphs (`freetype.zig:340-347`), BGRA, bitmap strikes resized on the CPU.

### Atlas

- Skyline bottom-left packer (`font/Atlas.zig:3-7, 153-251`); two atlases per grid, grayscale and BGRA, starting at 512² (`SharedGrid.zig:92-95`).
- When full it **doubles, and every existing glyph keeps its position**: old rows are copied to the same x/y and one skyline node is appended for the new strip (`Atlas.zig:314-364`), so cached atlas coordinates never go stale.
- No padding between glyphs (safe under nearest sampling), no eviction, no size cap. A size or DPI change makes a **new grid with new atlases** and drops the old one (`SharedGridSet.zig:738-757`), so zooming does not leak — it re-rasterizes everything.
- GPU sync: an atomic `modified` counter compared against a per-consumer watermark; the **whole atlas** is re-uploaded when it moved (`generic.zig:1829-1844, 3616-3630`). Each of the three swap-chain frame states holds its own copy of both textures.
- Glyph key: `(face index, glyph id, cell width class, thicken, constraint width)` packed in a u64; colour is not in it (`SharedGrid.zig:472-516`).

### Procedural sprites

Box drawing, blocks, braille, powerline, **underlines, strikethrough and cursors** are rasterized procedurally into the atlas at exact cell metrics and claim their codepoints before any font (`font/sprite.zig:17-36`, `font/sprite/Face.zig:55-250`). What makes neighbours join exactly:

- integer thickness with a floor of 1 px, integer positions (`Metrics.zig:58-71, 298-319`);
- **complementary rounding** for fractional splits: `min = size − round((1−f)·size)`, `max = round(f·size)`, so the two halves of 7 px are 0→4 and 3→7 rather than a gap (`font/sprite/draw/common.zig:206-233`);
- decoration position and thickness come from the font's `post` / `OS/2` tables, with fallbacks for broken tables (`Metrics.zig:187-218`, `freetype.zig:922-962`).

An underline is an instance emitted *before* its glyph, strikethrough after (`generic.zig:3200-3308`).

### Blend space

`alpha-blending = native | linear | linear-corrected`; default `native` on macOS, `linear-corrected` elsewhere (`Config.zig:384-412`).

- `linear` (sRGB target) removes the dark fringes that gamma-space blending produces between saturated colours (red on green), but "makes dark text look much thinner than normal and light text much thicker".
- `linear-corrected` keeps linear blending and remaps coverage so the blended **luminance** equals what gamma-space blending would give (`cell_text.f.glsl:47-67`):

```glsl
float fg_l = luminance(color.rgb);
float bg_l = luminance(bg.rgb);
if (abs(fg_l - bg_l) > 0.001) {
    float blend_l = linearize(unlinearize(fg_l) * a + unlinearize(bg_l) * (1.0 - a));
    a = clamp((blend_l - bg_l) / (fg_l - bg_l), 0.0, 1.0);
}
```

It **needs the destination colour per glyph**, which a terminal has (`bg_cells[grid_pos]`, read in the vertex shader, `cell_text.v.glsl:115-128`). `minimum-contrast` uses the same lookup (`shaders/glsl/common.glsl:77-110`).

This and GPUI's `apply_contrast_and_gamma_correction` are **alternatives tied to the blend space**, not stackable: GPUI blends in gamma space and reshapes coverage from the text colour alone; Ghostty blends in linear space and reshapes coverage from text and background.

### Frame discipline

- Row-level dirty bits: only dirty rows are re-shaped and re-emitted into per-row instance lists (`renderer/cell.zig:42-216`, `generic.zig:2569-2862`). The lists are concatenated and the **whole buffer is uploaded** on every drawn frame (`:1817-1819`) — dirty rows save shaping, not bandwidth.
- Update and draw are split: wakes update CPU state; on macOS a display link draws, and runs only while something was rebuilt (`Thread.zig:464-466`, `generic.zig:1241-1253`). With nothing to do there is no GPU work and no present; the last frame stays on the layer (`:1735-1747`). Hidden surfaces free their GPU resources (`:1156-1192`).
- The **cursor is its own instance** and cursor-cell recolouring is a uniform, so a blink or a caret move never re-emits text (`cell.zig:136-154`, `cell_text.v.glsl:139-145`).
- Three frame states behind a semaphore; the host can draw synchronously on the main thread during a live resize, and a late async frame of the wrong size is discarded (`generic.zig:280-368`, `Surface.zig:880-887`, `renderer/metal/IOSurfaceLayer.zig:105-109`).
- Pipelines, device and the font database are warmed up off the first-frame path (`renderer/Metal.zig:405-441`, `discovery.zig:353-367`).
- The terminal lock is held only to snapshot state; rebuild runs outside it, with a fairness handoff so the producer cannot starve the renderer (`renderer/State.zig:36-67`).
- **Scroll is whole rows only** and re-emits every visible row (`Surface.zig:3532-3555`, `terminal/render.zig:408-411`). No profiler or counters exist.

## Disposition

Reasons as in [GPUI.md](GPUI.md): **N** Neon/host covers it, **W** worse than what Void has, **P** not portable. **G** = only valid on a pixel-aligned monospace grid.

| Ghostty | Disposition | Note |
|---|---|---|
| 1:1 texel-exact glyph sprites, integer baseline, colour out of the glyph key, R8 + BGRA atlases selected per instance | **Confirms** GPUI.md | |
| Runs never span a style change; decorations and cursor as instances of the text pipeline; hairline ≥ 1 px | **Confirms** | |
| Build instances on the CPU, upload, draw ranges; nothing dirty → no work | **Confirms** | |
| Hand-ported shaders drift | **Confirms** "one GLSL source" | |
| Font collection: ordered faces per style, deferred faces, explicit-vs-fallback presentation, negative-caching codepoint map, whole-grapheme selection, embedded last-resort fonts | **Take** | the fallback design for the glyph layer; GPUI's is "per grapheme by coverage" and no more |
| Fallback size harmonisation (`ic_width → ex_height → cap_height → line_height`) | **Take** | metrics only; an editor mixing CJK or symbols with a Latin mono font needs it |
| Variable-font axes; style derived from axes | **Take**, at P6 only if the T5 capture beside Zed asks for them (the rasterizer was decided at P3 step 8) | stb_truetype has no `fvar`/`gvar` |
| Synthetic bold / italic policy | **Take**, module | |
| Decoration metrics from `post` / `OS/2`, with broken-table fallbacks | **Take** | fixes a GPUI weakness |
| Complementary rounding for fractional splits | **Take** | into the snapping rules: split panes, progress bars, table columns |
| Caret and selection as their own instances, never part of the text range | **Take** | a blink must not dirty a text run |
| "A repack never moves a live tile"; atomic `modified` counter vs per-consumer watermark | **Take, adapted** | void2d keeps pages; the rule keeps persistent instance ranges byte-identical, the counter drives dirty-page upload and a second window |
| Shaping break at an index (caret), suppress-ligature list | **Take the mechanism** | as an input on `Text`; the defaults are terminal UX |
| Position-independent run hash + fixed-size bucketed LRU | **Take, inside the shaper module** | GPUI.md keeps the node-held layout; this is the right shape for the "same string shaped twice" carve-out and for tokens recurring across lines |
| Hinting only without outline transforms; shift the outline before hinting | **Take**, as a constraint on the rasterizer decision | hinting belongs to the pixel-exact regime only |
| Warm-up; synchronous draw during live resize; release GPU resources when occluded; discard late frames of the wrong size | **Take** (requirements on the host-facing API) | |
| Procedural sprite glyphs (box drawing, blocks, braille) | **Take**, optional module | needed by a terminal widget; tiles seamlessly whatever the font |
| Blend space as an explicit, documented knob; `linear-corrected` | **Take, adapted** | void2d blends in gamma space with GPUI's function. Record the known artifact. The bg-aware correction is an opt-in only for text that declares a solid background (an editor buffer) |
| Integer shaped positions and advances; hinted advances feeding layout | **G** | the fontstash defect GPUI.md rejects |
| One raster per glyph, no variants | **G** | proportional, unrounded text needs the four x-variants |
| Background as a colour array shaded by one triangle; per-glyph knowledge of the destination colour; `minimum-contrast` | **G** | |
| Fixed three draws, no z interleaving | **G** | |
| Whole-buffer and whole-atlas re-upload every change, ×3 frame states | **W** | fine at 30k × 32 B; not at SCENE-SCALE |
| Single unbounded doubling atlas, no eviction, dropped wholesale on zoom | **W** | a UI has many sizes live at once |
| Scroll = re-emit integer rows | **G/W** | an editor needs pixel-smooth scroll; neither Ghostty nor GPUI has a cheap path |
| SSBOs, `sampler2DRect`, GL 4.3 | **P** | |
| Windows font directory scan | **W** | discovery is host work; hand void2d bytes |
| LTR-only, monotonic-x assumption | **G** | |
