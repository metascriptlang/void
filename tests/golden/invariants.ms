import "../../src/sokol/gpu";
import { env } from "std/process";
import {
	FILTERED_TEXT_SCENE,
	FILTERED_TEXT_DPI,
	FILTERED_TEXT_X,
	FILTERED_TEXT_Y,
	FILTERED_TEXT_SHIFT,
	FILTERED_TEXT_W,
	FILTERED_TEXT_H,
	CARET_SCENE,
	CARET_TEXT,
	CARET_SIZE,
	CARET_X,
	CARET_Y,
	CARET_DPI,
	CARET_SELECTION_START,
	CARET_SELECTION_LENGTH,
	CARET_SELECTION_R,
	CARET_SELECTION_G,
	CARET_SELECTION_B,
	CARET_SELECTION_A,
	LANES_SCENE,
	LANES_X,
	LANES_Y,
	LANES_W,
	LANES_H,
	LANES_SHIFT,
	PREMULTIPLIED_EFFECT_SCENE,
	PREMULTIPLIED_STYLE_SCENE,
	PREMULTIPLIED_X,
	PREMULTIPLIED_Y,
	PREMULTIPLIED_SIZE,
	PREMULTIPLIED_SHIFT,
	PREMULTIPLIED_ROW_STEP,
	MANY_TARGETS_SCENE,
	MANY_TARGETS_COUNT,
	MANY_TARGETS_COLUMNS,
	MANY_TARGETS_STEP,
	MANY_TARGETS_ORIGIN,
	MANY_TARGETS_EXTENT,
	EFFECT_UI_SCENE,
	EFFECT_UI_SHIFT,
	SDF_EFFECT_SCENE,
	DESIGN_FOLD_SCENE,
	DESIGN_FOLD_DPI_SCENE,
	SDF_EFFECT_SHIFT,
	SDF_EFFECT_Y,
	SDF_EFFECT_ADD_Y,
	SDF_BG_X,
	SDF_BG_Y,
	LIGATURE_SCENE,
	LIGATURE_Y,
	LIGATURE_STEP,
	LIGATURE_DPI,
	LIGATURE_BAND_H,
	LIGATURE_BG_X,
	LIGATURE_BG_Y,
} from "./table";
import { Align, TextLayout } from "../../src/void2d/textLayout";
import { laid } from "../../src/test/layoutHelpers";
import { DEFAULT_FONT } from "../../src/void2d/font";
import { voidPngLoad, voidPngWidth, voidPngHeight, voidPngPixel } from "./pngio.h";

const SLOT: int32 = 0;

function filteredTextMatchesPlain(): int32 {
	const override: string = env.get("VOID_FILTERED_TEXT_CAPTURE");
	const path: string = override.equals("")
		? `tests/golden/d3d11/${FILTERED_TEXT_SCENE}.png`
		: override;
	if (voidPngLoad(SLOT, path) == 0) {
		console.log(`FAIL ${FILTERED_TEXT_SCENE}: cannot read ${path}`);
		return 1;
	}
	const x0: int32 = (Math.floor(FILTERED_TEXT_X * FILTERED_TEXT_DPI) as int32) - 2;
	const y0: int32 = (Math.floor(FILTERED_TEXT_Y * FILTERED_TEXT_DPI) as int32) - 4;
	const shift: int32 = Math.floor(FILTERED_TEXT_SHIFT * FILTERED_TEXT_DPI) as int32;
	const width: int32 = (FILTERED_TEXT_W * FILTERED_TEXT_DPI) as int32;
	const x1: int32 = Math.min(x0 + width, voidPngWidth(SLOT));
	const y1: int32 = y0 + (FILTERED_TEXT_H * FILTERED_TEXT_DPI) as int32;
	if (y1 + shift > voidPngHeight(SLOT)) {
		console.log(`FAIL ${FILTERED_TEXT_SCENE}: the filtered copy runs off the capture`);
		return 1;
	}
	let differ: int32 = 0;
	let inked: int32 = 0;
	let maxDelta: int32 = 0;
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x < x1; x++) {
			for (let channel = 0; channel < 3; channel++) {
				const plain: int32 = voidPngPixel(SLOT, x, y, channel);
				const filtered: int32 = voidPngPixel(SLOT, x, y + shift, channel);
				if (plain != voidPngPixel(SLOT, x0, y0, channel)) { inked = inked + 1; }
				const delta: int32 = Math.abs(plain - filtered) as int32;
				if (delta > 0) { differ = differ + 1; }
				if (delta > maxDelta) { maxDelta = delta; }
			}
		}
	}
	if (inked == 0) {
		console.log(
			`FAIL ${FILTERED_TEXT_SCENE}: the plain copy has no ink in the compared region`,
		);
		return 1;
	}
	if (differ > 0) {
		console.log(
			`FAIL ${FILTERED_TEXT_SCENE}: the filtered copy differs from the plain one in ` +
			`${differ} channel values, max delta ${maxDelta}`,
		);
		return 1;
	}
	console.log(
		`PASS ${FILTERED_TEXT_SCENE}: text inside a filter target is byte-identical to the ` +
		`same text outside it (${inked} inked channel values)`,
	);
	return 0;
}

const JOIN_MARGIN: float32 = 10.0;
const JOIN_TOLERANCE: int32 = 2;

// Where two selected rows meet, every pixel is the selection composited once over the clear
// colour: a gap shows the background, a doubled alpha a darker blend.
function joinHoldsOnce(
	layout: TextLayout,
	upper: int32,
	x0: float32,
	x1: float32,
	background: int32[],
): int32 {
	const expected: float32[] = [CARET_SELECTION_R, CARET_SELECTION_G, CARET_SELECTION_B];
	const boundary: float32 = layout.lines[upper + 1].top;
	const y: int32 = Math.floor((CARET_Y + boundary) * CARET_DPI + 0.5) as int32;
	const left: int32 = Math.floor((CARET_X + x0 + JOIN_MARGIN) * CARET_DPI) as int32;
	const right: int32 = Math.floor((CARET_X + x1 - JOIN_MARGIN) * CARET_DPI) as int32;
	let wrong: int32 = 0;
	let checked: int32 = 0;
	for (let py = y - 1; py <= y; py++) {
		for (let px = left; px <= right; px++) {
			for (let c = 0; c < 3; c++) {
				const once: float32 = expected[c] * CARET_SELECTION_A * 255.0 +
					(background[c] as float32) * (1.0 - CARET_SELECTION_A);
				const seen: float32 = voidPngPixel(SLOT, px, py, c) as float32;
				const delta: float32 = Math.abs(seen - once) as float32;
				checked = checked + 1;
				if (delta > (JOIN_TOLERANCE as float32)) { wrong = wrong + 1; }
			}
		}
	}
	if (checked == 0) {
		console.log(`FAIL ${CARET_SCENE}: the join under line ${upper} spans no pixel`);
		return 1;
	}
	if (wrong > 0) {
		console.log(
			`FAIL ${CARET_SCENE}: ${wrong} of ${checked} channel values where lines ${upper} and ` +
			`${upper + 1} meet are not the selection composited once`,
		);
		return 1;
	}
	return 0;
}

function raggedSelectionJoins(): int32 {
	const override: string = env.get("VOID_CARET_CAPTURE");
	const path: string = override.equals("")
		? `tests/golden/d3d11/${CARET_SCENE}.png`
		: override;
	if (voidPngLoad(SLOT, path) == 0) {
		console.log(`FAIL ${CARET_SCENE}: cannot read ${path}`);
		return 1;
	}
	const background: int32[] = [
		voidPngPixel(SLOT, 2, 2, 0), voidPngPixel(SLOT, 2, 2, 1), voidPngPixel(SLOT, 2, 2, 2),
	];
	const l = laid(CARET_TEXT, {
		font: DEFAULT_FONT,
		size: CARET_SIZE,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: Align.Left,
	});
	const start: float32 = l.xForIndex(CARET_SELECTION_START);
	const firstEnd: float32 = l.lines[0].x + l.lines[0].width;
	const end: float32 = l.xForIndex(CARET_SELECTION_START + CARET_SELECTION_LENGTH);
	const failed: int32 = joinHoldsOnce(l, 0, start, firstEnd, background) +
		joinHoldsOnce(l, 1, l.lines[2].x, end, background);
	if (failed > 0) { return 1; }
	console.log(
		`PASS ${CARET_SCENE}: where ragged selected rows meet, the selection is composited once, ` +
		"with no gap",
	);
	return 0;
}

function lanesMatchPainter(): int32 {
	const override: string = env.get("VOID_LANES_CAPTURE");
	const path: string = override.equals("") ? `tests/golden/d3d11/${LANES_SCENE}.png` : override;
	if (voidPngLoad(SLOT, path) == 0) {
		console.log(`FAIL ${LANES_SCENE}: cannot read ${path}`);
		return 1;
	}
	const x0: int32 = (LANES_X as int32) - 2;
	const y0: int32 = (LANES_Y as int32) - 2;
	const x1: int32 = ((LANES_X + LANES_W) as int32) + 2;
	const y1: int32 = Math.min(((LANES_Y + LANES_H) as int32) + 2, voidPngHeight(SLOT));
	const shift: int32 = LANES_SHIFT as int32;
	if (x1 + shift > voidPngWidth(SLOT)) {
		console.log(`FAIL ${LANES_SCENE}: the list drawn without the promise runs off the capture`);
		return 1;
	}
	let differ: int32 = 0;
	let inked: int32 = 0;
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x < x1; x++) {
			for (let channel = 0; channel < 3; channel++) {
				const promised: int32 = voidPngPixel(SLOT, x, y, channel);
				if (promised != voidPngPixel(SLOT, 0, 0, channel)) { inked = inked + 1; }
				if (promised != voidPngPixel(SLOT, x + shift, y, channel)) { differ = differ + 1; }
			}
		}
	}
	if (inked == 0 || differ > 0) {
		console.log(
			`FAIL ${LANES_SCENE}: the list that promises no overlap differs from the same list ` +
			`in painter's order in ${differ} channel values (${inked} inked)`,
		);
		return 1;
	}
	console.log(
		`PASS ${LANES_SCENE}: a list drawn in lanes is byte-identical to the same list in ` +
		`painter's order (${inked} inked channel values)`,
	);
	return 0;
}

const PREMULTIPLIED_TOLERANCE: int32 = 1;

function premultipliedMatchesStraight(scene: string, captureVariable: string, rows: int32): int32 {
	const override: string = env.get(captureVariable);
	const path: string = override.equals("") ? `tests/golden/d3d11/${scene}.png` : override;
	if (voidPngLoad(SLOT, path) == 0) {
		console.log(`FAIL ${scene}: cannot read ${path}`);
		return 1;
	}
	const x0: int32 = PREMULTIPLIED_X as int32;
	const y0: int32 = PREMULTIPLIED_Y as int32;
	const x1: int32 = x0 + PREMULTIPLIED_SIZE;
	const rowSpan: float32 = ((rows - 1) as float32) * PREMULTIPLIED_ROW_STEP;
	const y1: int32 = y0 + (rowSpan as int32) + PREMULTIPLIED_SIZE;
	const shift: int32 = PREMULTIPLIED_SHIFT as int32;
	if (x1 + shift > voidPngWidth(SLOT) || y1 > voidPngHeight(SLOT)) {
		console.log(`FAIL ${scene}: the premultiplied copy runs off the capture`);
		return 1;
	}
	let differ: int32 = 0;
	let inked: int32 = 0;
	let maxDelta: int32 = 0;
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x < x1; x++) {
			for (let channel = 0; channel < 3; channel++) {
				const straight: int32 = voidPngPixel(SLOT, x, y, channel);
				if (straight != voidPngPixel(SLOT, 0, 0, channel)) { inked = inked + 1; }
				const premultiplied: int32 = voidPngPixel(SLOT, x + shift, y, channel);
				const delta: int32 = Math.abs(straight - premultiplied) as int32;
				if (delta > PREMULTIPLIED_TOLERANCE) { differ = differ + 1; }
				if (delta > maxDelta) { maxDelta = delta; }
			}
		}
	}
	if (inked == 0 || differ > 0) {
		console.log(
			`FAIL ${scene}: the premultiplied copy differs from the straight one by more than ` +
			`${PREMULTIPLIED_TOLERANCE} in ${differ} channel values, max delta ${maxDelta} ` +
			`(${inked} inked)`,
		);
		return 1;
	}
	console.log(
		`PASS ${scene}: a premultiplied source draws what the same straight pixels draw, ` +
		`max delta ${maxDelta} (${inked} inked channel values)`,
	);
	return 0;
}

function everyTargetFiltered(): int32 {
	const override: string = env.get("VOID_MANY_TARGETS_CAPTURE");
	const path: string = override.equals("")
		? `tests/golden/d3d11/${MANY_TARGETS_SCENE}.png`
		: override;
	if (voidPngLoad(SLOT, path) == 0) {
		console.log(`FAIL ${MANY_TARGETS_SCENE}: cannot read ${path}`);
		return 1;
	}
	const x0: int32 = MANY_TARGETS_ORIGIN as int32;
	const y0: int32 = MANY_TARGETS_ORIGIN as int32;
	const step: int32 = MANY_TARGETS_STEP as int32;
	let inked: int32 = 0;
	let differing: int32 = 0;
	for (let k: int32 = 1; k < MANY_TARGETS_COUNT; k++) {
		const dx: int32 = (k % MANY_TARGETS_COLUMNS) * step;
		const dy: int32 = (k / MANY_TARGETS_COLUMNS) * step;
		let differ: int32 = 0;
		for (let y = y0; y < y0 + MANY_TARGETS_EXTENT; y++) {
			for (let x = x0; x < x0 + MANY_TARGETS_EXTENT; x++) {
				for (let channel = 0; channel < 3; channel++) {
					const first: int32 = voidPngPixel(SLOT, x, y, channel);
					if (k == 1 && first != voidPngPixel(SLOT, 0, 0, channel)) { inked = inked + 1; }
					const other: int32 = voidPngPixel(SLOT, x + dx, y + dy, channel);
					if (first != other) { differ = differ + 1; }
				}
			}
		}
		if (differ > 0) {
			console.log(`  node ${k} differs from node 0 in ${differ} channel values`);
			differing = differing + 1;
		}
	}
	const overlapX: int32 = x0 + 15;
	const overlapY: int32 = y0 + 12;
	const single: int32[] = [48, 107, 136];
	for (let channel = 0; channel < 3; channel++) {
		const got: int32 = voidPngPixel(SLOT, overlapX, overlapY, channel);
		if ((Math.abs(got - single[channel]) as int32) > 2) {
			console.log(
				`FAIL ${MANY_TARGETS_SCENE}: the first group's overlap reads ${got} in channel ` +
				`${channel}, where one composite at alpha 0.5 gives ${single[channel]}`,
			);
			return 1;
		}
	}
	if (inked == 0 || differing > 0) {
		console.log(
			`FAIL ${MANY_TARGETS_SCENE}: ${differing} of ${MANY_TARGETS_COUNT - 1} ` +
			`filtered groups differ from the first (${inked} inked)`,
		);
		return 1;
	}
	console.log(
		`PASS ${MANY_TARGETS_SCENE}: all ${MANY_TARGETS_COUNT} filtered groups are ` +
		`byte-identical, so each had a target of its own (${inked} inked channel values)`,
	);
	return 0;
}

const LUMA_TOLERANCE: float32 = 2.0;

function uiEffectIsLuma(): int32 {
	const override: string = env.get("VOID_EFFECT_UI_CAPTURE");
	const path: string = override.equals("")
		? `tests/golden/d3d11/${EFFECT_UI_SCENE}.png`
		: override;
	if (voidPngLoad(SLOT, path) == 0) {
		console.log(`FAIL ${EFFECT_UI_SCENE}: cannot read ${path}`);
		return 1;
	}
	const shift: int32 = EFFECT_UI_SHIFT as int32;
	let coloured: int32 = 0;
	let differ: int32 = 0;
	let worst: float32 = 0.0;
	for (let y: int32 = 0; y < voidPngHeight(SLOT); y++) {
		for (let x: int32 = 0; x < shift; x++) {
			const r: int32 = voidPngPixel(SLOT, x, y, 0);
			const g: int32 = voidPngPixel(SLOT, x, y, 1);
			const b: int32 = voidPngPixel(SLOT, x, y, 2);
			if (r != g || g != b) { coloured = coloured + 1; }
			const luma: float32 = 0.299 * (r as float32) + 0.587 * (g as float32)
				+ 0.114 * (b as float32);
			for (let channel = 0; channel < 3; channel++) {
				const got: float32 = voidPngPixel(SLOT, x + shift, y, channel) as float32;
				const delta: float32 = Math.abs(got - luma) as float32;
				if (delta > LUMA_TOLERANCE) { differ = differ + 1; }
				if (delta > worst) { worst = delta; }
			}
		}
	}
	if (coloured == 0 || differ > 0) {
		console.log(
			`FAIL ${EFFECT_UI_SCENE}: the grayscale copy is off its twin's luma by more than ` +
			`${LUMA_TOLERANCE} ` +
			`in ${differ} channel values, worst ${worst} (${coloured} coloured pixels)`,
		);
		return 1;
	}
	console.log(
		`PASS ${EFFECT_UI_SCENE}: every UI kind under a grayscale matrix draws its twin's luma, ` +
		`worst ${worst} (${coloured} coloured pixels)`,
	);
	return 0;
}

const SDF_EFFECT_TOLERANCE: int32 = 1;
const SDF_EFFECT_BAND_H: int32 = 90;

function sdfEffectMatchesPlain(): int32 {
	const override: string = env.get("VOID_SDF_EFFECT_CAPTURE");
	const path: string = override.equals("")
		? `tests/golden/d3d11/${SDF_EFFECT_SCENE}.png`
		: override;
	if (voidPngLoad(SLOT, path) == 0) {
		console.log(`FAIL ${SDF_EFFECT_SCENE}: cannot read ${path}`);
		return 1;
	}
	const shift: int32 = SDF_EFFECT_SHIFT as int32;
	const bandTop: int32 = (SDF_EFFECT_Y as int32) - 20;
	const bandBottom: int32 = bandTop + SDF_EFFECT_BAND_H;
	let inked: int32 = 0;
	let differ: int32 = 0;
	let worst: int32 = 0;
	for (let y: int32 = bandTop; y < bandBottom; y++) {
		for (let x: int32 = 0; x < shift; x++) {
			for (let channel: int32 = 0; channel < 3; channel++) {
				const plain: int32 = voidPngPixel(SLOT, x, y, channel);
				const keyed: int32 = voidPngPixel(SLOT, x + shift, y, channel);
				const clear: int32 = voidPngPixel(SLOT, SDF_BG_X, SDF_BG_Y, channel);
				if (plain != clear) { inked = inked + 1; }
				const delta: int32 = Math.abs(plain - keyed) as int32;
				if (delta > SDF_EFFECT_TOLERANCE) { differ = differ + 1; }
				if (delta > worst) { worst = delta; }
			}
		}
	}
	let plainRed: int32 = 0;
	let tintedRed: int32 = 0;
	const addOffset: int32 = (SDF_EFFECT_ADD_Y - SDF_EFFECT_Y) as int32;
	for (let y: int32 = bandTop; y < bandBottom; y++) {
		for (let x: int32 = 0; x < shift; x++) {
			plainRed = plainRed + voidPngPixel(SLOT, x, y, 0);
			tintedRed = tintedRed + voidPngPixel(SLOT, x, y + addOffset, 0);
		}
	}
	if (inked < 600 || differ > 0 || tintedRed <= plainRed) {
		console.log(
			`FAIL ${SDF_EFFECT_SCENE}: a rotated label under a never-matching colour key is off ` +
			`its plain twin by more than ${SDF_EFFECT_TOLERANCE} in ${differ} channel values ` +
			`(worst ${worst}, ${inked} inked), or its colorAdd copy is not redder ` +
			`(${tintedRed} against ${plainRed})`,
		);
		return 1;
	}
	console.log(
		`PASS ${SDF_EFFECT_SCENE}: the Vertex program draws the SDF label as the UI ` +
		`program does, worst ${worst} (${inked} inked channel values), the colorAdd copy redder`,
	);
	return 0;
}

const LIGATURE_MIN_INKED: int32 = 300;
const LIGATURE_MIN_DIFFERENT: int32 = 40;
const LIGATURE_WIDTH: int32 = 320;

const LIGATURE_WEAK: int32 = 16;
const LIGATURE_STRONG: int32 = 96;

function inkStrength(x: int32, y: int32): int32 {
	let strongest: int32 = 0;
	for (let channel: int32 = 0; channel < 3; channel++) {
		const clear: int32 = voidPngPixel(SLOT, LIGATURE_BG_X, LIGATURE_BG_Y, channel);
		const gap: int32 = Math.abs(voidPngPixel(SLOT, x, y, channel) - clear) as int32;
		if (gap > strongest) { strongest = gap; }
	}
	return strongest;
}

function inkedPixel(x: int32, y: int32): boolean {
	return inkStrength(x, y) >= LIGATURE_WEAK;
}

function inkOnlyOnOne(a: int32, b: int32): boolean {
	return (a >= LIGATURE_STRONG && b < LIGATURE_WEAK) ||
		(b >= LIGATURE_STRONG && a < LIGATURE_WEAK);
}

function bandTop(line: int32): int32 {
	return (((LIGATURE_Y + (line as float32) * LIGATURE_STEP) * LIGATURE_DPI) as int32) - 4;
}

function inkedIn(line: int32): int32 {
	let inked: int32 = 0;
	for (let y: int32 = 0; y < LIGATURE_BAND_H; y++) {
		for (let x: int32 = 0; x < LIGATURE_WIDTH; x++) {
			if (inkedPixel(x, bandTop(line) + y)) { inked = inked + 1; }
		}
	}
	return inked;
}

function inkDiffers(first: int32, second: int32): int32 {
	let differ: int32 = 0;
	for (let y: int32 = 0; y < LIGATURE_BAND_H; y++) {
		for (let x: int32 = 0; x < LIGATURE_WIDTH; x++) {
			const a: int32 = inkStrength(x, bandTop(first) + y);
			const b: int32 = inkStrength(x, bandTop(second) + y);
			if (inkOnlyOnOne(a, b)) {
				differ = differ + 1;
			}
		}
	}
	return differ;
}

function ligatureLinesAgree(): int32 {
	const override: string = env.get("VOID_LIGATURE_CAPTURE");
	const path: string = override.equals("")
		? `tests/golden/d3d11/${LIGATURE_SCENE}.png`
		: override;
	if (voidPngLoad(SLOT, path) == 0) {
		console.log(`FAIL ${LIGATURE_SCENE}: cannot read ${path}`);
		return 1;
	}
	const inked: int32 = inkedIn(1);
	const split: int32 = inkDiffers(1, 2);
	const ligated: int32 = inkDiffers(0, 1);
	const ligatedSplit: int32 = inkDiffers(0, 2);
	if (inked < LIGATURE_MIN_INKED || split > 0 || ligated < LIGATURE_MIN_DIFFERENT ||
		ligatedSplit < LIGATURE_MIN_DIFFERENT) {
		console.log(
			`FAIL ${LIGATURE_SCENE}: the calt 0 line inks ${inked} pixels (at least ` +
			`${LIGATURE_MIN_INKED}), the colour-split line is off it in ${split} pixels (none ` +
			`allowed), the ligated line is off the calt 0 line in ${ligated} and off the split ` +
			`line in ${ligatedSplit} (at least ${LIGATURE_MIN_DIFFERENT} each)`,
		);
		return 1;
	}
	console.log(
		`PASS ${LIGATURE_SCENE}: a colour change through every ligature draws the calt 0 glyphs ` +
		`(${inked} inked pixels, 0 apart), and the ligated line is ${ligated} pixels off them`,
	);
	return 0;
}

function designFoldMatchesDpi(): int32 {
	const fold: string = `tests/golden/d3d11/${DESIGN_FOLD_SCENE}.png`;
	const dpi: string = `tests/golden/d3d11/${DESIGN_FOLD_DPI_SCENE}.png`;
	if (voidPngLoad(0, fold) == 0 || voidPngLoad(1, dpi) == 0) {
		console.log(`FAIL ${DESIGN_FOLD_SCENE}: cannot read ${fold} and ${dpi}`);
		return 1;
	}
	if (voidPngWidth(0) != voidPngWidth(1) || voidPngHeight(0) != voidPngHeight(1)) {
		console.log(`FAIL ${DESIGN_FOLD_SCENE}: the two captures differ in size`);
		return 1;
	}
	let differ: int32 = 0;
	let inked: int32 = 0;
	for (let y = 0; y < voidPngHeight(0); y++) {
		for (let x = 0; x < voidPngWidth(0); x++) {
			for (let channel = 0; channel < 3; channel++) {
				const folded: int32 = voidPngPixel(0, x, y, channel);
				if (folded != voidPngPixel(0, 0, 0, channel)) { inked = inked + 1; }
				if (folded != voidPngPixel(1, x, y, channel)) { differ = differ + 1; }
			}
		}
	}
	if (inked == 0 || differ > 0) {
		console.log(
			`FAIL ${DESIGN_FOLD_SCENE}: labels in a LetterBox scene at 1.6 differ from the same ` +
			`labels at DPI 1.6 in ${differ} channel values (${inked} inked)`,
		);
		return 1;
	}
	console.log(
		`PASS ${DESIGN_FOLD_SCENE}: labels in a LetterBox scene at 1.6 are byte-identical to the ` +
		`same labels at DPI 1.6 (${inked} inked channel values)`,
	);
	return 0;
}

process.exit(
	filteredTextMatchesPlain() + raggedSelectionJoins() + lanesMatchPainter() +
	designFoldMatchesDpi() +
	premultipliedMatchesStraight(
		PREMULTIPLIED_EFFECT_SCENE, "VOID_PREMULTIPLIED_EFFECT_CAPTURE", 2,
	) +
	premultipliedMatchesStraight(PREMULTIPLIED_STYLE_SCENE, "VOID_PREMULTIPLIED_STYLE_CAPTURE", 1) +
	everyTargetFiltered() +
	uiEffectIsLuma() +
	sdfEffectMatchesPlain() +
	ligatureLinesAgree(),
);
