// T0 + T3 — the coverage oracle's own properties, and the analytic antialiasing judged
// against it (docs/TESTING.md "T3", tests/PENDING.md `oracle:coverage`).
//
// Order matters here and is deliberate: this lands BEFORE the SDF reaches a pixel. Wiring the
// judge after the thing it judges is how P1 ended up with filter goldens arranged so that
// none of them could see the defect they were meant to cover - the captures simply froze
// whatever the code did. Here the bound is stated first, and the shader has to meet it.

import {
	roundedRectDistance, coverageFromDistance, aaWidthForAffine,
	smoothUnionDistance, wavyUnderlineDistance,
} from "../void2d/sdf";
import {
	insideRoundedRect, pixelCoverage, maxCoverageError, SUPERSAMPLES,
} from "../../tests/oracle/coverage";
import { approx } from "./helpers";

// ===== the oracle's own geometry, before it is trusted to judge anything =====

test "the oracle is a square when the radius is zero" {
	assert insideRoundedRect(0.0, 0.0, 10.0, 6.0, 0.0);
	assert insideRoundedRect(9.9, 5.9, 10.0, 6.0, 0.0);
	assert !insideRoundedRect(10.1, 0.0, 10.0, 6.0, 0.0);
	assert !insideRoundedRect(0.0, 6.1, 10.0, 6.0, 0.0);
}

test "the oracle rounds the corners it is asked to round" {
	// (9.9, 5.9) is inside the square and outside a box with a 4-unit corner.
	assert insideRoundedRect(9.9, 5.9, 10.0, 6.0, 0.0);
	assert !insideRoundedRect(9.9, 5.9, 10.0, 6.0, 4.0);
	// The corner centre itself is always inside.
	assert insideRoundedRect(6.0, 2.0, 10.0, 6.0, 4.0);
}

test "a radius past the half extent is clamped, not turned into a lens" {
	// r = 100 on a 10x6 half-extent box clamps to 6, giving a stadium. Its waist is full
	// width; a lens would have pinched it.
	assert insideRoundedRect(9.9, 0.0, 10.0, 6.0, 100.0);
	assert !insideRoundedRect(10.1, 0.0, 10.0, 6.0, 100.0);
}

test "the oracle's sampling grid is the 16x16 the doc states" {
	assert SUPERSAMPLES == 16;
}

test "coverage is one deep inside and zero well outside" {
	assert pixelCoverage(0.0, 0.0, 10.0, 6.0, 0.0) == 1.0;
	assert pixelCoverage(20.0, 0.0, 10.0, 6.0, 0.0) == 0.0;
}

// The property the whole tier rests on: a straight edge through a pixel centre covers half of
// it. Get this wrong by half a sample and every antialiased edge in the renderer is biased.
test "a straight edge through a pixel centre covers exactly half of it" {
	assert pixelCoverage(10.0, 0.0, 10.0, 6.0, 0.0) == 0.5;
	assert pixelCoverage(0.0, 6.0, 10.0, 6.0, 0.0) == 0.5;
}

test "coverage falls monotonically as a pixel crosses an edge" {
	let previous: float32 = 1.1;
	for (let i: int32 = 0; i <= 10; i++) {
		const cx: float32 = 9.0 + (i as float32) * 0.2;
		const c: float32 = pixelCoverage(cx, 0.0, 10.0, 6.0, 0.0);
		assert c <= previous;
		previous = c;
	}
	assert previous < 0.5;
}

// ===== the analytic coverage, judged against the oracle =====

test "the distance function is zero on the edge and signed the way the name says" {
	assert approx(roundedRectDistance(10.0, 0.0, 10.0, 6.0, 0.0) as float64, 0.0);
	assert roundedRectDistance(0.0, 0.0, 10.0, 6.0, 0.0) < 0.0;
	assert roundedRectDistance(12.0, 0.0, 10.0, 6.0, 0.0) > 0.0;
	assert approx(roundedRectDistance(12.0, 0.0, 10.0, 6.0, 0.0) as float64, 2.0);
}

test "a corner's distance is measured to the arc, not to the box" {
	// At 45 degrees out from the corner centre of a 4-unit radius, the distance to the arc is
	// the radial distance minus the radius.
	const s: float32 = 2.8284271;   // 4 / sqrt(2) * 1.0, the 45-degree offset for radius 4
	const d: float32 = roundedRectDistance(6.0 + s, 2.0 + s, 10.0, 6.0, 4.0);
	assert approx(d as float64, 0.0);
}

test "coverage from distance is a half on the edge, and saturates either side" {
	assert approx(coverageFromDistance(0.0, 1.0) as float64, 0.5);
	assert coverageFromDistance(-1.0, 1.0) == 1.0;
	assert coverageFromDistance(1.0, 1.0) == 0.0;
}

test "a zero antialiasing width is a hard edge, not a divide by zero" {
	assert coverageFromDistance(-0.001, 0.0) == 1.0;
	assert coverageFromDistance(0.001, 0.0) == 0.0;
}

test "the antialiasing width is one device pixel in local units" {
	assert approx(aaWidthForAffine(1.0, 0.0, 0.0, 1.0) as float64, 1.0);
	assert approx(aaWidthForAffine(2.0, 0.0, 0.0, 2.0) as float64, 0.5);
	// A rotation is not a scale, so it must not change the width.
	const r: float32 = 0.7071068;
	assert approx(aaWidthForAffine(r, r, -r, r) as float64, 1.0);
}
test "selection gloop is a hard union outside its radius and fillets a join inside it" {
	assert smoothUnionDistance(-4.0, 8.0, 8.0) == -4.0;
	assert smoothUnionDistance(8.0, -4.0, 8.0) == -4.0;
	assert smoothUnionDistance(1.0, 1.0, 8.0) == -1.0;
	assert smoothUnionDistance(-2.0, 3.0, 8.0) == smoothUnionDistance(3.0, -2.0, 8.0);
}

test "wavy underline distance follows the sine centreline" {
	const height: float32 = 6.0;
	const thickness: float32 = 2.0;
	const peakX: float32 = 4.5;
	assert approx(wavyUnderlineDistance(0.0, 0.0, height, thickness) as float64, -1.0);
	assert approx(wavyUnderlineDistance(peakX, 1.6, height, thickness) as float64, -1.0);
	assert wavyUnderlineDistance(peakX, 0.0, height, thickness) > 0.0;
}


// THE BOUND, stated before the shader exists, and tightened to what was measured once the
// curve was corrected. A straight edge is the case where analytic coverage can be EXACT, so
// the bound is exact: linear coverage is the true area of a pixel cut by a straight edge, not
// an approximation of it.
test "analytic coverage equals true area across a straight edge" {
	const cxs: Vec<float32> = [9.0, 9.25, 9.5, 9.75, 10.0, 10.25, 10.5, 10.75, 11.0];
	const cys: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
	const analytic: Vec<float32> = new Array(0);
	for (let i: int32 = 0; i < (cxs.length as int32); i++) {
		const d: float32 = roundedRectDistance(cxs[i], cys[i], 10.0, 6.0, 0.0);
		analytic.push(coverageFromDistance(d, 1.0));
	}
	const worst: float32 = maxCoverageError(analytic, cxs, cys, 10.0, 6.0, 0.0);
	console.log(`coverage oracle: straight edge, worst error ${worst}`);
	assert worst <= 0.001;
}

// A corner is where a distance-based approximation is genuinely weak: the true coverage of a
// curved edge is not a function of distance alone. 0.0425 is what it measures; 0.06 is the
// bound, stated rather than discovered, so a commit that makes it worse has something to fail.
test "analytic coverage tracks true area around a rounded corner within 0.06" {
	const cxs: Vec<float32> = [7.0, 7.5, 8.0, 8.5, 9.0, 9.5];
	const cys: Vec<float32> = [3.0, 3.5, 4.0, 4.5, 5.0, 5.5];
	const analytic: Vec<float32> = new Array(0);
	for (let i: int32 = 0; i < (cxs.length as int32); i++) {
		const d: float32 = roundedRectDistance(cxs[i], cys[i], 10.0, 6.0, 4.0);
		analytic.push(coverageFromDistance(d, 1.0));
	}
	const worst: float32 = maxCoverageError(analytic, cxs, cys, 10.0, 6.0, 4.0);
	console.log(`coverage oracle: rounded corner, worst error ${worst}`);
	assert worst <= 0.06;
}

// The oracle has to be able to convict. Feed it a deliberately wrong analytic curve - a hard
// edge where the truth is a gradient - and require the error to exceed the bound the tests
// above accept. Without this, both bounds could be met by an oracle that returns nothing.
test "the oracle rejects a coverage curve that is wrong" {
	const cxs: Vec<float32> = [9.5, 10.0, 10.5];
	const cys: Vec<float32> = [0.0, 0.0, 0.0];
	const analytic: Vec<float32> = new Array(0);
	for (let i: int32 = 0; i < (cxs.length as int32); i++) {
		const d: float32 = roundedRectDistance(cxs[i], cys[i], 10.0, 6.0, 0.0);
		analytic.push(coverageFromDistance(d, 0.0));
	}
	const worst: float32 = maxCoverageError(analytic, cxs, cys, 10.0, 6.0, 0.0);
	console.log(`coverage oracle: hard edge against true area, worst error ${worst}`);
	assert worst > 0.06;
}

// The finding this file produced, kept as a test so it cannot be undone by someone reaching
// for the reflex. `smoothstep` is what a distance-field renderer usually uses for coverage,
// and it is WRONG here: the true area of a pixel cut by a straight edge is linear in the
// edge's distance, and smoothstep is an S-curve through the same two endpoints. It overshoots
// by 0.09375 at the quarter points - 24 levels out of 255, on every antialiased edge.
//
// The oracle convicted it before a single pixel was drawn, which is the whole reason this
// tier was wired before the SDF reached the shader instead of after.
function smoothstepCoverage(d: float32, aa: float32): float32 {
	if (aa <= 0.0) { return d <= 0.0 ? 1.0 : 0.0; }
	const t: float32 = (0.5 - d / aa) as float32;
	if (t <= 0.0) { return 0.0; }
	if (t >= 1.0) { return 1.0; }
	return (t * t * (3.0 - 2.0 * t)) as float32;
}

test "smoothstep would fail the straight-edge bound that linear coverage meets exactly" {
	const cxs: Vec<float32> = [9.0, 9.25, 9.5, 9.75, 10.0, 10.25, 10.5, 10.75, 11.0];
	const cys: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
	const curve: Vec<float32> = new Array(0);
	for (let i: int32 = 0; i < (cxs.length as int32); i++) {
		const d: float32 = roundedRectDistance(cxs[i], cys[i], 10.0, 6.0, 0.0);
		curve.push(smoothstepCoverage(d, 1.0));
	}
	const worst: float32 = maxCoverageError(curve, cxs, cys, 10.0, 6.0, 0.0);
	console.log(`coverage oracle: smoothstep on a straight edge, worst error ${worst}`);
	assert worst > 0.09;
	assert worst > 0.001;
}

// ===== the shadow half (tests/PENDING.md `oracle:coverage-shadow`) =====
//
// Same discipline as the geometry half above: the bound is stated, the analytic curve is
// `sdf.ms`'s shadow integral, and the truth is the kernel-integral Riemann sum in
// tests/oracle/coverage.ms, which shares no code with it.

import { erfApprox, shadowCoverage, insetShadowCoverage } from "../void2d/sdf";
import { blurredPixelCoverage, maxShadowError } from "../../tests/oracle/coverage";

test "the error function is odd, saturates, and lands on erf(1)" {
	assert approx(erfApprox(0.0) as float64, 0.0);
	assert erfApprox(3.0) > 0.9999;
	assert erfApprox(-3.0) < -0.9999;
	// erf(1) = 0.8427008; the rational form's polynomial error is far below this bound.
	assert Math.abs((erfApprox(1.0) - 0.8427008) as float64) < 0.001;
	assert approx(erfApprox(-0.7) as float64, -(erfApprox(0.7) as float64));
}

// The shadow scene every test below judges: half extents 10x6, radius 3, sigma 2, the caster
// offset by (1.5, -1) - so the shadow's own rect spans x in [-8.5, 11.5], y in [-7, 5] and
// its soft edges and corners sit away from the sample points' grid.
function shadowPoints(): Vec<float32> {
	return [9.5, -1.0,  10.5, -1.0,  11.5, -1.0,  12.5, -1.0,  13.5, -1.0,
	        11.5, -6.5,  12.5, -5.5,  11.0, -7.5,   2.0, -1.0,  20.0, -1.0];
}

test "the shadow integral matches the kernel-integral truth within 0.02" {
	const pts: Vec<float32> = shadowPoints();
	const analytic: Vec<float32> = new Array(0);
	const pxs: Vec<float32> = new Array(0);
	const pys: Vec<float32> = new Array(0);
	for (let i: int32 = 0; i + 1 < (pts.length as int32); i = i + 2) {
		analytic.push(shadowCoverage(pts[i], pts[i + 1], 10.0, 6.0, 3.0, 3.0, 3.0, 3.0, 1.5, -1.0, 2.0, 1.0));
		pxs.push(pts[i]);
		pys.push(pts[i + 1]);
	}
	const worst: float32 = maxShadowError(analytic, pxs, pys, 10.0, 6.0, 3.0, 1.5, -1.0, 2.0);
	console.log(`coverage oracle: shadow integral, worst error ${worst}`);
	assert worst <= 0.02;
}

test "the oracle convicts a shadow computed with the wrong blur" {
	const pts: Vec<float32> = shadowPoints();
	const wrong: Vec<float32> = new Array(0);
	const pxs: Vec<float32> = new Array(0);
	const pys: Vec<float32> = new Array(0);
	for (let i: int32 = 0; i + 1 < (pts.length as int32); i = i + 2) {
		wrong.push(shadowCoverage(pts[i], pts[i + 1], 10.0, 6.0, 3.0, 3.0, 3.0, 3.0, 1.5, -1.0, 3.0, 1.0));
		pxs.push(pts[i]);
		pys.push(pts[i + 1]);
	}
	const worst: float32 = maxShadowError(wrong, pxs, pys, 10.0, 6.0, 3.0, 1.5, -1.0, 2.0);
	console.log(`coverage oracle: sigma 3 against truth sigma 2, worst error ${worst}`);
	assert worst > 0.02;
}

test "per-corner radii mirror exactly under x negation" {
	// The asymmetric scanline's left and right chords swap roles when the box is mirrored,
	// which is exact algebra - a drift here means the two sides are not the two chords.
	const a: float32 = shadowCoverage(11.5, -4.5, 10.0, 6.0, 5.0, 2.0, 3.0, 6.0, 1.5, -1.0, 2.0, 1.0);
	const b: float32 = shadowCoverage(-11.5, -4.5, 10.0, 6.0, 2.0, 5.0, 6.0, 3.0, -1.5, -1.0, 2.0, 1.0);
	assert approx(a as float64, b as float64);
	assert a != shadowCoverage(11.5, -4.5, 10.0, 6.0, 5.0, 6.0, 3.0, 2.0, 1.5, -1.0, 2.0, 1.0);
}

test "the inset shadow is the clipped complement of the blur" {
	// Truth composed from the oracle's own pieces, both definition-level: the blurred hole is
	// the kernel integral, the clip is the supersampled area fraction.
	const pts: Vec<float32> = [1.0, 1.0,  8.0, 0.0,  9.5, 0.0,  10.5, 0.0,  8.5, 4.5,  0.0, 5.5];
	for (let i: int32 = 0; i + 1 < (pts.length as int32); i = i + 2) {
		const px: float32 = pts[i];
		const py: float32 = pts[i + 1];
		const analytic: float32 = insetShadowCoverage(px, py, 10.0, 6.0, 3.0, 3.0, 3.0, 3.0, 2.0, 1.0);
		const truth: float32 = (1.0 - blurredPixelCoverage(px, py, 10.0, 6.0, 3.0, 0.0, 0.0, 2.0))
			* pixelCoverage(px, py, 10.0, 6.0, 3.0);
		const d: float32 = analytic - truth;
		const e: float32 = d < 0.0 ? -d : d;
		if (e > 0.02) {
			console.log(`coverage oracle: inset at (${px},${py}), analytic ${analytic} truth ${truth}`);
		}
		assert e <= 0.02;
	}
}
