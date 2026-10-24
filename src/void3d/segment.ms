// Port of h3d.col.Seg: the distance from a point to a segment.

import { Vec3 } from "../math/math3d";
import { Wide3, wide, wideSub, wideAdd, wideScaled, wideDot, finiteVec } from "./colliderMath";

export struct Segment3D {
	p1: Vec3;
	p2: Vec3;
}

export enum SegmentError { NonFinite, ZeroLength }

function distanceSquaredWide(a: Wide3, b: Wide3): float64 {
	const d: Wide3 = wideSub(a, b);
	return wideDot(d, d);
}

// Seg.hx:16-24. Heaps divides by the segment's squared length, so a zero-length segment gives
// 0/0 and every distance NaN; here it is ZeroLength.
export function distanceSquared(this seg: Segment3D, point: Vec3): Result<float64, SegmentError> {
	if (!finiteVec(seg.p1) || !finiteVec(seg.p2) || !finiteVec(point)) {
		return Result.err(SegmentError.NonFinite);
	}
	const p1: Wide3 = wide(seg.p1);
	const p2: Wide3 = wide(seg.p2);
	const p: Wide3 = wide(point);
	const axis: Wide3 = wideSub(p2, p1);
	const lengthSquared: float64 = wideDot(axis, axis);
	if (lengthSquared == 0.0) { return Result.err(SegmentError.ZeroLength); }
	const t: float64 = wideDot(wideSub(p, p1), axis) / lengthSquared;
	if (t < 0.0) { return Result.ok(distanceSquaredWide(p, p1)); }
	if (t > 1.0) { return Result.ok(distanceSquaredWide(p, p2)); }
	return Result.ok(distanceSquaredWide(p, wideAdd(p1, wideScaled(axis, t))));
}

export function distance(this seg: Segment3D, point: Vec3): Result<float64, SegmentError> {
	const squared: float64 = try seg.distanceSquared(point);
	return Result.ok(Math.sqrt(squared));
}
