// T3 — the coverage oracle against a CAPTURE (docs/TESTING.md "T3", VOID2D.md P2 "Tests").
//
// `src/test/coverageOracleCheck.ms` judges the arithmetic in `src/void2d/sdf.ms`. It cannot
// see the shader, and the shader is a second copy of that arithmetic in GLSL — so until this
// existed, "the antialiasing is correct" was proven for MetaScript and merely *unchanged* for
// the thing that actually draws. That is the shape of the defect that let a squared alpha live
// through all of P1 behind goldens arranged so none could see it.
//
// So: recompute every pixel of `prim/aaRotatedBox` from GEOMETRY — the rotation and the size
// in `tests/golden/table.ms`, 16x16 supersampled, with no distance field anywhere — and
// compare against the coverage the captured pixels imply. No GPU and no window: it reads the
// committed PNG, which is what ships.
//
// The two reference colours are READ OUT OF THE CAPTURE rather than predicted: the background
// at a corner, full coverage at the box's centre. Predicting them would fold the colour pack,
// the blend factors and the clear value into a test that is about coverage, and a failure
// would then name the wrong thing.

import { env } from "std/process";
import {
	AA_BOX_W, AA_BOX_H, AA_BOX_X, AA_BOX_Y, AA_BOX_PIVOT_X, AA_BOX_PIVOT_Y,
	AA_BOX_ROTATION,
} from "../golden/table";
import { devicePixelCoverage, coverageFromPixel } from "./coverage";
import { voidPngLoad, voidPngWidth, voidPngHeight, voidPngPixel } from "../golden/pngio.h";

// Two bounds, because a straight edge and a sharp corner are two different claims and one
// number would hide the weaker of them behind the stronger. Both are MEASURED and then
// stated; neither was chosen to make a reading pass.
//
// THE ROTATED EDGE IS NOT EXACT, AND THAT IS NOT A DEFECT IN THE RAMP. T0 measures the linear
// coverage against true area at 0 error — for an edge parallel to the pixel grid, where the
// area really is linear in the distance. Under a rotation the true area of a unit pixel cut
// by a line is piecewise QUADRATIC, and a linear ramp through the same endpoints deviates
// from it by up to (sqrt(2)/2 - 1/2)^2 = 0.043 at 45 degrees. Measured on this capture at 37
// degrees: worst 0.050, which is that 0.043 plus the 0.005 that 8 bits can express.
//
// The shape is the evidence that it is the geometry and not a half-pixel offset, which would
// look identical in magnitude: the error is ANTISYMMETRIC about half coverage — mean +0.034
// where true coverage is 0.25, -0.034 where it is 0.75, and 0.000 at 0.5 and over the whole
// edge. An offset would be one-signed. That profile was measured before this bound was set.
//
// 0.06 therefore passes the geometry and still convicts what this tier exists to catch, and
// that conviction was RUN rather than argued: the shader's curve was swapped to smoothstep,
// the headers regenerated, the caches evicted and the scene recaptured, and this file read
// 0.0734 and failed. Linear reads 0.0502. The bound sits between two measured numbers, which
// is a narrower margin than the T0 case has - so a change that moves the edge number toward
// 0.06 is a finding to explain, not a bound to raise.
//
// Worth keeping from that control: smoothstep's CORNER error was 0.095, BETTER than linear's
// 0.1875. One averaged number over both regions would have moved in smoothstep's favour.
const EDGE_BOUND: float32 = 0.06;

// At a SHARP corner one distance cannot describe a pixel cut by two perpendicular edges.
// Measured 0.1875 here; it is where the rounded radii of the box side table will improve it,
// so the number is printed and pinned rather than averaged into the edge's.
const CORNER_BOUND: float32 = 0.20;

// How far from a corner, in local units, a pixel counts as a corner pixel. Two device pixels:
// the region where the two edges' coverage overlaps within one pixel footprint.
const CORNER_BAND: float32 = 2.0;

const SLOT: int32 = 0;

function pixel(x: int32, y: int32, channel: int32): int32 {
	return voidPngPixel(SLOT, x, y, channel);
}

// The committed golden by default - what ships is what the gate judges. `VOID_AA_CAPTURE`
// points it at a fresh capture instead, which is the order a golden is allowed to move in:
// capture, let the oracle say the antialiasing is true area, and only then promote. Judging
// a golden that was promoted first would be judging a decision already taken.
const GOLDEN_PATH: string = "tests/golden/d3d11/prim/aaRotatedBox.png";

function run(): int32 {
	const override: string = env.get("VOID_AA_CAPTURE");
	const path: string = override.equals("") ? GOLDEN_PATH : override;
	if (voidPngLoad(SLOT, path) == 0) {
		console.log(`FAIL coverage oracle: cannot read ${path}`);
		return 1;
	}
	const w: int32 = voidPngWidth(SLOT);
	const h: int32 = voidPngHeight(SLOT);

	const bgR: int32 = pixel(2, 2, 0);
	const bgG: int32 = pixel(2, 2, 1);
	const bgB: int32 = pixel(2, 2, 2);
	const fillR: int32 = pixel(AA_BOX_X as int32, AA_BOX_Y as int32, 0);
	const fillG: int32 = pixel(AA_BOX_X as int32, AA_BOX_Y as int32, 1);
	const fillB: int32 = pixel(AA_BOX_X as int32, AA_BOX_Y as int32, 2);

	// The world affine the scene was drawn with, and the device point the box's local (0,0)
	// lands on. `at(x,y)` places the node's ORIGIN, and the local rect starts at -pivot, so
	// the box's own corner is the pivot mapped through the rotation and subtracted.
	const co: float32 = Math.cos(AA_BOX_ROTATION as float64) as float32;
	const si: float32 = Math.sin(AA_BOX_ROTATION as float64) as float32;
	const a: float32 = co;
	const b: float32 = si;
	const c: float32 = -si;
	const d: float32 = co;
	const ox: float32 = a * (-AA_BOX_PIVOT_X) + c * (-AA_BOX_PIVOT_Y) + AA_BOX_X;
	const oy: float32 = b * (-AA_BOX_PIVOT_X) + d * (-AA_BOX_PIVOT_Y) + AA_BOX_Y;

	const det: float32 = a * d - b * c;
	const ia: float32 = d / det;
	const ib: float32 = -b / det;
	const ic: float32 = -c / det;
	const id: float32 = a / det;
	const hx: float32 = AA_BOX_W * 0.5;
	const hy: float32 = AA_BOX_H * 0.5;

	let worstEdge: float32 = 0.0;
	let worstEdgeX: int32 = -1;
	let worstEdgeY: int32 = -1;
	let worstCorner: float32 = 0.0;
	let worstCornerX: int32 = -1;
	let worstCornerY: int32 = -1;
	let edgePixels: int32 = 0;
	let cornerPixels: int32 = 0;
	let unjudgeable: int32 = 0;

	for (let y: int32 = 0; y < h; y++) {
		for (let x: int32 = 0; x < w; x++) {
			const truth: float32 = devicePixelCoverage(
				(x as float32) + 0.5, (y as float32) + 0.5,
				a, b, c, d, ox, oy, AA_BOX_W, AA_BOX_H, 0.0);
			// Only the edge is under test. An interior pixel says the fill is the fill and an
			// exterior one says the background is the background; neither can tell a linear
			// ramp from an S-curve, which is the whole question here.
			if (truth <= 0.0 || truth >= 1.0) { continue; }
			const observed: float32 = coverageFromPixel(
				pixel(x, y, 0), pixel(x, y, 1), pixel(x, y, 2),
				bgR, bgG, bgB, fillR, fillG, fillB);
			if (observed < 0.0) { unjudgeable = unjudgeable + 1; continue; }
			const delta: float32 = observed - truth;
			const error: float32 = delta < 0.0 ? -delta : delta;

			const dx: float32 = (x as float32) + 0.5 - ox;
			const dy: float32 = (y as float32) + 0.5 - oy;
			const lx: float32 = ia * dx + ic * dy - hx;
			const ly: float32 = ib * dx + id * dy - hy;
			const ax: float32 = lx < 0.0 ? -lx : lx;
			const ay: float32 = ly < 0.0 ? -ly : ly;
			if (ax > hx - CORNER_BAND && ay > hy - CORNER_BAND) {
				cornerPixels = cornerPixels + 1;
				if (error > worstCorner) {
					worstCorner = error; worstCornerX = x; worstCornerY = y;
				}
			} else {
				edgePixels = edgePixels + 1;
				if (error > worstEdge) {
					worstEdge = error; worstEdgeX = x; worstEdgeY = y;
				}
			}
		}
	}

	console.log(`coverage oracle: capture prim/aaRotatedBox,`
		+ ` ${edgePixels} straight-edge pixels worst ${worstEdge} at (${worstEdgeX},${worstEdgeY}),`
		+ ` ${cornerPixels} corner pixels worst ${worstCorner} at (${worstCornerX},${worstCornerY})`);

	// An oracle that cannot convict is not an oracle. A scene whose edge never falls inside a
	// pixel has nothing to judge, and would pass while measuring nothing.
	if (edgePixels < 200) {
		console.log(`FAIL coverage oracle: only ${edgePixels} edge pixels - the scene cannot convict`);
		return 1;
	}
	if (unjudgeable > 0) {
		console.log(`FAIL coverage oracle: ${unjudgeable} edge pixels where no channel separates fill from background`);
		return 1;
	}
	if (worstEdge > EDGE_BOUND) {
		console.log(`FAIL coverage oracle: straight-edge error ${worstEdge} exceeds ${EDGE_BOUND}`
			+ ` - the shader's coverage ramp disagrees with true area`);
		return 1;
	}
	if (worstCorner > CORNER_BOUND) {
		console.log(`FAIL coverage oracle: corner error ${worstCorner} exceeds ${CORNER_BOUND}`);
		return 1;
	}
	// The corner bound is loose enough that it must not be allowed to pass by accident: a
	// capture whose corners are perfect is a capture of a scene with no sharp corner in it,
	// and this scene has four.
	if (cornerPixels < 8) {
		console.log(`FAIL coverage oracle: only ${cornerPixels} corner pixels - the scene has four corners`);
		return 1;
	}
	console.log(`PASS coverage oracle: the capture's antialiasing is true area`
		+ ` within ${EDGE_BOUND} along edges and ${CORNER_BOUND} at sharp corners`);
	return 0;
}

process.exit(run());
