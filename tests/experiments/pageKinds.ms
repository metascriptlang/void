import { DEFAULT_FONT } from "../../src/void2d/font";
// P3's atlas page-kind experiment (docs/VOID2D.md P3, "Atlas page kinds"): one workload through
// the real glyph atlas and packer, read two ways. R8 pages are what void2d has; the four-plane
// alternative packs the same tiles into the four channels of RGBA pages, which is the same
// packer with plane p living on RGBA page p / 4, so both readings come from one run.
// No GPU: the atlas, its CPU pages and the placement are all CPU-side.

import { allocateLabelText, shapeLabel, placeLabel, glyphAtlas, glyphRasterizations } from "../../src/void2d/labelText";
import { GlyphAtlas, NO_GLYPH_PAGE } from "../../src/void2d/glyphAtlas";
import { trs2d } from "../../src/void2d/types";

const CODE: string = "fn layout(node: &Node, width: f32) -> Size { node.measure(width) } // 0123456789";
const PROSE: string = "The quick brown fox jumps over the lazy dog; Sphinx of black quartz, judge my vow!";
const ICONS: string = "← ↑ → ↓ • ◦ ▸ ▾ ✓ ✗ ★ ☆ ⌘ ⌥ ⇧ ⏎ ⌫ … · ¶ § † ‡ ©";
const SIZES: float32[] = [12.0, 13.0, 14.0];
const DPIS: float32[] = [1.0, 1.5];
const STRESS_SIZES: float32[] = [12.0, 13.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 32.0, 40.0];
const STRESS_DPIS: float32[] = [1.0, 1.25, 1.5, 2.0];
const ICON_SIZES: float32[] = [16.0, 24.0];
const R8_PAGE_BYTES: int32 = 1024 * 1024;
const RGBA_PAGE_BYTES: int32 = 4 * R8_PAGE_BYTES;

const pageOrder: Vec<int32> = new Array(0);

function place(text: string, size: float32, dpi: float32, x: float32): void {
	const index = allocateLabelText();
	shapeLabel(index, text, {
		font: DEFAULT_FONT,
		size: size,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: 0.0,
	});
	const placed = placeLabel(index, trs2d(x, 20.0, 0.0, 1.0, 1.0), dpi);
	for (const p of placed.placed) {
		if (p.page != NO_GLYPH_PAGE) { pageOrder.push(p.page as int32); }
	}
}

function switches(planesPerTexture: int32): int32 {
	let count: int32 = 0;
	let last: int32 = -1;
	for (const page of pageOrder) {
		const texture: int32 = Math.floor((page as float32) / (planesPerTexture as float32)) as int32;
		if (last >= 0 && texture != last) { count = count + 1; }
		last = texture;
	}
	return count;
}

function workload(sizes: float32[], dpis: float32[]): void {
	for (const dpi of dpis) {
		for (const size of sizes) {
			for (let line: int32 = 0; line < 4; line++) {
				place(CODE, size, dpi, 0.25 * (line as float32));
				place(PROSE, size, dpi, 0.5 * (line as float32));
			}
		}
		for (const size of ICON_SIZES) {
			place(ICONS, size, dpi, 0.0);
			place(ICONS, size, dpi, 0.5);
		}
	}
}

function report(name: string): void {
	const planes: int32 = glyphAtlas.pageCount();
	const rgbaPages: int32 = Math.ceil((planes as float32) / 4.0) as int32;
	console.log(`PAGES ${name} glyphs ${pageOrder.length} tiles ${glyphAtlas.tileSlots()} rasterizations ${glyphRasterizations()}`);
	console.log(`PAGES ${name} r8 pages ${planes} bytes ${planes * R8_PAGE_BYTES} switches ${switches(1)} upload-per-new-glyph ${R8_PAGE_BYTES}`);
	console.log(`PAGES ${name} fourPlane pages ${rgbaPages} bytes ${rgbaPages * RGBA_PAGE_BYTES} switches ${switches(4)} upload-per-new-glyph ${RGBA_PAGE_BYTES}`);
}

function run(): void {
	workload(SIZES, DPIS);
	report("workload");
	workload(STRESS_SIZES, STRESS_DPIS);
	report("stress");
}

run();
