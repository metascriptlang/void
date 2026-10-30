// Mirrored in `shader2d.ms`: change both together.

export function roundedRectDistance(
	px: float32,
	py: float32,
	hx: float32,
	hy: float32,
	r: float32,
): float32 {
	const rMax: float32 = hx < hy ? hx : hy;
	let rr: float32 = r;
	if (rr < 0.0) { rr = 0.0; }
	if (rr > rMax) { rr = rMax; }
	const qx: float32 = (px < 0.0 ? -px : px) - (hx - rr);
	const qy: float32 = (py < 0.0 ? -py : py) - (hy - rr);
	const mx: float32 = qx > 0.0 ? qx : 0.0;
	const my: float32 = qy > 0.0 ? qy : 0.0;
	const outside: float32 = Math.sqrt((mx * mx + my * my) as float64) as float32;
	const inside: float32 = (qx > qy ? qx : qy) < 0.0 ? (qx > qy ? qx : qy) : 0.0;
	return outside + inside - rr;
}

// Linear, not smoothstep: smoothstep overshoots a pixel's true coverage by up to 0.094
// (`src/test/coverageOracleCheck.ms` bounds the error tightly enough to refuse it).
export function coverageFromDistance(d: float32, aa: float32): float32 {
	if (aa <= 0.0) { return d <= 0.0 ? 1.0 : 0.0; }
	const t: float32 = (0.5 - d / aa) as float32;
	if (t <= 0.0) { return 0.0; }
	if (t >= 1.0) { return 1.0; }
	return t;
}

export function aaWidthForAffine(a: float32, b: float32, c: float32, d: float32): float32 {
	const sx: float32 = Math.sqrt((a * a + b * b) as float64) as float32;
	const sy: float32 = Math.sqrt((c * c + d * d) as float64) as float32;
	const s: float32 = Math.sqrt((sx * sy) as float64) as float32;
	if (s <= 0.0) { return 0.0; }
	return (1.0 / s) as float32;
}
export function smoothUnionDistance(a: float32, b: float32, k: float32): float32 {
	if (k <= 0.0) { return a < b ? a : b; }
	let h: float32 = 0.5 + 0.5 * (a - b) / k;
	if (h < 0.0) { h = 0.0; }
	if (h > 1.0) { h = 1.0; }
	return (a * (1.0 - h) + b * h - k * h * (1.0 - h)) as float32;
}

export function wavyUnderlineDistance(
	px: float32,
	py: float32,
	height: float32,
	thickness: float32,
): float32 {
	const frequency: float32 = (2.0 * (Math.PI as float32) * thickness / height) as float32;
	const amplitude: float32 = thickness * 0.8 / height;
	const phase: float32 = px / height * frequency;
	const slope: float32 = (Math.cos(phase as float64) as float32) * amplitude * frequency;
	const wave: float32 = (Math.sin(phase as float64) as float32) * amplitude;
	const distance: float32 = (py / height - wave)
		* height / (Math.sqrt((1.0 + slope * slope) as float64) as float32);
	const ad: float32 = distance < 0.0 ? -distance : distance;
	return (ad - thickness * 0.5) as float32;
}

// The analytic shadow is GPUI's `fs_shadow` (shaders.wgsl): a closed-form erf difference along x
// at four midpoints along y. It diverges in one place: GPUI's `blur_along_x` picks one half-width
// by quadrant, which is wrong once the four radii differ, so this carries a chord per side. For
// uniform radii it is GPUI's function exactly.

// GPUI's polynomial error function (`shaders.wgsl:325`).
export function erfApprox(x: float32): float32 {
	const s: float32 = x < 0.0 ? -1.0 : 1.0;
	const a: float32 = x < 0.0 ? -x : x;
	const r1: float32 = 1.0 + (0.278393 + (0.230389 + (0.000972 + 0.078108 * a) * a) * a) * a;
	const r2: float32 = r1 * r1;
	return (s - s / (r2 * r2)) as float32;
}

export function gaussianPdf(x: float32, sigma: float32): float32 {
	const e: float32 = Math.exp(((-(x * x) / (2.0 * sigma * sigma)) as float64)) as float32;
	return (e as float32) / ((Math.sqrt((2.0 * Math.PI) as float64) as float32) * sigma);
}

export function cornerRadiusAt(
	px: float32, py: float32,
	rTL: float32, rTR: float32, rBR: float32, rBL: float32,
): float32 {
	if (px < 0.0) {
		return py < 0.0 ? rTL : rBL;
	}
	return py < 0.0 ? rTR : rBR;
}

function scanlineHalf(hx: float32, hy: float32, ay: float32, r: float32): float32 {
	const dy: float32 = ay - (hy - r);
	const under: float32 = r * r - dy * dy;
	const chord: float32 = dy > 0.0 && under > 0.0
		? (Math.sqrt((under) as float64) as float32)
		: r;
	return hx - r + chord;
}

export function shadowCoverage(
	px: float32, py: float32,
	hx: float32, hy: float32,
	rTL: float32, rTR: float32, rBR: float32, rBL: float32,
	offsetX: float32, offsetY: float32,
	sigma: float32,
	aa: float32,
): float32 {
	const rMax: float32 = hx < hy ? hx : hy;
	const tl: float32 = rTL < 0.0 ? 0.0 : (rTL > rMax ? rMax : rTL);
	const tr: float32 = rTR < 0.0 ? 0.0 : (rTR > rMax ? rMax : rTR);
	const br: float32 = rBR < 0.0 ? 0.0 : (rBR > rMax ? rMax : rBR);
	const bl: float32 = rBL < 0.0 ? 0.0 : (rBL > rMax ? rMax : rBL);
	const cx: float32 = px - offsetX;
	const cy: float32 = py - offsetY;
	if (sigma <= 0.0) {
		const r: float32 = cornerRadiusAt(cx, cy, tl, tr, br, bl);
		return coverageFromDistance(roundedRectDistance(cx, cy, hx, hy, r), aa);
	}
	const low: float32 = cy - hy;
	const high: float32 = cy + hy;
	let start: float32 = -(3.0 * sigma);
	let end: float32 = 3.0 * sigma;
	if (start < low) { start = low; }
	if (start > high) { start = high; }
	if (end > high) { end = high; }
	if (end < low) { end = low; }
	const stepY: float32 = (end - start) / 4.0;
	const k: float32 = (Math.sqrt((0.5) as float64) as float32) / sigma;
	let acc: float32 = 0.0;
	let y: float32 = start + stepY * 0.5;
	for (let i: int32 = 0; i < 4; i++) {
		const scanY: float32 = cy - y;
		const ay: float32 = scanY < 0.0 ? -scanY : scanY;
		const wL: float32 = scanlineHalf(hx, hy, ay, scanY < 0.0 ? tl : bl);
		const wR: float32 = scanlineHalf(hx, hy, ay, scanY < 0.0 ? tr : br);
		const hi: float32 = 0.5 + 0.5 * erfApprox((cx + wL) * k);
		const lo: float32 = 0.5 + 0.5 * erfApprox((cx - wR) * k);
		acc = acc + (hi - lo) * gaussianPdf(y, sigma) * stepY;
		y = y + stepY;
	}
	return acc;
}

export function insetShadowCoverage(
	px: float32, py: float32,
	hx: float32, hy: float32,
	rTL: float32, rTR: float32, rBR: float32, rBL: float32,
	sigma: float32,
	aa: float32,
): float32 {
	const blur: float32 = shadowCoverage(px, py, hx, hy, rTL, rTR, rBR, rBL, 0.0, 0.0, sigma, aa);
	const r: float32 = cornerRadiusAt(px, py, rTL, rTR, rBR, rBL);
	const clip: float32 = coverageFromDistance(roundedRectDistance(px, py, hx, hy, r), aa);
	return ((1.0 - blur) * clip) as float32;
}
