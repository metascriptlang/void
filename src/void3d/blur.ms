// Heaps' h3d.pass.Blur: a separable blur whose taps fall between texels, so the linear filter
// reads two texels per tap. This file holds its kernel; docs/VOID3D.md "Ambient occlusion".

// Blur's radius, gain, linear and quality, defaulting as `new Blur()` does.
export struct BlurSettings {
	radius: float32;
	gain: float32;
	linear: float32;
	quality: float32;
}

export function defaults(this typeof BlurSettings): BlurSettings {
	return { radius: 1.0, gain: 1.0, linear: 0.0, quality: 1.0 };
}

// The most taps one side of the blur program reads, the centre one included.
export const BLUR_MAX_TAPS: int32 = 16;

// Tap i's weight and how far it sits from the centre, in pixels per tap index.
export struct BlurKernel {
	values: Vec<float32>;
	offsets: Vec<float32>;
}

function gauss(x: float64, s: float64): float64 {
	if (s <= 0.0) { return x == 0.0 ? 1.0 : 0.0; }
	const sq: float64 = s * s;
	const p: float64 = Math.pow(2.718281828459, -(x * x) / (2.0 * sq));
	return p / Math.sqrt(2.0 * Math.PI * sq);
}

function lerp(a: float64, b: float64, t: float64): float64 {
	return a + (b - a) * t;
}

// Blur.calcValues, in float64 as Heaps computes it.
export function blurKernel(settings: BlurSettings): BlurKernel {
	let values: Vec<float64> = [];
	let offsets: Vec<float64> = [];
	const radius: float64 = settings.radius;
	const quality: float64 = settings.quality;
	const qadj: float64 = (quality < 0.0 ? 0.0 : quality > 1.0 ? 1.0 : quality) * 0.7 + 0.3;
	const spread: float64 = radius - 1.0 > 1.0 ? radius - 1.0 : 1.0;
	const width: int32 = radius > 0.0 ? Math.ceil(spread * qadj / 2.0) as int32 : 0;
	const sigma: float64 = Math.sqrt(radius);
	let total: float64 = 0.0;
	for (let i = 0; i < width + 1; i++) {
		const i1: float64 = (i * 2) as float64;
		const i2: float64 = i == 0 ? 0.0 : (i * 2 - 1) as float64;
		const g1: float64 = gauss(i1, sigma);
		const g2: float64 = gauss(i2, sigma);
		const g: float64 = g1 + g2;
		values.push(g);
		offsets.push(i == 0 ? 0.0 : (g1 * i1 + g2 * i2) / (g * (i as float64) * Math.sqrt(qadj)));
		total += g;
		if (i > 0) { total += g; }
	}
	const least: float64 = values[0] * (0.01 / qadj);
	while (values.length > 2) {
		const last: float64 = values[values.length - 1];
		if (last > least) { break; }
		total -= last * 2.0;
		values.pop();
	}
	total /= settings.gain;
	for (let i = 0; i < values.length; i++) { values[i] = values[i] / total; }
	const linear: float64 = settings.linear;
	if (linear > 0.0) {
		const flat: float64 = settings.gain / ((values.length * 2 - 1) as float64);
		for (let i = 0; i < values.length; i++) {
			values[i] = lerp(values[i], flat, linear);
			const at: float64 = i as float64;
			const spaced: float64 = i == 0 ? 0.0 : (at * 2.0 - 0.5) / (at * qadj);
			offsets[i] = lerp(offsets[i], spaced, linear);
		}
	}
	let kernel: BlurKernel = { values: [], offsets: [] };
	for (let i = 0; i < values.length; i++) {
		kernel.values.push(values[i] as float32);
		kernel.offsets.push(offsets[i] as float32);
	}
	return kernel;
}

// Blur.getKernelSize.
export function blurKernelSize(settings: BlurSettings): int32 {
	if (settings.radius <= 0.0) { return 0; }
	return (blurKernel(settings).values.length as int32) * 2 - 1;
}

// Finite settings, a gain above 0 and a kernel the program holds; a radius of 0 copies.
export function valid(this settings: BlurSettings): boolean {
	return Number.isFinite(settings.radius) && settings.radius >= 0.0 &&
		Number.isFinite(settings.gain) && settings.gain > 0.0 &&
		Number.isFinite(settings.linear) && Number.isFinite(settings.quality) &&
		blurKernel(settings).values.length <= BLUR_MAX_TAPS;
}
