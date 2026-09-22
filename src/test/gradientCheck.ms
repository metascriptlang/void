import { rgba } from "../void2d/types";
import { GradientSpace, toOklab, fromOklab, mixGradient, dither4x4 } from "../void2d/gradient";

function near(a: float32, b: float32, tolerance: float32): boolean {
	const d: float32 = a > b ? a - b : b - a;
	return d <= tolerance;
}

test "Oklab uses the published red coordinates and round-trips" {
	const red = rgba(1.0, 0.0, 0.0, 0.75);
	const lab = toOklab(red);
	assert near(lab.l, 0.627955, 0.00001);
	assert near(lab.a, 0.224863, 0.00001);
	assert near(lab.b, 0.125846, 0.00001);
	const roundTrip = fromOklab(lab, red.a);
	assert near(roundTrip.r, red.r, 0.00001);
	assert near(roundTrip.g, red.g, 0.00001);
	assert near(roundTrip.b, red.b, 0.00001);
	assert roundTrip.a == red.a;
}

test "Oklab red-blue midpoint differs from an sRGB midpoint" {
	const red = rgba(1.0, 0.0, 0.0, 1.0);
	const blue = rgba(0.0, 0.0, 1.0, 1.0);
	const lab = mixGradient(red, blue, 0.5, GradientSpace.Oklab);
	const srgb = mixGradient(red, blue, 0.5, GradientSpace.Srgb);
	assert near(lab.r, 0.550441, 0.00002);
	assert near(lab.g, 0.325621, 0.00002);
	assert near(lab.b, 0.636501, 0.00002);
	assert srgb.r == 0.5 && srgb.g == 0.0 && srgb.b == 0.5;
}

test "the 4 by 4 dither has zero mean and a two-level-per-channel peak" {
	let sum: float32 = 0.0;
	let low: float32 = 1.0;
	let high: float32 = -1.0;
	for (let y: int32 = 0; y < 4; y++) {
		for (let x: int32 = 0; x < 4; x++) {
			const d: float32 = dither4x4(x, y);
			sum = sum + d;
			if (d < low) { low = d; }
			if (d > high) { high = d; }
		}
	}
	assert near(sum, 0.0, 0.000001);
	assert near(low, -2.0 / 255.0, 0.000001);
	assert near(high, 2.0 / 255.0, 0.000001);
	assert dither4x4(0, 0) == dither4x4(4, 4);
}
