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

export const SHADOW_GRID: int32 = 160;

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

export function trueEdgeSlope(
	a: float32, b: float32, c: float32, d: float32,
	edge: int32,
): float32 {
	const det: float32 = a * d - b * c;
	const adet: float32 = det < 0.0 ? -det : det;
	const colX: float32 = Math.sqrt((a * a + b * b) as float64) as float32;
	const colY: float32 = Math.sqrt((c * c + d * d) as float64) as float32;
	if (edge == 0) { return adet / colY; }
	return adet / colX;
}

export function usedEdgeSlope(a: float32, b: float32, c: float32, d: float32): float32 {
	const colX: float32 = Math.sqrt((a * a + b * b) as float64) as float32;
	const colY: float32 = Math.sqrt((c * c + d * d) as float64) as float32;
	return Math.sqrt((colX * colY) as float64) as float32;
}

export function affineEdgeBound(a: float32, b: float32, c: float32, d: float32): float32 {
	const used: float32 = usedEdgeSlope(a, b, c, d);
	let worst: float32 = 0.0;
	for (let edge: int32 = 0; edge < 2; edge++) {
		const s: float32 = trueEdgeSlope(a, b, c, d, edge);
		const lo: float32 = s < used ? s : used;
		const hi: float32 = s < used ? used : s;
		const e: float32 = 0.5 * (1.0 - lo / hi);
		if (e > worst) { worst = e; }
	}
	return worst;
}

export function isCornerPixel(
	cx: float32,
	cy: float32,
	a: float32, b: float32, c: float32, d: float32,
	ox: float32, oy: float32,
	w: float32, h: float32,
	band: float32,
): boolean {
	const det: float32 = a * d - b * c;
	const dx: float32 = cx - ox;
	const dy: float32 = cy - oy;
	const lx: float32 = (d * dx - c * dy) / det - w * 0.5;
	const ly: float32 = (a * dy - b * dx) / det - h * 0.5;
	const ax: float32 = lx < 0.0 ? -lx : lx;
	const ay: float32 = ly < 0.0 ? -ly : ly;
	return (w * 0.5 - ax) * trueEdgeSlope(a, b, c, d, 0) < band
		&& (h * 0.5 - ay) * trueEdgeSlope(a, b, c, d, 1) < band;
}

export function deviceBoxExtent(
	a: float32, b: float32, c: float32, d: float32,
	ox: float32, oy: float32,
	w: float32, h: float32,
	pad: int32,
): Vec<int32> {
	const xs: Vec<float32> = [ox, ox + a * w, ox + c * h, ox + a * w + c * h];
	const ys: Vec<float32> = [oy, oy + b * w, oy + d * h, oy + b * w + d * h];
	let x0: float32 = xs[0];
	let x1: float32 = xs[0];
	let y0: float32 = ys[0];
	let y1: float32 = ys[0];
	for (let i: int32 = 1; i < 4; i++) {
		if (xs[i] < x0) { x0 = xs[i]; }
		if (xs[i] > x1) { x1 = xs[i]; }
		if (ys[i] < y0) { y0 = ys[i]; }
		if (ys[i] > y1) { y1 = ys[i]; }
	}
	return [
		(Math.floor(x0 as float64) as int32) - pad, (Math.floor(y0 as float64) as int32) - pad,
		(Math.ceil(x1 as float64) as int32) + pad, (Math.ceil(y1 as float64) as int32) + pad,
	];
}
