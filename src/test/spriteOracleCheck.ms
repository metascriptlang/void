import { loadImageSync, imageWidth, imageHeight, freeImage } from "../assets/image";
import { SpriteCanvas, drawSprite, spriteCodepoint, spriteCount } from "../void2d/spriteGlyph";

struct CellSize {
	width: int32;
	height: int32;
	thickness: int32;
}

struct CodeRange {
	first: int32;
	last: int32;
}

const ORACLE_DIR: string = "tests/oracle/ghostty/sprite/";
const SIZES: CellSize[] = [
	{ width: 18, height: 36, thickness: 4 },
	{ width: 12, height: 24, thickness: 3 },
	{ width: 11, height: 21, thickness: 2 },
	{ width: 9, height: 17, thickness: 1 },
];
const BUCKETS: int32[] = [0x2500, 0x2800];
const EXACT: CodeRange[] = [
	{ first: 0x2500, last: 0x256C },
	{ first: 0x2574, last: 0x257F },
	{ first: 0x2580, last: 0x259F },
	{ first: 0x2800, last: 0x28FF },
];

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

function isExact(codepoint: int32): boolean {
	for (const r of EXACT) {
		if (codepoint >= r.first && codepoint <= r.last) { return true; }
	}
	return false;
}

function exactCount(): int32 {
	let n: int32 = 0;
	for (const r of EXACT) { n = n + (r.last - r.first + 1); }
	return n;
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

function mismatches(
	reference: Ptr<uint8>, referenceWidth: int32, bucket: int32, codepoint: int32,
	canvas: SpriteCanvas,
): int32 {
	const slot: int32 = codepoint - bucket;
	const originX: int32 = canvas.width * (slot % 16);
	const originY: int32 = canvas.height * (slot / 16);
	let differing: int32 = 0;
	for (let y = 0; y < canvas.height; y++) {
		for (let x = 0; x < canvas.width; x++) {
			const at: int32 = (originY + y) * referenceWidth + originX + x;
			const expected: int32 = reference[at] as int32;
			const actual: int32 = canvas.pixels[y * canvas.width + x] as int32;
			if (expected != actual) { differing = differing + 1; }
		}
	}
	return differing;
}

struct RangeTally {
	cells: int32;
	equal: int32;
}

test "blocks, straight box lines and braille equal Ghostty's sprites byte for byte at four sizes" {
	let tallies: RangeTally[] = [];
	for (const r of EXACT) { tallies.push({ cells: 0, equal: 0 }); }
	for (const size of SIZES) {
		for (const bucket of BUCKETS) {
			const raw = loadImageSync(pngPath(bucket, size), 1);
			const referenceWidth: int32 = imageWidth();
			const reference = raw as Ptr<uint8>;
			assert referenceWidth == (size.width + 2 * (size.width / 4)) * 16;
			assert imageHeight() == (size.height + 2 * (size.height / 4)) * 16;
			for (let k = 0; k < 256; k++) {
				const codepoint: int32 = bucket + k;
				if (!isExact(codepoint)) { continue; }
				const canvas = drawn(codepoint, size);
				const differing: int32 = mismatches(
					reference, referenceWidth, bucket, codepoint, canvas,
				);
				const same: boolean = differing == 0;
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
	assert cells == exactCount() * (SIZES.length as int32);
	assert equal == cells;
}

test "every sprite the table draws is classified: this slice has no graded ones" {
	assert spriteCount() == exactCount();
	for (let id = 1; id <= spriteCount(); id++) {
		assert isExact(spriteCodepoint(id));
	}
}

test "the comparison is not vacuous: another glyph's cell, or another line weight, differs" {
	const size = SIZES[0];
	const raw = loadImageSync(pngPath(0x2500, size), 1);
	const referenceWidth: int32 = imageWidth();
	const reference = raw as Ptr<uint8>;
	const lowerHalf = drawn(0x2584, size);
	assert mismatches(reference, referenceWidth, 0x2500, 0x2584, lowerHalf) == 0;
	assert mismatches(reference, referenceWidth, 0x2500, 0x2580, lowerHalf) > 0;
	const thin = drawn(0x2500, { width: 18, height: 36, thickness: 3 });
	assert mismatches(reference, referenceWidth, 0x2500, 0x2500, thin) > 0;
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
