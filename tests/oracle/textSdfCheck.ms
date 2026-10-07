import { env } from "std/process";
import {
	SdfLabelCase, sdfLabelCases, SDF_ROTATED_SCENE, SDF_ZOOM_SCENE, SDF_SCALE_DOWN_SCENE,
	SDF_TEXT_R, SDF_TEXT_G, SDF_TEXT_B, SDF_BG_X, SDF_BG_Y,
} from "../golden/table";
import { coverageFromPixel } from "./coverage";
import {
	allocateLabelText, releaseLabelText, shapeLabel, labelTexts,
} from "../../src/void2d/labelText";
import { Align, NO_GLYPH } from "../../src/void2d/textLayout";
import { DEFAULT_FONT } from "../../src/void2d/font";
import {
	void2dGlyphBox, void2dGlyphRasterize, void2dGlyphPageCreate, void2dGlyphPageTexel,
} from "../../src/void2d/glyph.h";
import {
	DEFAULT_TEXT_GAMMA, DEFAULT_TEXT_CONTRAST, gammaRatios, correctCoverage,
} from "../../src/void2d/textGamma";
import { voidPngLoad, voidPngWidth, voidPngHeight, voidPngPixel } from "../golden/pngio.h";

const SLOT: int32 = 0;
const SUPERSAMPLE: int32 = 4;
const REGION_MARGIN: int32 = 3;

const MAE_BOUND: float32 = 0.075;
const P99_BOUND: float32 = 0.40;
const INK_LOW: float32 = 0.94;
const INK_HIGH: float32 = 1.07;
const MIN_PIXELS: int32 = 300;

struct Measure {
	mae: float32;
	p99: float32;
	ink: float32;
	pixels: int32;
}

let referencePage: int32 = -1;

interface Canvas {
	width: int32;
	height: int32;
	values: Vec<float32>;
}

function page(): int32 {
	if (referencePage < 0) { referencePage = void2dGlyphPageCreate(1024, 0); }
	return referencePage;
}

function isTransformed(c: SdfLabelCase): boolean {
	return c.rotation != 0.0 || c.zoom != 1.0;
}

function capturePath(scene: string): string {
	const dir: string = env.get("VOID_TEXT_SDF_CAPTURE_DIR");
	return dir.equals("") ? `tests/golden/d3d11/${scene}.png` : `${dir}/${scene}.png`;
}

function shaped(c: SdfLabelCase): int32 {
	const index: int32 = allocateLabelText();
	shapeLabel(index, c.text, {
		font: DEFAULT_FONT, size: c.size, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0,
		align: Align.Left,
	});
	return index;
}

function paintCase(c: SdfLabelCase, canvas: Canvas): void {
	const width: int32 = canvas.width;
	const height: int32 = canvas.height;
	const index: int32 = shaped(c);
	const entry = labelTexts[index];
	const cs: float32 = Math.cos(c.rotation as float64) as float32;
	const sn: float32 = Math.sin(c.rotation as float64) as float32;
	const fine: float32 = SUPERSAMPLE as float32;
	const step: float32 = 1.0 / fine;
	for (const g of entry.layout.glyphs) {
		if (g.glyph == NO_GLYPH) { continue; }
		const baseline: float32 = entry.layout.lines[g.line].baseline;
		const refSize: float32 = g.size * c.zoom * fine;
		const box: Ptr<int32> = void2dGlyphBox(g.face, g.glyph, refSize, 0.0);
		const refLeft: int32 = box[0];
		const refTop: int32 = box[1];
		const refW: int32 = box[2] - box[0];
		const refH: int32 = box[3] - box[1];
		if (refW <= 0 || refH <= 0) { continue; }
		void2dGlyphRasterize(g.face, g.glyph, refSize, 0.0, page(), 0, 0, refW, refH);
		const perLocal: float32 = c.zoom * fine;
		let minX: float32 = 1.0e9;
		let maxX: float32 = -1.0e9;
		let minY: float32 = 1.0e9;
		let maxY: float32 = -1.0e9;
		for (const lx of [box[0] as float32, box[2] as float32]) {
			for (const ly of [box[1] as float32, box[3] as float32]) {
				const gx: float32 = (g.x + lx / perLocal) * c.zoom;
				const gy: float32 = (baseline + ly / perLocal) * c.zoom;
				const dx: float32 = c.x + cs * gx - sn * gy;
				const dy: float32 = c.y + sn * gx + cs * gy;
				if (dx < minX) { minX = dx; }
				if (dx > maxX) { maxX = dx; }
				if (dy < minY) { minY = dy; }
				if (dy > maxY) { maxY = dy; }
			}
		}
		const i0: int32 = Math.max(0, (Math.floor(minX) as int32) - 1);
		const i1: int32 = Math.min(width, (Math.ceil(maxX) as int32) + 1);
		const j0: int32 = Math.max(0, (Math.floor(minY) as int32) - 1);
		const j1: int32 = Math.min(height, (Math.ceil(maxY) as int32) + 1);
		for (let j = j0; j < j1; j++) {
			for (let i = i0; i < i1; i++) {
				let total: float32 = 0.0;
				for (let b = 0; b < SUPERSAMPLE; b++) {
					for (let a = 0; a < SUPERSAMPLE; a++) {
						const sx: float32 = (i as float32) + ((a as float32) + 0.5) * step - c.x;
						const sy: float32 = (j as float32) + ((b as float32) + 0.5) * step - c.y;
						const u: float32 = cs * sx + sn * sy;
						const v: float32 = cs * sy - sn * sx;
						const hx: float32 = (u - g.x * c.zoom) * fine;
						const hy: float32 = (v - baseline * c.zoom) * fine;
						const col: int32 = (Math.floor(hx) as int32) - refLeft;
						const row: int32 = (Math.floor(hy) as int32) - refTop;
						if (col >= 0 && row >= 0 && col < refW && row < refH) {
							const texel: int32 = void2dGlyphPageTexel(page(), col, row);
							total = total + (texel as float32) / 255.0;
						}
					}
				}
				const at: int32 = j * width + i;
				const sum: float32 = canvas.values[at] + total * step * step;
				canvas.values[at] = Math.min(1.0, sum) as float32;
			}
		}
	}
	releaseLabelText(index);
}

function regionOf(c: SdfLabelCase, width: int32, height: int32): [int32, int32, int32, int32] {
	const index: int32 = shaped(c);
	const entry = labelTexts[index];
	const cs: float32 = Math.cos(c.rotation as float64) as float32;
	const sn: float32 = Math.sin(c.rotation as float64) as float32;
	const last = entry.layout.glyphs[(entry.layout.glyphs.length as int32) - 1];
	const right: float32 = (last.x + last.advance) * c.zoom;
	const bottom: float32 = (entry.layout.lines[0].baseline + c.size * 0.4) * c.zoom;
	const top: float32 = -c.size * 0.3 * c.zoom;
	let minX: float32 = 1.0e9;
	let maxX: float32 = -1.0e9;
	let minY: float32 = 1.0e9;
	let maxY: float32 = -1.0e9;
	for (const gx of [0.0 as float32, right]) {
		for (const gy of [top, bottom]) {
			const dx: float32 = c.x + cs * gx - sn * gy;
			const dy: float32 = c.y + sn * gx + cs * gy;
			if (dx < minX) { minX = dx; }
			if (dx > maxX) { maxX = dx; }
			if (dy < minY) { minY = dy; }
			if (dy > maxY) { maxY = dy; }
		}
	}
	releaseLabelText(index);
	return [
		Math.max(0, (Math.floor(minX) as int32) - REGION_MARGIN),
		Math.max(0, (Math.floor(minY) as int32) - REGION_MARGIN),
		Math.min(width, (Math.ceil(maxX) as int32) + REGION_MARGIN),
		Math.min(height, (Math.ceil(maxY) as int32) + REGION_MARGIN),
	];
}

function measureRegion(
	region: [int32, int32, int32, int32], canvas: Canvas,
): Measure {
	const width: int32 = canvas.width;
	const fillR: int32 = Math.floor(SDF_TEXT_R * 255.0 + 0.5) as int32;
	const fillG: int32 = Math.floor(SDF_TEXT_G * 255.0 + 0.5) as int32;
	const fillB: int32 = Math.floor(SDF_TEXT_B * 255.0 + 0.5) as int32;
	const bgR: int32 = voidPngPixel(SLOT, SDF_BG_X, SDF_BG_Y, 0);
	const bgG: int32 = voidPngPixel(SLOT, SDF_BG_X, SDF_BG_Y, 1);
	const bgB: int32 = voidPngPixel(SLOT, SDF_BG_X, SDF_BG_Y, 2);
	const ratios = gammaRatios(DEFAULT_TEXT_GAMMA);
	let histogram: Vec<int32> = new Array(256);
	for (let b = 0; b < 256; b++) { histogram[b] = 0; }
	let sumError: float32 = 0.0;
	let counted: int32 = 0;
	let gotInk: float32 = 0.0;
	let wantInk: float32 = 0.0;
	for (let j = region[1]; j < region[3]; j++) {
		for (let i = region[0]; i < region[2]; i++) {
			const expected: float32 = correctCoverage(
				canvas.values[j * width + i], SDF_TEXT_R, SDF_TEXT_G, SDF_TEXT_B,
				DEFAULT_TEXT_CONTRAST, ratios,
			);
			const observed: float32 = coverageFromPixel(
				voidPngPixel(SLOT, i, j, 0), voidPngPixel(SLOT, i, j, 1),
				voidPngPixel(SLOT, i, j, 2), bgR, bgG, bgB, fillR, fillG, fillB,
			);
			gotInk = gotInk + observed;
			wantInk = wantInk + expected;
			if (observed < 0.004 && expected < 0.004) { continue; }
			const delta: float32 = observed - expected;
			const error: float32 = delta < 0.0 ? -delta : delta;
			sumError = sumError + error;
			counted = counted + 1;
			const bin: int32 = Math.min(255, Math.floor(error * 255.0 + 0.5) as int32);
			histogram[bin] = histogram[bin] + 1;
		}
	}
	let seen: int32 = 0;
	let p99: float32 = 1.0;
	for (let b = 0; b < 256; b++) {
		seen = seen + histogram[b];
		if ((seen as float32) >= (counted as float32) * 0.99) {
			p99 = (b as float32) / 255.0;
			break;
		}
	}
	return {
		mae: counted > 0 ? sumError / (counted as float32) : 1.0,
		p99: p99,
		ink: wantInk > 0.0 ? gotInk / wantInk : 0.0,
		pixels: counted,
	};
}

function judgeScene(scene: string): int32 {
	const path: string = capturePath(scene);
	if (voidPngLoad(SLOT, path) == 0) {
		console.log(`FAIL text sdf oracle ${scene}: cannot read ${path}`);
		return 1;
	}
	const width: int32 = voidPngWidth(SLOT);
	const height: int32 = voidPngHeight(SLOT);
	let values: Vec<float32> = new Array(width * height);
	for (let k = 0; k < width * height; k++) { values[k] = 0.0; }
	const canvas: Canvas = { width: width, height: height, values: values };
	for (const c of sdfLabelCases()) {
		if (c.scene == scene) { paintCase(c, canvas); }
	}
	let failed: int32 = 0;
	for (const c of sdfLabelCases()) {
		if (c.scene != scene || !isTransformed(c)) { continue; }
		const m = measureRegion(regionOf(c, width, height), canvas);
		console.log(
			`text sdf oracle: ${scene} "${c.text}" size ${c.size} zoom ${c.zoom} ` +
			`rot ${c.rotation}: mae ${m.mae} p99 ${m.p99} ink ${m.ink} px ${m.pixels}`,
		);
		if (m.pixels < MIN_PIXELS) {
			console.log(`FAIL text sdf oracle ${scene}: ${m.pixels} pixels, too few to convict`);
			failed = failed + 1;
		} else if (m.mae > MAE_BOUND || m.p99 > P99_BOUND || m.ink < INK_LOW || m.ink > INK_HIGH) {
			console.log(
				`FAIL text sdf oracle ${scene} "${c.text}": mae ${m.mae} of ${MAE_BOUND}, ` +
				`p99 ${m.p99} of ${P99_BOUND}, ink ${m.ink} of ${INK_LOW}..${INK_HIGH}`,
			);
			failed = failed + 1;
		}
	}
	return failed;
}

function run(): int32 {
	const failed: int32 = judgeScene(SDF_ROTATED_SCENE) + judgeScene(SDF_ZOOM_SCENE) +
		judgeScene(SDF_SCALE_DOWN_SCENE);
	if (failed == 0) {
		console.log(
			`PASS text sdf oracle: the captures read as true coverage within mae ${MAE_BOUND}, ` +
			`p99 ${P99_BOUND}, ink ${INK_LOW}..${INK_HIGH}`,
		);
	}
	return failed == 0 ? 0 : 1;
}

process.exit(run());
