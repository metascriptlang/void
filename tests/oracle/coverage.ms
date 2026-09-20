// T3 — the coverage oracle (docs/TESTING.md "T3", tests/PENDING.md `oracle:coverage`).
//
// Ground truth for antialiasing, computed from GEOMETRY and nothing else: a pixel's coverage
// is the fraction of it that lies inside the shape, found by 16x16 supersampling. It shares
// no code with `src/void2d/sdf.ms`, which is the whole point - an oracle that called the
// thing it judges would agree with it by construction.
//
// This is the only tier that says the antialiasing is *correct*. A golden says it has not
// changed since last week, which is exactly the check that let a squared alpha live through
// all of P1 (docs/REVIEWS.md).
//
// No GPU, no capture, no external tool: the reference is arithmetic, so it runs in every gate
// on every machine.

// Is a point inside a rounded rectangle centred on the origin? Exact geometry, by cases, with
// no distance field anywhere: inside the cross of the two inner rectangles, or within the
// radius of the nearest corner centre.
export function insideRoundedRect(
	px: float32,
	py: float32,
	hx: float32,
	hy: float32,
	r: float32,
): boolean {
	const rMax: float32 = hx < hy ? hx : hy;
	let rr: float32 = r;
	if (rr < 0.0) { rr = 0.0; }
	if (rr > rMax) { rr = rMax; }
	const ax: float32 = px < 0.0 ? -px : px;
	const ay: float32 = py < 0.0 ? -py : py;
	if (ax > hx || ay > hy) { return false; }
	const innerX: float32 = hx - rr;
	const innerY: float32 = hy - rr;
	if (ax <= innerX || ay <= innerY) { return true; }
	const dx: float32 = ax - innerX;
	const dy: float32 = ay - innerY;
	return dx * dx + dy * dy <= rr * rr;
}

export const SUPERSAMPLES: int32 = 16;

// The fraction of the pixel centred at (cx, cy) that lies inside the shape. 16x16 samples on
// a half-offset grid, so the samples are symmetric about the pixel centre and a straight edge
// through that centre reads exactly 0.5 rather than 0.5 plus a half-sample bias.
export function pixelCoverage(
	cx: float32,
	cy: float32,
	hx: float32,
	hy: float32,
	r: float32,
): float32 {
	let hits: int32 = 0;
	const step: float32 = 1.0 / (SUPERSAMPLES as float32);
	for (let sy: int32 = 0; sy < SUPERSAMPLES; sy++) {
		const oy: float32 = ((sy as float32) + 0.5) * step - 0.5;
		for (let sx: int32 = 0; sx < SUPERSAMPLES; sx++) {
			const ox: float32 = ((sx as float32) + 0.5) * step - 0.5;
			if (insideRoundedRect(cx + ox, cy + oy, hx, hy, r)) { hits = hits + 1; }
		}
	}
	return (hits as float32) / ((SUPERSAMPLES * SUPERSAMPLES) as float32);
}

// The largest disagreement between the oracle and an analytic coverage, over a band of pixel
// centres crossing an edge. Returned rather than asserted, so a test can state the bound it
// accepts and print the number it got - a bound nobody prints is a bound nobody checks.
export function maxCoverageError(
	analytic: Vec<float32>,
	cxs: Vec<float32>,
	cys: Vec<float32>,
	hx: float32,
	hy: float32,
	r: float32,
): float32 {
	let worst: float32 = 0.0;
	const n: int32 = analytic.length as int32;
	for (let i: int32 = 0; i < n; i++) {
		const truth: float32 = pixelCoverage(cxs[i], cys[i], hx, hy, r);
		const d: float32 = analytic[i] - truth;
		const e: float32 = d < 0.0 ? -d : d;
		if (e > worst) { worst = e; }
	}
	return worst;
}
