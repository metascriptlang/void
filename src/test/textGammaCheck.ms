import { gammaRatios, correctCoverage, GammaRatios, DEFAULT_TEXT_GAMMA } from "../void2d/textGamma";
import { approx } from "./helpers";

test "gamma 1.8 gives GPUI's ratios, the Windows Terminal row normalised" {
	const g = gammaRatios(DEFAULT_TEXT_GAMMA);
	const norm13: float32 = 65536.0 / (255.0 * 255.0) * 4.0;
	const norm24: float32 = 256.0 / 255.0 * 4.0;
	assert approx(g.r0, 0.1469 / 4.0 * norm13);
	assert approx(g.r1, -0.8911 / 4.0 * norm24);
	assert approx(g.r2, 1.4644 / 4.0 * norm13);
	assert approx(g.r3, -0.3234 / 4.0 * norm24);
}

test "gamma is clamped to the table and rounded to its tenth" {
	const low = gammaRatios(0.5);
	assert low.r0 == 0.0 && low.r1 == 0.0 && low.r2 == 0.0 && low.r3 == 0.0;
	const high = gammaRatios(3.0);
	const top = gammaRatios(2.2);
	assert high.r0 == top.r0 && high.r3 == top.r3;
	const between = gammaRatios(1.85);
	const upper = gammaRatios(1.9);
	assert between.r1 == upper.r1;
}

test "empty and full coverage stay empty and full" {
	const g = gammaRatios(1.8);
	assert correctCoverage(0.0, 1.0, 1.0, 1.0, 1.0, g) == 0.0;
	assert approx(correctCoverage(1.0, 1.0, 1.0, 1.0, 1.0, g), 1.0);
	assert approx(correctCoverage(1.0, 0.0, 0.0, 0.0, 1.0, g), 1.0);
}

test "contrast thickens dark text and leaves bright text alone" {
	const flat: GammaRatios = gammaRatios(1.0);
	assert approx(correctCoverage(0.5, 0.0, 0.0, 0.0, 1.0, flat), 2.0 / 3.0);
	assert approx(correctCoverage(0.5, 1.0, 1.0, 1.0, 1.0, flat), 0.5);
	assert approx(correctCoverage(0.5, 1.0, 1.0, 1.0, 0.0, flat), 0.5);
}

test "gamma correction moves a half-covered edge, differently for light and dark text" {
	const g = gammaRatios(1.8);
	const light = correctCoverage(0.5, 1.0, 1.0, 1.0, 0.0, g);
	const dark = correctCoverage(0.5, 0.0, 0.0, 0.0, 0.0, g);
	assert light != 0.5;
	assert dark != 0.5;
	assert light != dark;
}

test "at GPUI's defaults a half-covered edge of white text becomes 0.69" {
	const edge = correctCoverage(0.5, 1.0, 1.0, 1.0, 1.0, gammaRatios(1.8));
	assert edge > 0.69 && edge < 0.70;
}
