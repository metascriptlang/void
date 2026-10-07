import { readFile } from "std/fs";
import { loadImageSync, imageWidth, imageHeight, freeImage } from "../assets/image";
import { SpriteCanvas, drawSprite, spriteCodepoint, spriteCount } from "../void2d/spriteGlyph";
import { trimSpaces, parseInt32, NOT_A_NUMBER } from "../../tests/harness/parse";

struct CellSize {
	width: int32;
	height: int32;
	thickness: int32;
}

struct CodeRange {
	first: int32;
	last: int32;
}

struct Family {
	name: string;
	ranges: CodeRange[];
}

struct Budget {
	maxPixels: int32;
	maxDelta: int32;
}

struct Distance {
	pixels: int32;
	worst: int32;
}

const ORACLE_DIR: string = "tests/oracle/ghostty/sprite/";
const PENDING_PATH: string = "tests/PENDING.md";
const SIZES: CellSize[] = [
	{ width: 18, height: 36, thickness: 4 },
	{ width: 12, height: 24, thickness: 3 },
	{ width: 11, height: 21, thickness: 2 },
	{ width: 9, height: 17, thickness: 1 },
];
const BUCKETS: int32[] = [0x2500, 0x2800, 0xE000, 0x1CD00, 0x1FB00];
const EXACT: CodeRange[] = [
	{ first: 0x2500, last: 0x256C },
	{ first: 0x2574, last: 0x257F },
	{ first: 0x2580, last: 0x259F },
	{ first: 0x2800, last: 0x28FF },
	{ first: 0x1CD00, last: 0x1CDE5 },
	{ first: 0x1FB00, last: 0x1FB3B },
	{ first: 0x1FB70, last: 0x1FB92 },
	{ first: 0x1FB94, last: 0x1FB97 },
];
const GRADED: Family[] = [
	{ name: "arcs", ranges: [{ first: 0x256D, last: 0x2570 }] },
	{ name: "diagonals", ranges: [{ first: 0x2571, last: 0x2573 }] },
	{
		name: "triangles",
		ranges: [
			{ first: 0x25E2, last: 0x25E5 },
			{ first: 0x25F8, last: 0x25FA },
			{ first: 0x25FF, last: 0x25FF },
		],
	},
	{
		name: "powerline",
		ranges: [
			{ first: 0xE0B0, last: 0xE0BF },
			{ first: 0xE0D2, last: 0xE0D2 },
			{ first: 0xE0D4, last: 0xE0D4 },
		],
	},
];
const COVERAGE_STEP: int32 = 16;

function hexUpper(value: int32): string {
	const digits: string = "0123456789ABCDEF";
	let out: string = "";
	let rest: int32 = value;
	while (rest > 0) {
		out = digits.charAt(rest % 16) + out;
		rest = rest / 16;
	}
	return out;
}

function pngPath(bucket: int32, size: CellSize): string {
	return `${ORACLE_DIR}U+${hexUpper(bucket)}...U+${hexUpper(bucket + 255)}` +
		`-${size.width}x${size.height}+${size.thickness}.png`;
}

function inRanges(codepoint: int32, ranges: CodeRange[]): boolean {
	for (const r of ranges) {
		if (codepoint >= r.first && codepoint <= r.last) { return true; }
	}
	return false;
}

function rangeTotal(ranges: CodeRange[]): int32 {
	let n: int32 = 0;
	for (const r of ranges) { n = n + (r.last - r.first + 1); }
	return n;
}

function familyOf(codepoint: int32): int32 {
	for (let i = 0; i < (GRADED.length as int32); i++) {
		if (inRanges(codepoint, GRADED[i].ranges)) { return i; }
	}
	return -1;
}

function drawn(codepoint: int32, size: CellSize): SpriteCanvas {
	const canvas = drawSprite(codepoint, size.width, size.height, size.thickness);
	if (!canvas.ok) {
		console.log(
			`sprite oracle: U+${hexUpper(codepoint)} was refused (${canvas.error.toString()})`,
		);
		unreachable;
	}
	return canvas.value;
}

function referenceAt(
	reference: Ptr<uint8>, refWidth: int32, bucket: int32, codepoint: int32,
	canvas: SpriteCanvas, x: int32, y: int32,
): int32 {
	const slot: int32 = codepoint - bucket;
	const originX: int32 = canvas.width * (slot % 16);
	const originY: int32 = canvas.height * (slot / 16);
	return reference[(originY + y) * refWidth + originX + x] as int32;
}

function distance(
	reference: Ptr<uint8>, refWidth: int32, bucket: int32, codepoint: int32,
	canvas: SpriteCanvas,
): Distance {
	let pixels: int32 = 0;
	let worst: int32 = 0;
	for (let y = 0; y < canvas.height; y++) {
		for (let x = 0; x < canvas.width; x++) {
			const expected = referenceAt(reference, refWidth, bucket, codepoint, canvas, x, y);
			let delta: int32 = expected - (canvas.pixels[y * canvas.width + x] as int32);
			if (delta < 0) { delta = -delta; }
			if (delta > COVERAGE_STEP) { pixels = pixels + 1; }
			if (delta > worst) { worst = delta; }
		}
	}
	return { pixels: pixels, worst: worst };
}

function equalCell(
	reference: Ptr<uint8>, refWidth: int32, bucket: int32, codepoint: int32,
	canvas: SpriteCanvas,
): boolean {
	for (let y = 0; y < canvas.height; y++) {
		for (let x = 0; x < canvas.width; x++) {
			const expected = referenceAt(reference, refWidth, bucket, codepoint, canvas, x, y);
			if (expected != (canvas.pixels[y * canvas.width + x] as int32)) { return false; }
		}
	}
	return true;
}

function budgetOf(family: string): Budget {
	const text = readFile(PENDING_PATH);
	if (!text.ok) {
		console.log(`sprite oracle: ${PENDING_PATH} cannot be read`);
		unreachable;
	}
	for (const line of text.value.split("\n")) {
		const cells = line.split("|");
		if ((cells.length as int32) < 8) { continue; }
		if (!trimSpaces(cells[1]).equals(`sprite-aa:${family}`)) { continue; }
		const maxPixels: int32 = parseInt32(cells[6]);
		const maxDelta: int32 = parseInt32(cells[7]);
		if (maxPixels == NOT_A_NUMBER || maxDelta == NOT_A_NUMBER) {
			console.log(`sprite oracle: ${PENDING_PATH} row sprite-aa:${family} has no budget`);
			unreachable;
		}
		return { maxPixels: maxPixels, maxDelta: maxDelta };
	}
	console.log(`sprite oracle: ${PENDING_PATH} has no row sprite-aa:${family}`);
	unreachable;
}

struct RangeTally {
	cells: int32;
	equal: int32;
}

test "blocks, straight box lines, braille, sextants and octants equal Ghostty's byte for byte" {
	let tallies: RangeTally[] = [];
	for (const r of EXACT) { tallies.push({ cells: 0, equal: 0 }); }
	for (const size of SIZES) {
		for (const bucket of BUCKETS) {
			const raw = loadImageSync(pngPath(bucket, size), 1);
			const refWidth: int32 = imageWidth();
			const reference = raw as Ptr<uint8>;
			assert refWidth == (size.width + 2 * (size.width / 4)) * 16;
			assert imageHeight() == (size.height + 2 * (size.height / 4)) * 16;
			for (let k = 0; k < 256; k++) {
				const codepoint: int32 = bucket + k;
				if (!inRanges(codepoint, EXACT)) { continue; }
				const canvas = drawn(codepoint, size);
				const same: boolean = equalCell(reference, refWidth, bucket, codepoint, canvas);
				for (let i = 0; i < (EXACT.length as int32); i++) {
					if (codepoint >= EXACT[i].first && codepoint <= EXACT[i].last) {
						tallies[i].cells = tallies[i].cells + 1;
						if (same) { tallies[i].equal = tallies[i].equal + 1; }
					}
				}
			}
			freeImage(raw);
		}
	}
	let cells: int32 = 0;
	let equal: int32 = 0;
	for (let i = 0; i < (EXACT.length as int32); i++) {
		console.log(
			`sprite oracle: U+${hexUpper(EXACT[i].first)}..U+${hexUpper(EXACT[i].last)} ` +
			`${tallies[i].equal} / ${tallies[i].cells} cells equal over ${SIZES.length} sizes`,
		);
		cells = cells + tallies[i].cells;
		equal = equal + tallies[i].equal;
	}
	assert cells == rangeTotal(EXACT) * (SIZES.length as int32);
	assert equal == cells;
}

struct Tally {
	cells: int32;
	pixels: int32;
	worst: int32;
}

test "diagonals, arcs, triangles and powerline stay inside the budget listed for them" {
	let tallies: Tally[] = [];
	for (const f of GRADED) { tallies.push({ cells: 0, pixels: 0, worst: 0 }); }
	for (const size of SIZES) {
		for (const bucket of BUCKETS) {
			const raw = loadImageSync(pngPath(bucket, size), 1);
			const refWidth: int32 = imageWidth();
			const reference = raw as Ptr<uint8>;
			for (let k = 0; k < 256; k++) {
				const codepoint: int32 = bucket + k;
				const family: int32 = familyOf(codepoint);
				if (family < 0) { continue; }
				const canvas = drawn(codepoint, size);
				const d = distance(reference, refWidth, bucket, codepoint, canvas);
				tallies[family].cells = tallies[family].cells + 1;
				if (d.pixels > tallies[family].pixels) { tallies[family].pixels = d.pixels; }
				if (d.worst > tallies[family].worst) { tallies[family].worst = d.worst; }
			}
			freeImage(raw);
		}
	}
	for (let i = 0; i < (GRADED.length as int32); i++) {
		const budget = budgetOf(GRADED[i].name);
		console.log(
			`sprite oracle: ${GRADED[i].name} ${tallies[i].cells} cells, at most ` +
			`${tallies[i].pixels} pixels past ${COVERAGE_STEP} (budget ${budget.maxPixels}), ` +
			`worst delta ${tallies[i].worst} (budget ${budget.maxDelta})`,
		);
		assert tallies[i].cells == rangeTotal(GRADED[i].ranges) * (SIZES.length as int32);
		assert tallies[i].pixels <= budget.maxPixels;
		assert tallies[i].worst <= budget.maxDelta;
	}
}

test "every sprite the table draws is in exactly one class, exact or graded" {
	let classified: int32 = rangeTotal(EXACT);
	for (const f of GRADED) { classified = classified + rangeTotal(f.ranges); }
	assert spriteCount() == classified;
	for (let id = 1; id <= spriteCount(); id++) {
		const codepoint: int32 = spriteCodepoint(id);
		const exact: boolean = inRanges(codepoint, EXACT);
		const graded: boolean = familyOf(codepoint) >= 0;
		assert exact != graded;
	}
}

test "the comparison is not vacuous: another glyph, another line weight or another shape differs" {
	const size = SIZES[0];
	const raw = loadImageSync(pngPath(0x2500, size), 1);
	const refWidth: int32 = imageWidth();
	const reference = raw as Ptr<uint8>;
	const lowerHalf = drawn(0x2584, size);
	assert equalCell(reference, refWidth, 0x2500, 0x2584, lowerHalf);
	assert !equalCell(reference, refWidth, 0x2500, 0x2580, lowerHalf);
	const thin = drawn(0x2500, { width: 18, height: 36, thickness: 3 });
	assert !equalCell(reference, refWidth, 0x2500, 0x2500, thin);
	const budget = budgetOf("diagonals");
	const honest = distance(reference, refWidth, 0x2500, 0x2571, drawn(0x2571, size));
	const crossed = distance(reference, refWidth, 0x2500, 0x2571, drawn(0x2572, size));
	assert honest.pixels <= budget.maxPixels && honest.worst <= budget.maxDelta;
	assert crossed.pixels > budget.maxPixels && crossed.worst > budget.maxDelta;
	freeImage(raw);
}

function litColumns(canvas: SpriteCanvas, row: int32): string {
	let out: string = "";
	for (let x = 0; x < canvas.width; x++) {
		out = out + (canvas.pixels[(row + canvas.padY) * canvas.width + x] != 0 ? "#" : ".");
	}
	return out;
}

test "an odd cell splits its halves with complementary rounding: 7 px is 0..4 and 3..7" {
	const size: CellSize = { width: 7, height: 8, thickness: 1 };
	assert litColumns(drawn(0x258C, size), 0) == ".####....";
	assert litColumns(drawn(0x2590, size), 0) == "....####.";
}

function pixelAt(canvas: SpriteCanvas, x: int32, y: int32): int32 {
	return canvas.pixels[(y + canvas.padY) * canvas.width + x + canvas.padX] as int32;
}

test "a box line and a powerline cap in neighbouring cells meet without a gap or a double edge" {
	for (const size of SIZES) {
		const line = drawn(0x2500, size);
		const cap = drawn(0xE0B0, size);
		const middle: int32 = (size.height - size.thickness) / 2;
		for (let y = middle; y < middle + size.thickness; y++) {
			assert pixelAt(line, size.width - 1, y) == 255;
			assert pixelAt(cap, 0, y) == 255;
		}
		for (let y = 0; y < size.height; y++) {
			assert pixelAt(line, size.width, y) == 0;
			assert pixelAt(cap, -1, y) == 0;
		}
		assert pixelAt(cap, 0, 0) < 255 && pixelAt(cap, 0, size.height - 1) < 255;
	}
}
