export const DEFAULT_TEXT_GAMMA: float32 = 1.8;
export const DEFAULT_TEXT_CONTRAST: float32 = 1.0;

export struct GammaRatios {
	r0: float32;
	r1: float32;
	r2: float32;
	r3: float32;
}

const GAMMA_ROWS: float32[] = [
	0.0000, 0.0000, 0.0000, 0.0000,
	0.0166, -0.0807, 0.2227, -0.0751,
	0.0350, -0.1760, 0.4325, -0.1370,
	0.0543, -0.2821, 0.6302, -0.1876,
	0.0739, -0.3963, 0.8167, -0.2287,
	0.0933, -0.5161, 0.9926, -0.2616,
	0.1121, -0.6395, 1.1588, -0.2877,
	0.1300, -0.7649, 1.3159, -0.3080,
	0.1469, -0.8911, 1.4644, -0.3234,
	0.1627, -1.0170, 1.6051, -0.3347,
	0.1773, -1.1420, 1.7385, -0.3426,
	0.1908, -1.2652, 1.8650, -0.3476,
	0.2031, -1.3864, 1.9851, -0.3501,
];

export function gammaRatios(gamma: float32): GammaRatios {
	const norm13: float32 = ((65536.0 / (255.0 * 255.0)) * 4.0) as float32;
	const norm24: float32 = ((256.0 / 255.0) * 4.0) as float32;
	const tenths: int32 = Math.floor(gamma * 10.0 + 0.5) as int32;
	const row: int32 = (tenths < 10 ? 10 : (tenths > 22 ? 22 : tenths)) - 10;
	const quarter: float32 = 0.25;
	return {
		r0: GAMMA_ROWS[row * 4] * quarter * norm13,
		r1: GAMMA_ROWS[row * 4 + 1] * quarter * norm24,
		r2: GAMMA_ROWS[row * 4 + 2] * quarter * norm13,
		r3: GAMMA_ROWS[row * 4 + 3] * quarter * norm24,
	};
}

function saturate(v: float32): float32 {
	if (v < 0.0) { return 0.0; }
	if (v > 1.0) { return 1.0; }
	return v;
}

export function correctCoverage(
	sample: float32,
	r: float32,
	g: float32,
	b: float32,
	contrast: float32,
	ratios: GammaRatios,
): float32 {
	const one: float32 = 1.0;
	const lumaR: float32 = 0.30;
	const lumaG: float32 = 0.59;
	const lumaB: float32 = 0.11;
	const four: float32 = 4.0;
	const knee: float32 = 0.75;
	const brightness: float32 = r * lumaR + g * lumaG + b * lumaB;
	const k: float32 = contrast * saturate(four * (knee - brightness));
	const a: float32 = sample * (k + one) / (sample * k + one);
	const slope: float32 = ratios.r0 * brightness + ratios.r1;
	const correction: float32 = slope * a + (ratios.r2 * brightness + ratios.r3);
	return a + a * (one - a) * correction;
}
