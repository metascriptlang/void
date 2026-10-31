import { env } from "std/process";
import { readFile, readFileBytes } from "std/fs";
import { sha256, toHex } from "std/crypto/sha256";
import { JsonValue, JsonKind } from "std/serialize/json/types";
import {
	SdfLabelCase, outlineSdfLabelCases, sceneRows, OUTLINE_SDF_WIDTH,
	OUTLINE_INK_R, OUTLINE_INK_G, OUTLINE_INK_B, OUTLINE_BG_R, OUTLINE_BG_G, OUTLINE_BG_B,
	OUTLINE_SDF_ROTATED_SCENE, OUTLINE_SDF_ZOOM_SCENE, OUTLINE_SDF_SCALE_DOWN_SCENE,
	OUTLINE_SDF_SEAM_SCENE, SDF_TEXT_R, SDF_TEXT_G, SDF_TEXT_B,
} from "../golden/table";
import {
	allocateLabelText, releaseLabelText, shapeLabel, labelTexts, regimeOf, TextRegime,
	setSdfRegime,
} from "../../src/void2d/labelText";
import { DEFAULT_FONT, fontFace } from "../../src/void2d/font";
import { Align, NO_GLYPH } from "../../src/void2d/textLayout";
import { quantizeX, snapBaseline } from "../../src/void2d/glyphAtlas";
import { deviceOutlineWidth } from "../../src/void2d/textOutline";
import { Transform2D, Color } from "../../src/void2d/types";
import {
	gammaRatios, correctCoverage, DEFAULT_TEXT_GAMMA, DEFAULT_TEXT_CONTRAST,
} from "../../src/void2d/textGamma";
import { voidPngLoad, voidPngWidth, voidPngHeight, voidPngPixel } from "../golden/pngio.h";

const FONT_PATH: string = "assets/font.ttf";
const REFERENCE_SAMPLES: int32 = 4;
const PILLOW_SAMPLES: int32 = 8;
const ORACLE_PATH: string = "tests/oracle/outlineCapture.json";
const BASE64: string = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const MAE_BOUND: float32 = 0.075;
const P99_BOUND: float32 = 0.40;
const INK_LOW: float32 = 0.94;
const INK_HIGH: float32 = 1.07;
const MIN_PIXELS: int32 = 300;
const MIN_OUTLINE_PIXELS: int32 = 16;
const OUTLINE_DELTA: float32 = 8.0 / 255.0;
const REGION_MARGIN: int32 = 3;
const FILL: Color = { r: SDF_TEXT_R, g: SDF_TEXT_G, b: SDF_TEXT_B, a: 1.0 };
const INK: Color = { r: OUTLINE_INK_R, g: OUTLINE_INK_G, b: OUTLINE_INK_B, a: 1.0 };

struct MaskRequest {
	key: string;
	codepoint: int32;
	glyph: int32;
	size: float32;
	variant: int32;
	width: float32;
}

struct ReferenceGlyph {
	x: float32;
	y: float32;
	fill: int32;
	outline: int32;
}

struct ReferenceLabel {
	spec: SdfLabelCase;
	exact: boolean;
	glyphs: ReferenceGlyph[];
}

struct Mask {
	left: int32;
	top: int32;
	width: int32;
	height: int32;
	data: Vec<uint8>;
}

interface Canvas {
	width: int32;
	height: int32;
	data: Vec<float32>;
}

struct Measure {
	mae: float32;
	p99: float32;
	ink: float32;
	pixels: int32;
	outlinePixels: int32;
}

let requests: MaskRequest[] = [];
let labels: ReferenceLabel[] = [];
let masks: Mask[] = [];

function require(ok: boolean, message: string): void {
	if (!ok) {
		console.log(`FAIL outline capture oracle: ${message}`);
		process.exit(1);
	}
}

function fontDigest(): string {
	const file = readFileBytes(FONT_PATH);
	if (file.ok) { return sha256(file.value).toHex(); }
	console.log(`FAIL outline capture oracle: cannot read ${FONT_PATH}`);
	unreachable;
}

function requestMask(
	codepoint: int32, glyph: int32, size: float32, variant: int32, width: float32,
): int32 {
	const key: string = `${codepoint}|${glyph}|${size}|${variant}|${width}`;
	for (let i: int32 = 0; i < (requests.length as int32); i++) {
		if (requests[i].key == key) { return i; }
	}
	const index: int32 = requests.length as int32;
	requests.push({ key, codepoint, glyph, size, variant, width });
	return index;
}

function buildPlan(): void {
	const face: int32 = fontFace(DEFAULT_FONT);
	require(face >= 0, "default face did not load");
	setSdfRegime(true);
	for (const c of outlineSdfLabelCases()) {
		const cs: float32 = Math.cos(c.rotation as float64) as float32;
		const sn: float32 = Math.sin(c.rotation as float64) as float32;
		const world: Transform2D = {
			a: cs * c.zoom, b: sn * c.zoom, c: -sn * c.zoom, d: cs * c.zoom,
			tx: c.x, ty: c.y,
		};
		const exact: boolean = regimeOf(world) == TextRegime.PixelExact;
		const fine: float32 = exact ? 1.0 : REFERENCE_SAMPLES as float32;
		const index: int32 = allocateLabelText();
		shapeLabel(index, c.text, {
			font: DEFAULT_FONT, size: c.size, letterSpacing: 0.0, lineSpacing: 0.0,
			maxWidth: 0.0, align: Align.Left,
		});
		const text = labelTexts[index];
		let glyphs: ReferenceGlyph[] = [];
		for (const g of text.layout.glyphs) {
			if (g.glyph == NO_GLYPH) { continue; }
			require(g.face == face, `${c.scene} has an unexpected face for U+${g.codepoint}`);
			let x: float32 = g.x + g.offsetX;
			let y: float32 = text.layout.lines[g.line].baseline + g.offsetY;
			let variant: int32 = 0;
			if (exact) {
				const left: float32 = Math.floor(c.x) as float32;
				const top: float32 = Math.floor(c.y) as float32;
				const q = quantizeX(c.x - left + x * c.zoom);
				variant = q.variant;
				x = left + (q.whole as float32);
				y = top + (snapBaseline(c.y - top + y * c.zoom) as float32);
			}
			const size: float32 = g.size * c.zoom * fine;
			const width: float32 = deviceOutlineWidth(OUTLINE_SDF_WIDTH, c.zoom, exact) * fine;
			glyphs.push({
				x, y,
				fill: requestMask(g.codepoint, g.glyph, size, variant, 0.0),
				outline: requestMask(g.codepoint, g.glyph, size, variant, width),
			});
		}
		labels.push({ spec: c, exact, glyphs });
		releaseLabelText(index);
	}
	require((labels.length as int32) == 11, "expected eleven existing label cases");
}

function exportRequests(): void {
	console.log(`FONT|${fontDigest()}|${PILLOW_SAMPLES}`);
	for (const r of requests) { console.log(`MASK|${r.key}`); }
}

function readReference(): JsonValue {
	const override: string = env.get("VOID_OUTLINE_REFERENCE");
	const path: string = override == "" ? ORACLE_PATH : override;
	const file = readFile(path);
	if (file.ok) {
		const parsed = JSON.parseValue(file.value);
		if (parsed.ok) { return parsed.value; }
	}
	console.log(`FAIL outline capture oracle: unreadable reference ${path}`);
	unreachable;
}

function stringField(row: JsonValue, name: string): string {
	require(row != null && row.kind == JsonKind.Object, `invalid object for ${name}`);
	const value = row.getDynamicField(name);
	require(value != null && value.kind == JsonKind.String, `invalid string field ${name}`);
	return value.asString();
}

function integerField(row: JsonValue, name: string, low: int32, high: int32): int32 {
	require(row != null && row.kind == JsonKind.Object, `invalid object for ${name}`);
	const value = row.getDynamicField(name);
	require(value != null && (value.kind == JsonKind.Int || value.kind == JsonKind.Number),
		`invalid numeric field ${name}`);
	const numberValue: float64 = value.asNumber();
	require(numberValue >= low && numberValue <= high && numberValue == Math.floor(numberValue),
		`out-of-range integer field ${name}`);
	return numberValue as int32;
}

function decode(text: string, size: int32, key: string): Vec<uint8> {
	const encoded: int32 = ((size + 2) / 3) * 4;
	require((text.length as int32) == encoded, `mask ${key} has an invalid base64 length`);
	let data: Vec<uint8> = [];
	let held: uint32 = 0;
	let bits: uint32 = 0;
	let padding: int32 = 0;
	for (let i: int32 = 0; i < (text.length as int32); i++) {
		const ch: string = text.charAt(i);
		if (ch == "=") { padding++; continue; }
		const value: int32 = BASE64.indexOf(ch) as int32;
		require(padding == 0 && value >= 0, `mask ${key} has invalid base64`);
		held = (held << 6) | (value as uint32);
		bits += 6;
		if (bits >= 8) {
			bits -= 8;
			data.push(((held >> bits) & 255) as uint8);
		}
	}
	require((data.length as int32) == size &&
		((bits == 0 && padding == 0) || (bits == 2 && padding == 1) ||
		(bits == 4 && padding == 2)), `mask ${key} has an invalid decoded size or padding`);
	return data;
}

function loadMasks(): void {
	const root = readReference();
	require(root != null && root.kind == JsonKind.Object, "reference is not an object");
	require(integerField(root, "format", 1, 1) == 1, "unknown reference format");
	require(integerField(root, "supersample", PILLOW_SAMPLES, PILLOW_SAMPLES) == PILLOW_SAMPLES,
		"reference supersampling differs");
	require(stringField(root, "fontSha256") == fontDigest(), "reference font digest differs");
	const rows = root.getDynamicField("masks");
	require(rows != null && rows.kind == JsonKind.Array, "reference masks are not an array");
	require(rows.length() == (requests.length as int32), "reference mask set is stale");
	for (const r of requests) {
		let found: int32 = 0;
		for (let i: int32 = 0; i < (rows.length() as int32); i++) {
			const row = rows.at(i);
			if (stringField(row, "key") != r.key) { continue; }
			found++;
			const width: int32 = integerField(row, "w", 0, 1024);
			const height: int32 = integerField(row, "h", 0, 1024);
			require((width == 0) == (height == 0), `mask ${r.key} has one empty dimension`);
			require(width > 0 || r.codepoint == 32, `mask ${r.key} drops a non-space glyph`);
			masks.push({
				left: integerField(row, "left", -2048, 2048),
				top: integerField(row, "top", -2048, 2048), width, height,
				data: decode(stringField(row, "data"), width * height, r.key),
			});
		}
		require(found == 1, `mask request ${r.key} is missing or duplicated`);
	}
}

function dimensions(scene: string): [int32, int32] {
	for (const row of sceneRows()) {
		if (row.name == scene) {
			require(row.dpi == 1.0, `capture reference does not support DPI ${row.dpi}: ${scene}`);
			return [row.width, row.height];
		}
	}
	console.log(`FAIL outline capture oracle: unknown scene ${scene}`);
	unreachable;
}

function background(): float32[] {
	let values: float32[] = [];
	for (const value of [OUTLINE_BG_R, OUTLINE_BG_G, OUTLINE_BG_B]) {
		values.push((Math.floor(value * 255.0 + 0.5) as float32) / 255.0);
	}
	return values;
}

function canvasFor(scene: string): Canvas {
	const [width, height] = dimensions(scene);
	const bg = background();
	let data: Vec<float32> = new Array(width * height * 3);
	for (let i: int32 = 0; i < width * height * 3; i++) { data[i] = bg[i % 3]; }
	return { width, height, data };
}

function bounds(label: ReferenceLabel, g: ReferenceGlyph, mask: Mask): float32[] {
	if (label.exact) {
		return [g.x + (mask.left as float32), g.y + (mask.top as float32),
			g.x + ((mask.left + mask.width) as float32),
			g.y + ((mask.top + mask.height) as float32)];
	}
	const c = label.spec;
	const cs: float32 = Math.cos(c.rotation as float64) as float32;
	const sn: float32 = Math.sin(c.rotation as float64) as float32;
	let minX: float32 = 1.0e9;
	let minY: float32 = 1.0e9;
	let maxX: float32 = -1.0e9;
	let maxY: float32 = -1.0e9;
	for (const x of [mask.left, mask.left + mask.width]) {
		for (const y of [mask.top, mask.top + mask.height]) {
			const gx: float32 = g.x * c.zoom + (x as float32) / (REFERENCE_SAMPLES as float32);
			const gy: float32 = g.y * c.zoom + (y as float32) / (REFERENCE_SAMPLES as float32);
			const dx: float32 = c.x + cs * gx - sn * gy;
			const dy: float32 = c.y + sn * gx + cs * gy;
			if (dx < minX) { minX = dx; }
			if (dx > maxX) { maxX = dx; }
			if (dy < minY) { minY = dy; }
			if (dy > maxY) { maxY = dy; }
		}
	}
	return [minX, minY, maxX, maxY];
}

function paintGlyph(
	label: ReferenceLabel, g: ReferenceGlyph, mask: Mask, target: Canvas,
	ink: Color, gammaInk: Color,
): void {
	if (mask.width == 0 || mask.height == 0) { return; }
	const box = bounds(label, g, mask);
	const i0: int32 = Math.max(0, Math.floor(box[0]) as int32);
	const j0: int32 = Math.max(0, Math.floor(box[1]) as int32);
	const i1: int32 = Math.min(target.width, Math.ceil(box[2]) as int32);
	const j1: int32 = Math.min(target.height, Math.ceil(box[3]) as int32);
	const c = label.spec;
	const cs: float32 = Math.cos(c.rotation as float64) as float32;
	const sn: float32 = Math.sin(c.rotation as float64) as float32;
	const n: int32 = label.exact ? 1 : REFERENCE_SAMPLES;
	const step: float32 = 1.0 / (n as float32);
	const ratios = gammaRatios(DEFAULT_TEXT_GAMMA);
	for (let j: int32 = j0; j < j1; j++) {
		for (let i: int32 = i0; i < i1; i++) {
			let total: float32 = 0.0;
			for (let b: int32 = 0; b < n; b++) {
				for (let a: int32 = 0; a < n; a++) {
					let col: int32 = i - (g.x as int32) - mask.left;
					let row: int32 = j - (g.y as int32) - mask.top;
					if (!label.exact) {
						const px: float32 = (i as float32) + ((a as float32) + 0.5) * step - c.x;
						const py: float32 = (j as float32) + ((b as float32) + 0.5) * step - c.y;
						const u: float32 = cs * px + sn * py;
						const v: float32 = cs * py - sn * px;
						const hx: float32 = (u - g.x * c.zoom) * (n as float32);
						const hy: float32 = (v - g.y * c.zoom) * (n as float32);
						col = (Math.floor(hx) as int32) - mask.left;
						row = (Math.floor(hy) as int32) - mask.top;
					}
					if (col >= 0 && row >= 0 && col < mask.width && row < mask.height) {
						total += (mask.data[row * mask.width + col] as float32) / 255.0;
					}
				}
			}
			const alpha: float32 = correctCoverage(total * step * step,
				gammaInk.r, gammaInk.g, gammaInk.b, DEFAULT_TEXT_CONTRAST, ratios);
			const at: int32 = (j * target.width + i) * 3;
			target.data[at] = ink.r * alpha + target.data[at] * (1.0 - alpha);
			target.data[at + 1] = ink.g * alpha + target.data[at + 1] * (1.0 - alpha);
			target.data[at + 2] = ink.b * alpha + target.data[at + 2] * (1.0 - alpha);
		}
	}
}

function reference(scene: string, control: int32): Canvas {
	const target = canvasFor(scene);
	for (const label of labels) {
		if (label.spec.scene != scene) { continue; }
		if (control == 3) {
			for (const g of label.glyphs) {
				paintGlyph(label, g, masks[g.outline], target, INK, INK);
				paintGlyph(label, g, masks[g.fill], target, FILL, FILL);
			}
			continue;
		}
		if (control != 1) {
			for (const g of label.glyphs) {
				const gammaInk: Color = control == 2 ? FILL : INK;
				const shifted: ReferenceGlyph = control == 4
					? { ...g, x: g.x + (label.exact ? 2.0 : 2.0 / label.spec.zoom) } : g;
				paintGlyph(label, shifted, masks[g.outline], target, INK, gammaInk);
			}
		}
		for (const g of label.glyphs) {
			paintGlyph(label, g, masks[g.fill], target, FILL, FILL);
		}
	}
	return target;
}

function region(label: ReferenceLabel, target: Canvas): int32[] {
	let x0: float32 = 1.0e9;
	let y0: float32 = 1.0e9;
	let x1: float32 = -1.0e9;
	let y1: float32 = -1.0e9;
	for (const g of label.glyphs) {
		const mask = masks[g.outline];
		if (mask.width == 0) { continue; }
		const box = bounds(label, g, mask);
		if (box[0] < x0) { x0 = box[0]; }
		if (box[1] < y0) { y0 = box[1]; }
		if (box[2] > x1) { x1 = box[2]; }
		if (box[3] > y1) { y1 = box[3]; }
	}
	return [Math.max(0, (Math.floor(x0) as int32) - REGION_MARGIN),
		Math.max(0, (Math.floor(y0) as int32) - REGION_MARGIN),
		Math.min(target.width, (Math.ceil(x1) as int32) + REGION_MARGIN),
		Math.min(target.height, (Math.ceil(y1) as int32) + REGION_MARGIN)];
}

function measure(label: ReferenceLabel, observed: Canvas, wanted: Canvas, plain: Canvas): Measure {
	const roi = region(label, wanted);
	const bg = background();
	let histogram: Vec<int32> = new Array(256);
	for (let i: int32 = 0; i < 256; i++) { histogram[i] = 0; }
	let errors: float32 = 0.0;
	let gotInk: float32 = 0.0;
	let wantInk: float32 = 0.0;
	let counted: int32 = 0;
	let sensitive: int32 = 0;
	for (let j: int32 = roi[1]; j < roi[3]; j++) {
		for (let i: int32 = roi[0]; i < roi[2]; i++) {
			const at: int32 = (j * wanted.width + i) * 3;
			let got: float32 = 0.0;
			let want: float32 = 0.0;
			let error: float32 = 0.0;
			let maximum: float32 = 0.0;
			let stroke: float32 = 0.0;
			for (let lane: int32 = 0; lane < 3; lane++) {
				const a: float32 = observed.data[at + lane] - bg[lane];
				const b: float32 = wanted.data[at + lane] - bg[lane];
				const delta: float32 = observed.data[at + lane] - wanted.data[at + lane];
				const outlineDelta: float32 = wanted.data[at + lane] - plain.data[at + lane];
				const off: float32 = delta < 0.0 ? -delta : delta;
				const effect: float32 = outlineDelta < 0.0 ? -outlineDelta : outlineDelta;
				got += a < 0.0 ? -a : a;
				want += b < 0.0 ? -b : b;
				error += off;
				if (off > maximum) { maximum = off; }
				if (effect > stroke) { stroke = effect; }
			}
			if (stroke >= OUTLINE_DELTA) { sensitive++; }
			gotInk += got;
			wantInk += want;
			if (got < 0.004 && want < 0.004) { continue; }
			errors += error;
			counted++;
			const bin: int32 = Math.min(255, Math.floor(maximum * 255.0 + 0.5) as int32);
			histogram[bin]++;
		}
	}
	let seen: int32 = 0;
	let p99: float32 = 1.0;
	for (let i: int32 = 0; i < 256; i++) {
		seen += histogram[i];
		if ((seen as float32) >= (counted as float32) * 0.99) {
			p99 = (i as float32) / 255.0;
			break;
		}
	}
	return { mae: counted > 0 ? errors / ((counted * 3) as float32) : 1.0,
		p99, ink: wantInk > 0.0 ? gotInk / wantInk : 0.0,
		pixels: counted, outlinePixels: sensitive };
}

function accepted(m: Measure): boolean {
	return m.pixels >= MIN_PIXELS && m.outlinePixels >= MIN_OUTLINE_PIXELS &&
		m.mae <= MAE_BOUND && m.p99 <= P99_BOUND && m.ink >= INK_LOW && m.ink <= INK_HIGH;
}

function observed(scene: string): Canvas {
	const directory: string = env.get("VOID_OUTLINE_CAPTURE_DIR");
	const path: string = directory == "" ? `tests/golden/d3d11/${scene}.png`
		: `${directory}/${scene}.png`;
	const target = canvasFor(scene);
	require(voidPngLoad(0, path) != 0, `cannot read capture ${path}`);
	require(voidPngWidth(0) == target.width && voidPngHeight(0) == target.height,
		`capture ${scene} has wrong dimensions`);
	const bg = background();
	for (let lane: int32 = 0; lane < 3; lane++) {
		require(voidPngPixel(0, 2, 2, lane) == (Math.floor(bg[lane] * 255.0 + 0.5) as int32),
			`capture ${scene} has a different background`);
	}
	for (let j: int32 = 0; j < target.height; j++) {
		for (let i: int32 = 0; i < target.width; i++) {
			for (let lane: int32 = 0; lane < 3; lane++) {
				target.data[(j * target.width + i) * 3 + lane] =
					(voidPngPixel(0, i, j, lane) as float32) / 255.0;
			}
		}
	}
	return target;
}

function run(selfTest: boolean): void {
	let judged: int32 = 0;
	for (const scene of [OUTLINE_SDF_ROTATED_SCENE, OUTLINE_SDF_ZOOM_SCENE,
		OUTLINE_SDF_SCALE_DOWN_SCENE, OUTLINE_SDF_SEAM_SCENE]) {
		const wanted = reference(scene, 0);
		const plain = reference(scene, 1);
		const got = selfTest ? wanted : observed(scene);
		const blank = selfTest ? canvasFor(scene) : got;
		const wrongGamma = selfTest ? reference(scene, 2) : got;
		const interleaved = selfTest ? reference(scene, 3) : got;
		const displaced = selfTest ? reference(scene, 4) : got;
		let gammaRefused: int32 = 0;
		let orderRefused: int32 = 0;
		let displacementRefused: int32 = 0;
		for (const label of labels) {
			if (label.spec.scene != scene) { continue; }
			const m = measure(label, got, wanted, plain);
			console.log(`outline capture oracle: ${scene} "${label.spec.text}" ` +
				`zoom ${label.spec.zoom} mae ${m.mae} p99 ${m.p99} ink ${m.ink} ` +
				`px ${m.pixels} outlinePx ${m.outlinePixels}`);
			require(accepted(m), `${scene} "${label.spec.text}" exceeds RGB/ink/support bounds`);
			if (selfTest) {
				require(!accepted(measure(label, blank, wanted, plain)), `${scene} accepts blank`);
				require(!accepted(measure(label, plain, wanted, plain)),
					`${scene} accepts fill only`);
				if (!accepted(measure(label, wrongGamma, wanted, plain))) { gammaRefused++; }
				if (!accepted(measure(label, interleaved, wanted, plain))) { orderRefused++; }
				if (!accepted(measure(label, displaced, wanted, plain))) { displacementRefused++; }
			}
			judged++;
		}
		if (selfTest) {
			console.log(`outline capture controls: ${scene} gammaRefused ${gammaRefused} ` +
				`orderRefused ${orderRefused} displacementRefused ${displacementRefused}; ` +
				`zero means this scene does not convict that mutant`);
		}
	}
	require(judged == 11, `judged ${judged} labels instead of eleven`);
	console.log(selfTest ? "PASS outline capture reference self/blank/fill-only controls: 11 cases"
		: "PASS outline capture oracle: 11 captured labels within declared Pillow RGB bounds");
}

buildPlan();
if (env.get("VOID_OUTLINE_REQUESTS") == "1") {
	exportRequests();
} else {
	loadMasks();
	run(env.get("VOID_OUTLINE_SELFTEST") == "1");
}
