import {
	roundedRectDistance, coverageFromDistance, aaWidthForAffine,
	smoothUnionDistance, wavyUnderlineDistance,
	erfApprox, shadowCoverage, insetShadowCoverage,
} from "../void2d/sdf";
import { trs2d } from "../void2d/types";
import {
	insideRoundedRect, pixelCoverage, maxCoverageError, SUPERSAMPLES,
	blurredPixelCoverage, maxShadowError,
	devicePixelCoverage, affineEdgeBound, trueEdgeSlope,
} from "../../tests/oracle/coverage";
import { approx } from "./helpers";

test "the oracle is a square when the radius is zero" {
	assert insideRoundedRect(0.0, 0.0, 10.0, 6.0, 0.0);
	assert insideRoundedRect(9.9, 5.9, 10.0, 6.0, 0.0);
	assert !insideRoundedRect(10.1, 0.0, 10.0, 6.0, 0.0);
	assert !insideRoundedRect(0.0, 6.1, 10.0, 6.0, 0.0);
}

test "the oracle rounds the corners it is asked to round" {
	assert insideRoundedRect(9.9, 5.9, 10.0, 6.0, 0.0);
	assert !insideRoundedRect(9.9, 5.9, 10.0, 6.0, 4.0);
	assert insideRoundedRect(6.0, 2.0, 10.0, 6.0, 4.0);
}

test "a radius past the half extent is clamped, not turned into a lens" {
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

test "the distance function is zero on the edge and signed the way the name says" {
	assert approx(roundedRectDistance(10.0, 0.0, 10.0, 6.0, 0.0), 0.0);
	assert roundedRectDistance(0.0, 0.0, 10.0, 6.0, 0.0) < 0.0;
	assert roundedRectDistance(12.0, 0.0, 10.0, 6.0, 0.0) > 0.0;
	assert approx(roundedRectDistance(12.0, 0.0, 10.0, 6.0, 0.0), 2.0);
}

test "a corner's distance is measured to the arc, not to the box" {
	const s: float32 = 2.8284271;
	const d: float32 = roundedRectDistance(6.0 + s, 2.0 + s, 10.0, 6.0, 4.0);
	assert approx(d, 0.0);
}

test "coverage from distance is a half on the edge, and saturates either side" {
	assert approx(coverageFromDistance(0.0, 1.0), 0.5);
	assert coverageFromDistance(-1.0, 1.0) == 1.0;
	assert coverageFromDistance(1.0, 1.0) == 0.0;
}

test "a zero antialiasing width is a hard edge, not a divide by zero" {
	assert coverageFromDistance(-0.001, 0.0) == 1.0;
	assert coverageFromDistance(0.001, 0.0) == 0.0;
}

test "the antialiasing width is one device pixel in local units" {
	assert approx(aaWidthForAffine(1.0, 0.0, 0.0, 1.0), 1.0);
	assert approx(aaWidthForAffine(2.0, 0.0, 0.0, 2.0), 0.5);
	const r: float32 = 0.7071068;
	assert approx(aaWidthForAffine(r, r, -r, r), 1.0);
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
	assert approx(wavyUnderlineDistance(0.0, 0.0, height, thickness), -1.0);
	assert approx(wavyUnderlineDistance(peakX, 1.6, height, thickness), -1.0);
	assert wavyUnderlineDistance(peakX, 0.0, height, thickness) > 0.0;
}

test "analytic coverage equals true area across a straight edge" {
	const cxs: Vec<float32> = [9.0, 9.25, 9.5, 9.75, 10.0, 10.25, 10.5, 10.75, 11.0];
	const cys: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
	let analytic: Vec<float32> = new Array(0);
	for (let i: int32 = 0; i < (cxs.length as int32); i++) {
		const d: float32 = roundedRectDistance(cxs[i], cys[i], 10.0, 6.0, 0.0);
		analytic.push(coverageFromDistance(d, 1.0));
	}
	const worst: float32 = maxCoverageError(analytic, cxs, cys, 10.0, 6.0, 0.0);
	console.log(`coverage oracle: straight edge, worst error ${worst}`);
	assert worst <= 0.001;
}

test "analytic coverage tracks true area around a rounded corner within 0.06" {
	const cxs: Vec<float32> = [7.0, 7.5, 8.0, 8.5, 9.0, 9.5];
	const cys: Vec<float32> = [3.0, 3.5, 4.0, 4.5, 5.0, 5.5];
	let analytic: Vec<float32> = new Array(0);
	for (let i: int32 = 0; i < (cxs.length as int32); i++) {
		const d: float32 = roundedRectDistance(cxs[i], cys[i], 10.0, 6.0, 4.0);
		analytic.push(coverageFromDistance(d, 1.0));
	}
	const worst: float32 = maxCoverageError(analytic, cxs, cys, 10.0, 6.0, 4.0);
	console.log(`coverage oracle: rounded corner, worst error ${worst}`);
	assert worst <= 0.06;
}

test "the oracle rejects a coverage curve that is wrong" {
	const cxs: Vec<float32> = [9.5, 10.0, 10.5];
	const cys: Vec<float32> = [0.0, 0.0, 0.0];
	let analytic: Vec<float32> = new Array(0);
	for (let i: int32 = 0; i < (cxs.length as int32); i++) {
		const d: float32 = roundedRectDistance(cxs[i], cys[i], 10.0, 6.0, 0.0);
		analytic.push(coverageFromDistance(d, 0.0));
	}
	const worst: float32 = maxCoverageError(analytic, cxs, cys, 10.0, 6.0, 0.0);
	console.log(`coverage oracle: hard edge against true area, worst error ${worst}`);
	assert worst > 0.06;
}

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
	let curve: Vec<float32> = new Array(0);
	for (let i: int32 = 0; i < (cxs.length as int32); i++) {
		const d: float32 = roundedRectDistance(cxs[i], cys[i], 10.0, 6.0, 0.0);
		curve.push(smoothstepCoverage(d, 1.0));
	}
	const worst: float32 = maxCoverageError(curve, cxs, cys, 10.0, 6.0, 0.0);
	console.log(`coverage oracle: smoothstep on a straight edge, worst error ${worst}`);
	assert worst > 0.09;
	assert worst > 0.001;
}


test "the error function is odd, saturates, and lands on erf(1)" {
	assert approx(erfApprox(0.0), 0.0);
	assert erfApprox(3.0) > 0.9999;
	assert erfApprox(-3.0) < -0.9999;
	assert Math.abs((erfApprox(1.0) - 0.8427008) as float64) < 0.001;
	assert approx(erfApprox(-0.7), -erfApprox(0.7));
}

function shadowPoints(): Vec<float32> {
	return [9.5, -1.0,  10.5, -1.0,  11.5, -1.0,  12.5, -1.0,  13.5, -1.0,
	        11.5, -6.5,  12.5, -5.5,  11.0, -7.5,   2.0, -1.0,  20.0, -1.0];
}

test "the shadow integral matches the kernel-integral truth within 0.02" {
	const pts: Vec<float32> = shadowPoints();
	let analytic: Vec<float32> = new Array(0);
	let pxs: Vec<float32> = new Array(0);
	let pys: Vec<float32> = new Array(0);
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
	let wrong: Vec<float32> = new Array(0);
	let pxs: Vec<float32> = new Array(0);
	let pys: Vec<float32> = new Array(0);
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
	const a: float32 = shadowCoverage(11.5, -4.5, 10.0, 6.0, 5.0, 2.0, 3.0, 6.0, 1.5, -1.0, 2.0, 1.0);
	const b: float32 = shadowCoverage(-11.5, -4.5, 10.0, 6.0, 2.0, 5.0, 6.0, 3.0, -1.5, -1.0, 2.0, 1.0);
	assert approx(a, b);
	assert a != shadowCoverage(11.5, -4.5, 10.0, 6.0, 5.0, 6.0, 3.0, 2.0, 1.5, -1.0, 2.0, 1.0);
}

test "the inset shadow is the clipped complement of the blur" {
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


const BOX_W: float32 = 60.0;
const BOX_H: float32 = 40.0;
const BOX_X: float32 = 10.3;
const BOX_Y: float32 = 7.7;
const SWEEP_HALF: float32 = 2.5;
const SWEEP_STEP: float32 = 0.125;

function edgeSweepWorst(
	a: float32, b: float32, c: float32, d: float32,
	exact: boolean,
): float32 {
	const det: float32 = a * d - b * c;
	const ia: float32 = d / det;
	const ib: float32 = -b / det;
	const ic: float32 = -c / det;
	const id: float32 = a / det;
	const hx: float32 = BOX_W * 0.5;
	const hy: float32 = BOX_H * 0.5;
	let worst: float32 = 0.0;
	for (let edge: int32 = 0; edge < 2; edge++) {
		const mx: float32 = edge == 0 ? BOX_W : BOX_W * 0.5;
		const my: float32 = edge == 0 ? BOX_H * 0.5 : BOX_H;
		const midX: float32 = BOX_X + a * mx + c * my;
		const midY: float32 = BOX_Y + b * mx + d * my;
		const aa: float32 = exact
			? 1.0 / trueEdgeSlope(a, b, c, d, edge)
			: aaWidthForAffine(a, b, c, d);
		const steps: int32 = (SWEEP_HALF / SWEEP_STEP) as int32;
		for (let iy: int32 = -steps; iy <= steps; iy++) {
			for (let ix: int32 = -steps; ix <= steps; ix++) {
				const cx: float32 = midX + (ix as float32) * SWEEP_STEP;
				const cy: float32 = midY + (iy as float32) * SWEEP_STEP;
				const lx: float32 = ia * (cx - BOX_X) + ic * (cy - BOX_Y);
				const ly: float32 = ib * (cx - BOX_X) + id * (cy - BOX_Y);
				const distance: float32 = roundedRectDistance(lx - hx, ly - hy, hx, hy, 0.0);
				const analytic: float32 = coverageFromDistance(distance, aa);
				const truth: float32 = devicePixelCoverage(
					cx, cy, a, b, c, d, BOX_X, BOX_Y, BOX_W, BOX_H, 0.0,
				);
				const e: float32 = analytic > truth ? analytic - truth : truth - analytic;
				if (e > worst) { worst = e; }
			}
		}
	}
	return worst;
}

function caseBounds(sx: float32, sy: float32, rotation: float32): Vec<float32> {
	const t = trs2d(0.0, 0.0, rotation, sx, sy);
	const predicted: float32 = affineEdgeBound(t.a, t.b, t.c, t.d);
	const worst: float32 = edgeSweepWorst(t.a, t.b, t.c, t.d, false);
	const control: float32 = edgeSweepWorst(t.a, t.b, t.c, t.d, true);
	console.log(
		`coverage oracle: scale ${sx}x${sy} rot ${rotation}, predicted ${predicted}`
		+ ` worst ${worst} exact-slope control ${control}`,
	);
	return [predicted, worst, control];
}

test "a uniform scale has a zero predicted bound and a worst error under 0.001" {
	const r: Vec<float32> = caseBounds(2.0, 2.0, 0.0);
	assert r[0] == 0.0;
	assert r[1] <= 0.001;
	assert r[2] <= 0.001;
}

test "the one-width error at 2:1 is within 0.005 of the predicted bound and not above it" {
	const r: Vec<float32> = caseBounds(2.0, 1.0, 0.0);
	assert approx(r[0], 0.1464466);
	assert Math.abs((r[1] - r[0]) as float64) < 0.005;
	assert r[1] <= r[0] + 0.0001;
	assert r[2] <= 0.06;
}

test "the one-width error at 3:1 is within 0.005 of the predicted bound and not above it" {
	const r: Vec<float32> = caseBounds(3.0, 1.0, 0.0);
	assert approx(r[0], 0.2113249);
	assert Math.abs((r[1] - r[0]) as float64) < 0.005;
	assert r[1] <= r[0] + 0.0001;
	assert r[2] <= 0.06;
}

test "the one-width error at 1:3 is within 0.005 of the predicted bound and not above it" {
	const r: Vec<float32> = caseBounds(1.0, 3.0, 0.0);
	assert approx(r[0], 0.2113249);
	assert Math.abs((r[1] - r[0]) as float64) < 0.005;
	assert r[1] <= r[0] + 0.0001;
	assert r[2] <= 0.06;
}

test "the one-width error at 4:1 rotated 20 degrees stays under the predicted bound within 0.03" {
	const r: Vec<float32> = caseBounds(4.0, 1.0, 0.34906584);
	assert approx(r[0], 0.25);
	assert r[1] <= r[0];
	assert r[0] - r[1] < 0.03;
	assert r[2] <= 0.06;
}
