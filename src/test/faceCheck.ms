import {
	FaceError,
	loadFace,
	syntheticFace,
	spriteFace,
	isSpriteFace,
	spriteCell,
	glyphIndex,
	glyphAdvance,
	glyphKern,
	faceMetrics,
	decorationMetrics,
	DecorationMetrics,
} from "../void2d/face";
import { spriteCount, spriteCodepoint, spriteIndex, spriteTableFault } from "../void2d/spriteGlyph";

let loadedFace: int32 = -1;

function testFace(): int32 {
	if (loadedFace < 0) { loadedFace = try loadFace("assets/font.ttf") catch -1; }
	return loadedFace;
}

test "a face that cannot load says why, in the error the C loader chose" {
	const missing = loadFace("tests/fonts/noSuchFont.ttf");
	assert !missing.ok;
	if (!missing.ok) { assert missing.error == FaceError.Unreadable; }
	const notAFont = loadFace("tests/fonts/README.md");
	assert !notAFont.ok;
	if (!notAFont.ok) { assert notAFont.error == FaceError.NotAFont; }
	const noBase = syntheticFace(1000000, true, false);
	assert !noBase.ok;
	if (!noBase.ok) { assert noBase.error == FaceError.NoBaseFace; }
}

test "metrics are float and unrounded at 13 px" {
	const face = testFace();
	assert face >= 0;
	const glyphA = glyphIndex(face, "A".code);
	assert glyphA > 0;
	const advance = glyphAdvance(face, glyphA, 13.0);
	assert advance > 0.0;
	assert advance != Math.floor(advance);
	const metrics = faceMetrics(face, 13.0);
	assert metrics.ascent > 0.0;
	assert metrics.descent > 0.0;
}

test "kerning reads the GPOS pair adjustment Inter carries instead of a kern table" {
	const face = testFace();
	const left = glyphIndex(face, "A".code);
	const kern = glyphKern(face, left, glyphIndex(face, "V".code), 13.0);
	const unitsPerPixel: float32 = (2048.0 / 13.0) as float32;
	assert Math.abs(kern * unitsPerPixel + 140.0) < 0.01;
}

test "a pair the kern feature does not list is not kerned" {
	const face = testFace();
	const h = glyphIndex(face, "H".code);
	assert glyphKern(face, h, h, 13.0) == 0.0;
}

function decorationInUnits(face: int32, unitsPerEm: float32): DecorationMetrics {
	const m = decorationMetrics(face, 13.0);
	const units: float32 = unitsPerEm / 13.0;
	return {
		underlineTop: m.underlineTop * units,
		underlineThickness: m.underlineThickness * units,
		strikethroughTop: m.strikethroughTop * units,
		strikethroughThickness: m.strikethroughThickness * units,
	};
}

function near(actual: float32, expected: float32): boolean {
	return Math.abs(actual - expected) < 0.01;
}

test "decoration metrics read post and OS/2 when both tables are sound" {
	const d = decorationInUnits(testFace(), 2048.0);
	assert near(d.underlineTop, 348.0);
	assert near(d.underlineThickness, 140.0);
	assert near(d.strikethroughTop, -671.0);
	assert near(d.strikethroughThickness, 140.0);
}

test "zeroed decoration tables fall back to the ex height the x glyph measures" {
	const face = try loadFace("tests/fonts/zeroedDecorations.ttf") catch -1;
	assert face >= 0;
	const d = decorationInUnits(face, 2048.0);
	const thickness: float32 = (0.15 * 1118.0) as float32;
	assert near(d.underlineThickness, thickness);
	assert near(d.underlineTop, thickness);
	assert near(d.strikethroughThickness, thickness);
	assert near(d.strikethroughTop, -(1118.0 + thickness) * 0.5);
}

test "a zero thickness keeps the table's position and estimates from the ascent" {
	const face = try loadFace("tests/fonts/zeroThickness.ttf") catch -1;
	assert face >= 0;
	const d = decorationInUnits(face, 2048.0);
	const thickness: float32 = (0.15 * 0.75 * 0.75 * 1984.0) as float32;
	assert near(d.underlineTop, 348.0);
	assert near(d.underlineThickness, thickness);
	assert near(d.strikethroughTop, -671.0);
	assert near(d.strikethroughThickness, thickness);
}

function spriteFaceOfTest(): int32 {
	return try spriteFace(testFace()) catch -1;
}

test "the sprite range table is sorted, disjoint and dense, and its ids fit a glyph key" {
	assert spriteTableFault() == 0;
	assert spriteCount() > 0;
	assert spriteCount() < 65536;
	for (let id = 1; id <= spriteCount(); id++) {
		const codepoint = spriteCodepoint(id);
		assert codepoint != 0;
		assert spriteIndex(codepoint) == id;
	}
	assert spriteCodepoint(0) == 0;
	assert spriteCodepoint(spriteCount() + 1) == 0;
}

test "a sprite face has glyph 0 outside the range table and one unique id inside it" {
	const sprite = spriteFaceOfTest();
	assert sprite >= 0;
	assert isSpriteFace(sprite);
	assert !isSpriteFace(testFace());
	assert glyphIndex(sprite, "A".code) == 0;
	assert glyphIndex(sprite, 0x24FF) == 0;
	assert glyphIndex(sprite, 0x2800 + 0x100) == 0;
	assert glyphIndex(sprite, 0x2588) == spriteIndex(0x2588);
	assert glyphIndex(sprite, 0x2588) != glyphIndex(sprite, 0x2589);
	assert glyphIndex(sprite, 0x2800) != glyphIndex(sprite, 0x28FF);
}

test "a sprite face is made from a loaded plain face only" {
	const noBase = spriteFace(1000000);
	assert !noBase.ok;
	if (!noBase.ok) { assert noBase.error == FaceError.NoBaseFace; }
	const again = spriteFace(spriteFaceOfTest());
	assert !again.ok;
	if (!again.ok) { assert again.error == FaceError.NoBaseFace; }
}

test "a sprite advance is the widest ASCII advance of its base, unkerned and unemboldened" {
	const face = testFace();
	const sprite = spriteFaceOfTest();
	let widest: float32 = 0.0;
	for (let c = 32; c < 127; c++) {
		const a = glyphAdvance(face, glyphIndex(face, c), 14.0);
		if (a > widest) { widest = a; }
	}
	const block = glyphIndex(sprite, 0x2588);
	assert Math.abs(glyphAdvance(sprite, block, 14.0) - widest) < 0.001;
	assert glyphAdvance(sprite, 0, 14.0) == 0.0;
	assert glyphKern(sprite, block, block, 14.0) == 0.0;
	const bold = try syntheticFace(face, true, false) catch -1;
	const boldSprite = try spriteFace(bold) catch -1;
	assert boldSprite >= 0;
	const boldBlock = glyphIndex(boldSprite, 0x2588);
	assert Math.abs(glyphAdvance(boldSprite, boldBlock, 14.0) - widest) < 0.001;
}

test "a sprite cell is Ghostty's Metrics.calc over the base face at the device size" {
	const face = testFace();
	const sprite = spriteFaceOfTest();
	const sizes: float32[] = [13.0, 14.0, 16.0, 17.5, 21.0, 33.3];
	for (const size of sizes) {
		const cell = spriteCell(sprite, size);
		let widest: float32 = 0.0;
		for (let c = 32; c < 127; c++) {
			const a = glyphAdvance(face, glyphIndex(face, c), size);
			if (a > widest) { widest = a; }
		}
		const m = faceMetrics(face, size);
		const height: float64 = (m.ascent + m.descent + m.lineGap) as float64;
		const cellHeight: float64 = Math.floor(height + 0.5);
		const baseline: float64 = Math.floor(
			(m.lineGap as float64) / 2.0 + (m.descent as float64) -
				(cellHeight - height) / 2.0 + 0.5,
		);
		const ink = decorationMetrics(face, size).underlineThickness as float64;
		assert cell.width == (Math.floor(widest as float64 + 0.5) as int32);
		assert cell.height == (cellHeight as int32);
		assert cell.topToBaseline == ((cellHeight - baseline) as int32);
		assert cell.lineThickness == Math.max(1, Math.ceil(ink) as int32);
	}
	const at14 = spriteCell(sprite, 14.0);
	assert at14.width == 14 && at14.height == 17;
	assert at14.topToBaseline == 14 && at14.lineThickness == 1;
}

test "a sprite cell asked of a plain face or a size nobody can draw is empty" {
	const plain = spriteCell(testFace(), 14.0);
	assert plain.width == 0 && plain.height == 0;
	const none = spriteCell(spriteFaceOfTest(), 0.0);
	assert none.width == 0 && none.height == 0;
}
