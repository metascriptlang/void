import { env } from "std/process";
import {
	FILTERED_TEXT_SCENE,
	FILTERED_TEXT_DPI,
	FILTERED_TEXT_X,
	FILTERED_TEXT_Y,
	FILTERED_TEXT_SHIFT,
	FILTERED_TEXT_W,
	FILTERED_TEXT_H,
} from "./table";
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

process.exit(filteredTextMatchesPlain());
