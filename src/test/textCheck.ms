import { buildGlyphMesh } from "../void2d/text";
import { approx } from "./helpers";

test "buildGlyphMesh empty produces empty array" {
	const out = buildGlyphMesh([]);
	assert out.length == 0;
}

test "buildGlyphMesh one glyph produces 6 vertices" {
	const glyphs: float32[] = [
		0.0, 0.0, 0.0, 0.0,  10.0, 10.0, 1.0, 1.0,
	];
	const out = buildGlyphMesh(glyphs);
	assert out.length == 48;
}

test "buildGlyphMesh two glyphs produces 12 vertices" {
	const glyphs: float32[] = [
		0.0, 0.0, 0.0, 0.0,  10.0, 10.0, 0.5, 0.5,
		10.0, 0.0, 0.5, 0.0,  20.0, 10.0, 1.0, 0.5,
	];
	const out = buildGlyphMesh(glyphs);
	assert out.length == 96;
}

test "buildGlyphMesh vertex colors are white" {
	const glyphs: float32[] = [
		0.0, 0.0, 0.0, 0.0,  10.0, 10.0, 1.0, 1.0,
	];
	const out = buildGlyphMesh(glyphs);
	assert approx(out[4], 1.0);
	assert approx(out[5], 1.0);
	assert approx(out[6], 1.0);
	assert approx(out[7], 1.0);
}
