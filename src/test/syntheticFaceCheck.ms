import {
	loadFace,
	syntheticFace,
	glyphIndex,
	glyphAdvance,
	pageTexel,
} from "../void2d/face";
import { GlyphAtlas, GlyphTile } from "../void2d/glyphAtlas";

const SIZE: float32 = 32.0;
const UNITS_PER_EM: float32 = 2048.0;
const INTER_LINE_UNITS: float32 = 1984.0 + 494.0;
const ITALIC_SKEW: float32 = 0.21255656;

let regularFace: int32 = -1;
const atlas: GlyphAtlas = GlyphAtlas.create(256, 4);

function regular(): int32 {
	if (regularFace < 0) { regularFace = try loadFace("assets/font.ttf") catch -1; }
	return regularFace;
}

function tileOf(face: int32, codepoint: int32): GlyphTile {
	const index = atlas.acquire({ face: face, glyph: glyphIndex(face, codepoint), sizePx: SIZE, variant: 0 });
	return atlas.tile(index.ok ? index.value : 0);
}

function rowCoverage(t: GlyphTile, deviceY: int32): float32 {
	let sum: float32 = 0.0;
	for (let x = 0; x < t.width; x++) {
		sum = sum + (pageTexel(atlas.pageHandle(t.page), t.x + x, t.y + deviceY - t.top) as float32);
	}
	return sum / (255.0 as float32);
}

function rowCentroid(t: GlyphTile, deviceY: int32): float32 {
	let sum: float32 = 0.0;
	let moment: float32 = 0.0;
	for (let x = 0; x < t.width; x++) {
		const c = pageTexel(atlas.pageHandle(t.page), t.x + x, t.y + deviceY - t.top) as float32;
		sum = sum + c;
		moment = moment + c * ((t.left + x) as float32 + 0.5);
	}
	return moment / sum;
}

test "synthetic bold widens the advance by its embolden strength" {
	const bold = try syntheticFace(regular(), true, false) catch -1;
	assert bold >= 0;
	const h = glyphIndex(regular(), "H".code);
	const strength: float32 = INTER_LINE_UNITS / 32.0 * SIZE / UNITS_PER_EM;
	assert Math.abs(glyphAdvance(bold, h, SIZE) - glyphAdvance(regular(), h, SIZE) - strength) < 0.001;
}

test "synthetic bold thickens a stem by its strength, measured in coverage" {
	const bold = try syntheticFace(regular(), true, false) catch -1;
	const stem: float32 = 180.0 * SIZE / UNITS_PER_EM;
	const strength: float32 = INTER_LINE_UNITS / 32.0 * SIZE / UNITS_PER_EM;
	const regularRow = rowCoverage(tileOf(regular(), "l".code), -12);
	const boldRow = rowCoverage(tileOf(bold, "l".code), -12);
	console.log(`synthetic bold stem: regular ${regularRow} px, bold ${boldRow} px`);
	assert Math.abs(regularRow - stem) < 0.05;
	assert Math.abs(boldRow - (stem + strength)) < 0.05;
}

test "synthetic italic slants 12 degrees about the baseline and keeps the advance" {
	const italic = try syntheticFace(regular(), false, true) catch -1;
	const l = glyphIndex(regular(), "l".code);
	assert glyphAdvance(italic, l, SIZE) == glyphAdvance(regular(), l, SIZE);
	const upright = tileOf(regular(), "l".code);
	const slanted = tileOf(italic, "l".code);
	for (const deviceY of [-4, -12, -20]) {
		const height: float32 = -(deviceY as float32) - 0.5;
		const expected: float32 = rowCentroid(upright, deviceY) + height * ITALIC_SKEW;
		assert Math.abs(rowCentroid(slanted, deviceY) - expected) < 0.05;
	}
}
