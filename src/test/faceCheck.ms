import {
	FaceError,
	loadFace,
	syntheticFace,
	glyphIndex,
	glyphAdvance,
	glyphKern,
	faceMetrics,
	decorationMetrics,
	DecorationMetrics,
} from "../void2d/face";

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
	const unitsPerPixel: float32 = 2048.0 / 13.0;
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
	const thickness: float32 = 0.15 * 1118.0;
	assert near(d.underlineThickness, thickness);
	assert near(d.underlineTop, thickness);
	assert near(d.strikethroughThickness, thickness);
	assert near(d.strikethroughTop, -(1118.0 + thickness) * 0.5);
}

test "a zero thickness keeps the table's position and estimates from the ascent" {
	const face = try loadFace("tests/fonts/zeroThickness.ttf") catch -1;
	assert face >= 0;
	const d = decorationInUnits(face, 2048.0);
	const thickness: float32 = 0.15 * 0.75 * 0.75 * 1984.0;
	assert near(d.underlineTop, 348.0);
	assert near(d.underlineThickness, thickness);
	assert near(d.strikethroughTop, -671.0);
	assert near(d.strikethroughThickness, thickness);
}
