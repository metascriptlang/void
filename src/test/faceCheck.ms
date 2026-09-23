import {
	loadFace,
	glyphIndex,
	glyphAdvance,
	glyphKern,
	faceMetrics,
} from "../void2d/face";

let loadedFace: int32 = -1;

function testFace(): int32 {
	if (loadedFace < 0) { loadedFace = loadFace("assets/font.ttf"); }
	return loadedFace;
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
