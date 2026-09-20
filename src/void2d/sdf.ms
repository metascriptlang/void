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
