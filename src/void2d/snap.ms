// The pixel-snapping rules (VOID2D.md "P2 - Lands", after GPUI.md "Pixel snapping rules").
//
// Applied by the emitter when the node's world transform is AXIS-ALIGNED: a rotated or skewed
// card has no device-pixel grid to snap to, and snapping it would be a different shape rather
// than a crisper one. Under an axis-aligned affine the device position of a local point is
// one multiply and one add per axis, so the rules are pure arithmetic here and the T0 suite
// states them as numbers at three DPIs - which is what the phase's exit criterion asks.
//
// Why edges snap at all, given the analytic AA: the coverage ramp is CENTRED on the edge and
// one device pixel wide, so an edge that lands exactly on a pixel boundary leaves the pixel
// centres half a ramp away - full coverage inside, none outside, a crisp edge with no
// half-covered seam. A fractional edge puts that seam half-way into a pixel row instead.

// Round half TOWARD ZERO, each edge independently - GPUI's `snap_bounds`. Half toward zero
// (and not away) because two adjacent boxes sharing a fractional edge must round it to the
// SAME integer whichever side each box is on, and any deterministic rule gives them that;
// toward zero is GPUI's choice and halves never grow a box by a pixel on their own.
export function snapEdge(v: float32): float32 {
	if (v >= 0.0) {
		return Math.ceil((v - 0.5) as float64) as float32;
	}
	return -Math.ceil(((-v) - 0.5) as float64) as float32;
}

// A stroke width in DEVICE pixels: zero stays zero, anything else rounds with a floor of one
// device pixel - GPUI's `snap_stroke`. The floor is the whole point: a hairline asked at
// 0.4 px at DPI 1.0 is 1 px, not invisible, and a 1 px border at DPI 1.25 (1.25 device px)
// stays distinguishable from a 2 px one instead of both rounding up.
export function snapStroke(widthDevice: float32): float32 {
	if (widthDevice <= 0.0) { return 0.0; }
	const r: float32 = Math.floor((widthDevice + 0.5) as float64) as float32;
	return r < 1.0 ? 1.0 : r;
}

// True when the transform's linear part maps local axes onto device axes, positively - the
// precondition for every rule in this file. A mirror or a rotation disqualifies it.
export function axisAligned(a: float32, b: float32, c: float32, d: float32): boolean {
	return b == 0.0 && c == 0.0 && a > 0.0 && d > 0.0;
}

// Snap one box's device edges. In/out through local units, because that is what the emitter
// holds; the device round-trip is exact for an axis-aligned affine. `size` may shrink or grow
// by up to one device pixel as each edge moves to its own integer.
export function snapBoxEdges(
	lx0: float32, ly0: float32, sx: float32, sy: float32,
	a: float32, tx: float32, d: float32, ty: float32,
): Vec<float32> {
	const x0d: float32 = snapEdge(a * lx0 + tx);
	const y0d: float32 = snapEdge(d * ly0 + ty);
	const x1d: float32 = snapEdge(a * (lx0 + sx) + tx);
	const y1d: float32 = snapEdge(d * (ly0 + sy) + ty);
	return [
		(x0d - tx) / a, (y0d - ty) / d,
		(x1d - tx) / a - ((x0d - tx) / a), (y1d - ty) / d - ((y0d - ty) / d),
	];
}
