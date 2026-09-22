// T0 — the snapping rules as numbers at three DPIs (VOID2D.md "P2 - Tests"). The phase's
// exit criterion is stated per device pixel, so the arithmetic is pinned here where it is
// exact, and the display-list tier pins that the emitter actually applies it.

import { snapEdge, snapStroke, snapBoxEdges, axisAligned } from "../void2d/snap";
import { approx } from "./helpers";

test "an edge rounds half toward zero, each edge independently" {
	assert snapEdge(2.0) == 2.0;
	assert snapEdge(2.4) == 2.0;
	assert snapEdge(2.5) == 2.0;
	assert snapEdge(2.6) == 3.0;
	assert snapEdge(-2.5) == -2.0;
	assert snapEdge(-2.6) == -3.0;
}

test "a stroke width is zero or at least one device pixel" {
	assert snapStroke(0.0) == 0.0;
	assert snapStroke(-1.0) == 0.0;
	assert snapStroke(0.4) == 1.0;
	assert snapStroke(1.0) == 1.0;
	assert snapStroke(1.24) == 1.0;
	assert snapStroke(1.26) == 1.0;
	assert snapStroke(1.5) == 2.0;
	assert snapStroke(2.4) == 2.0;
}

test "only a positive axis-aligned affine snaps" {
	assert axisAligned(1.0, 0.0, 0.0, 1.0);
	assert axisAligned(1.25, 0.0, 0.0, 1.5);
	assert !axisAligned(0.0, 1.0, -1.0, 0.0);
	assert !axisAligned(1.0, 0.1, 0.0, 1.0);
	assert !axisAligned(-1.0, 0.0, 0.0, 1.0);
}

// THE EXIT CRITERION, as arithmetic: at DPI 1.0, 1.25 and 1.5 a 1-logical-px border is
// exactly one device pixel, a zero border is zero, and the two halves of a 7-px split share
// one integer edge - which is what "touch with no gap" is, mechanically.
test "a 1px border is one device pixel at three DPIs, and zero stays zero" {
	const dpis: Vec<float32> = [1.0, 1.25, 1.5];
	for (let i: int32 = 0; i < 3; i++) {
		const dpi: float32 = dpis[i];
		// Asked as one DEVICE pixel (1/dpi logical): exactly one, not rounded away or up.
		assert snapStroke((1.0 / dpi) * dpi) == 1.0;
		assert snapStroke(0.0 * dpi) == 0.0;
		// A 1-logical-px border is honest about the device grid it lands on: 1.25 device
		// rounds to 1, 1.5 rounds to 2 - not silently 1 everywhere.
		if (dpi < 1.4) {
			assert snapStroke(1.0 * dpi) == 1.0;
		} else {
			assert snapStroke(1.0 * dpi) == 2.0;
		}
	}
}

test "the halves of a 7px split share one integer edge at three DPIs" {
	const dpis: Vec<float32> = [1.0, 1.25, 1.5];
	for (let i: int32 = 0; i < 3; i++) {
		const dpi: float32 = dpis[i];
		for (let k: int32 = 0; k < 6; k++) {
			const fraction: float32 = 0.5 + (k as float32) * 0.07;
			const shared: float32 = 16.0 + 7.0 * fraction;
			const firstRight = snapEdge(shared * dpi) / dpi;
			const secondLeft = snapEdge(shared * dpi) / dpi;
			assert firstRight == secondLeft;
			// Complementary widths: min + max = 7 in device pixels, never 6 with a gap
			// or 8 with an overlap.
			const near: float32 = snapEdge(0.0);
			const split: float32 = snapEdge(7.0 * fraction * dpi);
			const rest: float32 = snapEdge(7.0 * dpi) - split;
			assert rest > 0.0;
		}
	}
}

test "a box's device edges land on integers through the affine" {
	// DPI 1.25, a fractional logical box: every device edge integral after the round trip.
	const snapped = snapBoxEdges(10.3, 20.6, 40.4, 28.8, 1.25, 3.0, 1.25, -2.0);
	const a: float32 = 1.25;
	const tx: float32 = 3.0;
	const d: float32 = 1.25;
	const ty: float32 = -2.0;
	for (let i: int32 = 0; i < 2; i++) {
		const x0d: float32 = snapped[0] * a + tx;
		const y0d: float32 = snapped[1] * d + ty;
		const x1d: float32 = (snapped[0] + snapped[2]) * a + tx;
		const y1d: float32 = (snapped[1] + snapped[3]) * d + ty;
		assert approx(x0d as float64, Math.round(x0d as float64));
		assert approx(y0d as float64, Math.round(y0d as float64));
		assert approx(x1d as float64, Math.round(x1d as float64));
		assert approx(y1d as float64, Math.round(y1d as float64));
		assert snapped[2] > 0.0;
		assert snapped[3] > 0.0;
	}
}
