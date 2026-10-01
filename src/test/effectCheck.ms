import { colorMatrixGrayscale, colorMatrixAlphaOnly } from "../void2d/effect";
import { approx } from "./helpers";

test "grayscale amount 0 is identity" {
	const m = colorMatrixGrayscale(0.0);
	assert approx(m.m11, 1.0);
	assert approx(m.m22, 1.0);
	assert approx(m.m33, 1.0);
	assert approx(m.m44, 1.0);
	assert approx(m.m12, 0.0);
}

test "grayscale amount 1 uses Rec.601 luminance weights" {
	const m = colorMatrixGrayscale(1.0);
	assert approx(m.m11, 0.299);
	assert approx(m.m22, 0.587);
	assert approx(m.m33, 0.114);
	assert approx(m.m44, 1.0);
}

test "alphaOnly zeroes RGB keeps alpha scaled" {
	const m = colorMatrixAlphaOnly(1.5);
	assert approx(m.m11, 0.0);
	assert approx(m.m22, 0.0);
	assert approx(m.m33, 0.0);
	assert approx(m.m44, 1.5);
}
