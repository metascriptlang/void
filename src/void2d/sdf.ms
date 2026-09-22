// The signed distance functions the UI pipeline's fragment stage evaluates, written once here
// as arithmetic and mirrored in `shader2d.glsl`.
//
// They are in MetaScript rather than only in GLSL because a distance function is the kind of
// thing that is checked by reasoning until it is wrong. Here it is T0, and
// `tests/oracle/coverage.ms` supersamples the *geometry* independently to say whether the
// analytic coverage these produce is actually right - which a golden cannot say, because a
// golden only reports that the AA has not changed since last week.
//
// Local space, per GPUI.md:35-39: distances are evaluated against the node's own rectangle
// and the antialiasing width is derived from the scale, so a rotated or scaled card keeps its
// corner radius and its edge softness instead of having them baked in at record time.

// Distance from a point to a rounded rectangle centred on the origin, negative inside.
// `hx`/`hy` are half extents; `r` is clamped to the largest radius the box can hold, because
// a radius past that is not a rounded rect at all and silently produces a lens shape.
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

// Coverage from a signed distance, over an antialiasing width in the same units. `aa` is one
// device pixel expressed in local units (VOID2D.md "P2 - Lands").
//
// LINEAR, deliberately, and this is the one decision in this file that was measured rather
// than inherited. The reflex here is `smoothstep`, which is what a distance-field renderer
// usually reaches for. The coverage oracle rejected it before a pixel was ever drawn: the
// true area of a pixel cut by a straight edge is LINEAR in the edge's distance from the pixel
// centre, and smoothstep is an S-curve through the same endpoints, so it overshoots by up to
// 0.094 at the quarter points - 24 levels of 255, on every antialiased edge in the renderer.
// Measured, not argued: `src/test/coverageOracleCheck.ms` prints the worst error for both
// curves, and the bound it accepts is tight enough that smoothstep cannot pass it.
//
// The edge is centred on distance 0, so an edge through a pixel centre reads exactly 0.5 -
// which is what the supersampled oracle says too, and the first thing that goes wrong when
// the ramp is written over [0, aa] instead of [-aa/2, +aa/2].
export function coverageFromDistance(d: float32, aa: float32): float32 {
	if (aa <= 0.0) { return d <= 0.0 ? 1.0 : 0.0; }
	const t: float32 = (0.5 - d / aa) as float32;
	if (t <= 0.0) { return 0.0; }
	if (t >= 1.0) { return 1.0; }
	return t;
}

// The antialiasing width for a world transform whose linear part is (a,b,c,d). One device
// pixel across the edge, expressed in the node's local units: a card scaled 2x needs half a
// local unit to cover one device pixel. The scale is the geometric mean of the two axis
// lengths, so a non-uniform scale gets one width rather than a direction-dependent one -
// stated because it is an approximation, not an identity.
export function aaWidthForAffine(a: float32, b: float32, c: float32, d: float32): float32 {
	const sx: float32 = Math.sqrt((a * a + b * b) as float64) as float32;
	const sy: float32 = Math.sqrt((c * c + d * d) as float64) as float32;
	const s: float32 = Math.sqrt((sx * sy) as float64) as float32;
	if (s <= 0.0) { return 0.0; }
	return (1.0 / s) as float32;
}

// ===== the analytic shadow: GPUI's erf integral, ported =====
//
// GPUI (`shaders.wgsl` `fs_shadow`, anchored in GPUI.md:28) computes a Gaussian-blurred
// rounded rect as a closed-form CDF difference along x, sampled at four midpoints along y
// over the kernel's +-3-sigma window clamped to the box's extent. No render target, no
// tessellation, one fragment. The polynomial `erf` and the scanline half-width below are
// GPUI's arithmetic; the one deliberate divergence is the ASYMMETRIC scanline: GPUI's
// `blur_along_x` symmetrises to one half-width chosen by the evaluation point's quadrant,
// which is an approximation the moment the four radii differ, while the true slice of a
// rounded rect at height y has its own left and right chords. This carries a chord per side;
// for uniform radii it is GPUI's function exactly.

// The rational-form error function GPUI uses (`shaders.wgsl:325`). Its polynomial error is
// orders below one 8-bit level, so it is never the term a bound has to worry about.
export function erfApprox(x: float32): float32 {
	const s: float32 = x < 0.0 ? -1.0 : 1.0;
	const a: float32 = x < 0.0 ? -x : x;
	const r1: float32 = 1.0 + (0.278393 + (0.230389 + (0.000972 + 0.078108 * a) * a) * a) * a;
	const r2: float32 = r1 * r1;
	return (s - s / (r2 * r2)) as float32;
}

// The Gaussian pdf, GPUI's `gaussian`.
export function gaussianPdf(x: float32, sigma: float32): float32 {
	const e: float32 = Math.exp(((-(x * x) / (2.0 * sigma * sigma)) as float64)) as float32;
	return (e as float32) / ((Math.sqrt((2.0 * Math.PI) as float64) as float32) * sigma);
}

// The corner radius of the quadrant (px, py) falls in - the same pick the shader's
// `cornerRadius` makes, mirrored here so the oracle can judge it.
export function cornerRadiusAt(
	px: float32, py: float32,
	rTL: float32, rTR: float32, rBR: float32, rBL: float32,
): float32 {
	if (px < 0.0) {
		return py < 0.0 ? rTL : rBL;
	}
	return py < 0.0 ? rTR : rBR;
}

// The half-extent of the box's slice at |y| on one side whose corner radius is `r`: the core
// width plus the chord the circle still covers at that height. GPUI's `curved`, per side.
function scanlineHalf(hx: float32, hy: float32, ay: float32, r: float32): float32 {
	const dy: float32 = ay - (hy - r);
	const under: float32 = r * r - dy * dy;
	const chord: float32 = dy > 0.0 && under > 0.0
		? (Math.sqrt((under) as float64) as float32)
		: r;
	return hx - r + chord;
}

// The coverage of the shadow the box casts, at a point relative to the BOX centre. The blur
// is applied by evaluating the un-offset box's integral at (p - offset), which is the same
// thing GPUI does by offsetting the bounds on the CPU. A non-positive sigma is the hard
// shadow: distance coverage, one antialiasing width, no integral.
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
	// The kernel's +-3-sigma window in y, clamped to the box's extent - GPUI's sample range.
	// The sample variable is the offset from the point, so the scanline sits at (cy - y).
	const low: float32 = cy - hy;
	const high: float32 = cy + hy;
	let start: float32 = -3.0 * sigma;
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

// The inset shadow: the complement of the blurred hole, clipped to the element - which for a
// standalone instance is the same rounded rect. GPUI clips with a 1-pixel `saturate(0.5 - d)`
// in device space; this uses the local-space coverage the rest of the pipeline uses, so the
// oracle judges the same curve the shader draws.
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
