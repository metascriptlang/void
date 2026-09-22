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


// ===== judging a CAPTURE, not just an analytic curve =====
//
// Everything above works in the shape's own space. A capture is in device pixels under an
// affine, so this maps each supersample back through the INVERSE linear part before asking
// the same geometry question. Supersampling stays in device space, because coverage is a
// fraction of a DEVICE pixel and a rotation does not make those two the same thing.
//
// Still no distance field and still no code shared with src/void2d/sdf.ms: this decides
// inside from outside by cases, the way the rest of this file does.

// The fraction of the device pixel centred at (cx, cy) inside a rounded rect whose local
// (0,0) maps to (ox, oy) and whose local axes are the affine (a, b, c, d). The inverse is
// taken here rather than passed, so a caller cannot hand in an inverse that does not match
// the forward transform the scene was drawn with.
export function devicePixelCoverage(
	cx: float32,
	cy: float32,
	a: float32, b: float32, c: float32, d: float32,
	ox: float32, oy: float32,
	w: float32, h: float32,
	r: float32,
): float32 {
	const det: float32 = a * d - b * c;
	if (det == 0.0) { return 0.0; }
	const ia: float32 = d / det;
	const ib: float32 = -b / det;
	const ic: float32 = -c / det;
	const id: float32 = a / det;
	const hx: float32 = w * 0.5;
	const hy: float32 = h * 0.5;
	let hits: int32 = 0;
	const step: float32 = 1.0 / (SUPERSAMPLES as float32);
	for (let sy: int32 = 0; sy < SUPERSAMPLES; sy++) {
		const py: float32 = cy + (((sy as float32) + 0.5) * step - 0.5);
		for (let sx: int32 = 0; sx < SUPERSAMPLES; sx++) {
			const px: float32 = cx + (((sx as float32) + 0.5) * step - 0.5);
			const dx: float32 = px - ox;
			const dy: float32 = py - oy;
			const lx: float32 = ia * dx + ic * dy;
			const ly: float32 = ib * dx + id * dy;
			if (insideRoundedRect(lx - hx, ly - hy, hx, hy, r)) { hits = hits + 1; }
		}
	}
	return (hits as float32) / ((SUPERSAMPLES * SUPERSAMPLES) as float32);
}

// The coverage a captured pixel implies, read off the channel with the widest range between
// background and fill - that channel carries the most levels, so it quantises the answer the
// least. Returns -1 when no channel separates the two colours at all, which is a scene that
// cannot be judged rather than a scene that passed.
export function coverageFromPixel(
	pr: int32, pg: int32, pb: int32,
	bgR: int32, bgG: int32, bgB: int32,
	fillR: int32, fillG: int32, fillB: int32,
): float32 {
	let span: int32 = 0;
	let observed: int32 = 0;
	let base: int32 = 0;
	const spans: Vec<int32> = [fillR - bgR, fillG - bgG, fillB - bgB];
	const values: Vec<int32> = [pr, pg, pb];
	const bases: Vec<int32> = [bgR, bgG, bgB];
	for (let i: int32 = 0; i < 3; i++) {
		const magnitude: int32 = spans[i] < 0 ? -spans[i] : spans[i];
		const best: int32 = span < 0 ? -span : span;
		if (magnitude > best) {
			span = spans[i];
			observed = values[i];
			base = bases[i];
		}
	}
	if (span == 0) { return -1.0; }
	return ((observed - base) as float32) / (span as float32);
}

// ===== the shadow half (tests/PENDING.md `oracle:coverage-shadow`) =====
//
// Truth for a blurred shape is the DEFINITION, not the scanline trick: the coverage of a
// Gaussian-blurred rounded rect is the integral of the kernel over the shape. This
// Riemann-sums that integral on a fine grid, asking only the by-cases inside test above - no
// erf, no chord, no four samples, nothing `src/void2d/sdf.ms` computes with. Uniform radii,
// because the inside test is; the asymmetric-radii claim is judged by its mirror symmetry
// instead, which is exact algebra rather than a sampling bound.

export const SHADOW_GRID: int32 = 160;

// The kernel-integral truth at (px, py) for a uniform-radius rounded rect whose shadow is
// offset by (offsetX, offsetY). The box is sampled on a SHADOW_GRID^2 grid of midpoints over
// its bounding rect; each inside sample contributes its cell's kernel weight.
export function blurredPixelCoverage(
	px: float32, py: float32,
	hx: float32, hy: float32, r: float32,
	offsetX: float32, offsetY: float32,
	sigma: float32,
): float32 {
	const cellX: float32 = (2.0 * hx) / ((SHADOW_GRID) as float32);
	const cellY: float32 = (2.0 * hy) / ((SHADOW_GRID) as float32);
	const cellArea: float32 = cellX * cellY;
	const inv: float32 = 1.0 / (2.0 * sigma * sigma);
	const norm: float32 = 1.0 / ((2.0 * (Math.PI as float64)) as float32) / (sigma * sigma);
	let acc: float32 = 0.0;
	for (let gy: int32 = 0; gy < SHADOW_GRID; gy++) {
		const qy: float32 = -hy + ((gy as float32) + 0.5) * cellY;
		for (let gx: int32 = 0; gx < SHADOW_GRID; gx++) {
			const qx: float32 = -hx + ((gx as float32) + 0.5) * cellX;
			if (!insideRoundedRect(qx, qy, hx, hy, r)) { continue; }
			const dx: float32 = px - (qx + offsetX);
			const dy: float32 = py - (qy + offsetY);
			const e: float32 = Math.exp(((-(dx * dx + dy * dy)) * inv) as float64) as float32;
			acc = acc + e * norm * cellArea;
		}
	}
	return acc;
}

// The largest disagreement between an analytic shadow curve and the kernel-integral truth,
// over the points given. Returned rather than asserted, like `maxCoverageError`, so a test
// states the bound it accepts and prints the number it got.
export function maxShadowError(
	analytic: Vec<float32>,
	pxs: Vec<float32>,
	pys: Vec<float32>,
	hx: float32, hy: float32, r: float32,
	offsetX: float32, offsetY: float32,
	sigma: float32,
): float32 {
	let worst: float32 = 0.0;
	const n: int32 = analytic.length as int32;
	for (let i: int32 = 0; i < n; i++) {
		const truth: float32 = blurredPixelCoverage(pxs[i], pys[i], hx, hy, r, offsetX, offsetY, sigma);
		const d: float32 = analytic[i] - truth;
		const e: float32 = d < 0.0 ? -d : d;
		if (e > worst) { worst = e; }
	}
	return worst;
}
