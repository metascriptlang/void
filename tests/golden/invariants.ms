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
} from "./table";
import { TextLayout, Align } from "../../src/void2d/textLayout";
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
	const l = TextLayout.layout(CARET_TEXT, {
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

process.exit(filteredTextMatchesPlain() + raggedSelectionJoins());
