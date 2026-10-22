import { AnimationCompose, AnimationRestTarget, stageWeightedCompose } from "./animationCompose";
import {
	AnimationTransitionClip, AnimationTransitionError, TransitionSide, bindSide, sampleSide,
} from "./animationTransition";

export enum AnimationBlendSpaceError {
	PointCount,
	NonFinite,
	Degenerate,
	Triangulation,
	Smooth,
	Delta,
	Target,
	Curve,
	Compose,
}

export struct AnimationBlendSpacePoint {
	x: float64;
	y: float64;
	clip: AnimationTransitionClip;
	keepSync: boolean;
}

export struct BlendSpaceTriangle {
	a: int32;
	b: int32;
	c: int32;
}

struct BlendSpaceEdge {
	a: int32;
	b: int32;
}

export struct AnimationBlendSpace2D {
	compose: AnimationCompose;
	pointX: Vec<float64>;
	pointY: Vec<float64>;
	keepSync: Vec<boolean>;
	sides: Vec<TransitionSide>;
	triangles: Vec<BlendSpaceTriangle>;
	x: float64;
	y: float64;
	xSmooth: float64;
	ySmooth: float64;
	scaleSpeedOutsideOfBounds: boolean;
	xSmoothed: float64;
	ySmoothed: float64;
	xVelocity: float64;
	yVelocity: float64;
	outsideSpeedScale: float64;
	blendLength: float64;
	phase: float64;
	current: int32;
	weights: Vec<float64>;
}

function inCircle(
	xs: Readonly<Span<float64>>, ys: Readonly<Span<float64>>,
	point: int32, triangle: BlendSpaceTriangle,
): boolean {
	const epsilon: float64 = 1e-10;
	const x1: float64 = xs[triangle.a]; const y1: float64 = ys[triangle.a];
	const x2: float64 = xs[triangle.b]; const y2: float64 = ys[triangle.b];
	const x3: float64 = xs[triangle.c]; const y3: float64 = ys[triangle.c];
	if (Math.abs(y1 - y2) < epsilon && Math.abs(y2 - y3) < epsilon) { return false; }
	let xc: float64 = 0.0;
	let yc: float64 = 0.0;
	if (Math.abs(y2 - y1) < epsilon) {
		const m2: float64 = -(x3 - x2) / (y3 - y2);
		xc = (x2 + x1) * 0.5;
		yc = m2 * (xc - (x2 + x3) * 0.5) + (y2 + y3) * 0.5;
	} else if (Math.abs(y3 - y2) < epsilon) {
		const m1: float64 = -(x2 - x1) / (y2 - y1);
		xc = (x3 + x2) * 0.5;
		yc = m1 * (xc - (x1 + x2) * 0.5) + (y1 + y2) * 0.5;
	} else {
		const m1: float64 = -(x2 - x1) / (y2 - y1);
		const m2: float64 = -(x3 - x2) / (y3 - y2);
		const mx1: float64 = (x1 + x2) * 0.5;
		const mx2: float64 = (x2 + x3) * 0.5;
		const my1: float64 = (y1 + y2) * 0.5;
		const my2: float64 = (y2 + y3) * 0.5;
		xc = (m1 * mx1 - m2 * mx2 + my2 - my1) / (m1 - m2);
		yc = m1 * (xc - mx1) + my1;
	}
	const rx: float64 = x2 - xc;
	const ry: float64 = y2 - yc;
	const dx: float64 = xs[point] - xc;
	const dy: float64 = ys[point] - yc;
	return dx * dx + dy * dy <= rx * rx + ry * ry;
}

function sameEdge(a: BlendSpaceEdge, b: BlendSpaceEdge): boolean {
	return (a.a == b.a && a.b == b.b) || (a.a == b.b && a.b == b.a);
}

export function triangulate(
	pointX: Readonly<Span<float64>>,
	pointY: Readonly<Span<float64>>,
): Result<Vec<BlendSpaceTriangle>, AnimationBlendSpaceError> {
	const count: int32 = pointX.length as int32;
	if (count < 3 || pointY.length != pointX.length) {
		return Result.err(AnimationBlendSpaceError.PointCount);
	}
	let xs: Vec<float64> = [];
	let ys: Vec<float64> = [];
	let xMin: float64 = pointX[0]; let xMax: float64 = pointX[0];
	let yMin: float64 = pointY[0]; let yMax: float64 = pointY[0];
	for (let i = 0; i < count; i++) {
		xs.push(pointX[i]); ys.push(pointY[i]);
		xMin = Math.min(xMin, pointX[i]); xMax = Math.max(xMax, pointX[i]);
		yMin = Math.min(yMin, pointY[i]); yMax = Math.max(yMax, pointY[i]);
	}
	const dx: float64 = xMax - xMin;
	const dy: float64 = yMax - yMin;
	const dmax: float64 = dx > dy ? dx : dy;
	const xMid: float64 = (xMax + xMin) * 0.5;
	const yMid: float64 = (yMax + yMin) * 0.5;
	xs.push(xMid - 2.0 * dmax); ys.push(yMid - dmax);
	xs.push(xMid); ys.push(yMid + 2.0 * dmax);
	xs.push(xMid + 2.0 * dmax); ys.push(yMid - dmax);
	let triangles: Vec<BlendSpaceTriangle> = [{ a: count, b: count + 1, c: count + 2 }];
	const limit: int32 = 4 * count;
	for (let i = 0; i < count; i++) {
		let edges: Vec<BlendSpaceEdge> = [];
		let j: int32 = 0;
		while (j < triangles.length) {
			if (inCircle(xs, ys, i, triangles[j])) {
				edges.push({ a: triangles[j].a, b: triangles[j].b });
				edges.push({ a: triangles[j].b, b: triangles[j].c });
				edges.push({ a: triangles[j].c, b: triangles[j].a });
				triangles.splice(j, 1);
			} else { j++; }
		}
		let first: int32 = (edges.length as int32) - 2;
		while (first >= 0) {
			let second: int32 = (edges.length as int32) - 1;
			while (second >= first + 1) {
				if (sameEdge(edges[first], edges[second])) {
					edges.splice(second, 1);
					edges.splice(first, 1);
					second--;
				}
				second--;
			}
			first--;
		}
		for (const edge of edges) {
			if (triangles.length >= limit) { return Result.err(AnimationBlendSpaceError.Triangulation); }
			triangles.push({ a: edge.a, b: edge.b, c: i });
		}
	}
	let kept: Vec<BlendSpaceTriangle> = [];
	for (const triangle of triangles) {
		if (triangle.a < count && triangle.b < count && triangle.c < count) { kept.push(triangle); }
	}
	return Result.ok(move kept);
}

function triangleArea(space: Readonly<AnimationBlendSpace2D>, t: BlendSpaceTriangle): float64 {
	const ax: float64 = space.pointX[t.a]; const ay: float64 = space.pointY[t.a];
	const bx: float64 = space.pointX[t.b]; const by: float64 = space.pointY[t.b];
	const cx: float64 = space.pointX[t.c]; const cy: float64 = space.pointY[t.c];
	return ((ay * bx - ax * by) + (by * cx - bx * cy) + (cy * ax - cx * ay)) * -0.5;
}

export function create(
	this typeof AnimationBlendSpace2D,
	targets: Readonly<Span<AnimationRestTarget>>,
	points: Readonly<Span<AnimationBlendSpacePoint>>,
): Result<AnimationBlendSpace2D, AnimationBlendSpaceError> {
	if (points.length < 3) { return Result.err(AnimationBlendSpaceError.PointCount); }
	const composed = AnimationCompose.create(targets);
	if (!composed.ok) { return Result.err(AnimationBlendSpaceError.Compose); }
	let space: AnimationBlendSpace2D = {
		compose: composed.value,
		pointX: [], pointY: [], keepSync: [], sides: [], triangles: [],
		x: 0.0, y: 0.0, xSmooth: 0.0, ySmooth: 0.0, scaleSpeedOutsideOfBounds: false,
		xSmoothed: 0.0, ySmoothed: 0.0, xVelocity: 0.0, yVelocity: 0.0,
		outsideSpeedScale: 1.0, blendLength: 1.0, phase: 0.0, current: -1, weights: [1.0, 0.0, 0.0],
	};
	for (let i = 0; i < points.length; i++) {
		if (!Number.isFinite(points[i].x) || !Number.isFinite(points[i].y)) {
			return Result.err(AnimationBlendSpaceError.NonFinite);
		}
		for (let previous = 0; previous < i; previous++) {
			if (points[previous].x == points[i].x && points[previous].y == points[i].y) {
				return Result.err(AnimationBlendSpaceError.Degenerate);
			}
		}
		const side = bindSide(targets, [], points[i].clip);
		if (!side.ok) {
			return Result.err(side.error == AnimationTransitionError.Target
				? AnimationBlendSpaceError.Target : AnimationBlendSpaceError.Curve);
		}
		space.pointX.push(points[i].x);
		space.pointY.push(points[i].y);
		space.keepSync.push(points[i].keepSync);
		space.sides.push(side.value);
	}
	let xMin: float64 = space.pointX[0]; let xMax: float64 = space.pointX[0];
	let yMin: float64 = space.pointY[0]; let yMax: float64 = space.pointY[0];
	for (let i = 0; i < space.pointX.length; i++) {
		xMin = Math.min(xMin, space.pointX[i]); xMax = Math.max(xMax, space.pointX[i]);
		yMin = Math.min(yMin, space.pointY[i]); yMax = Math.max(yMax, space.pointY[i]);
	}
	if (xMax == xMin || yMax == yMin) { return Result.err(AnimationBlendSpaceError.Degenerate); }
	let unitX: Vec<float64> = [];
	let unitY: Vec<float64> = [];
	for (let i = 0; i < space.pointX.length; i++) {
		unitX.push((space.pointX[i] - xMin) / (xMax - xMin));
		unitY.push((space.pointY[i] - yMin) / (yMax - yMin));
	}
	const triangles = try triangulate(unitX, unitY);
	if (triangles.length < 1) { return Result.err(AnimationBlendSpaceError.Degenerate); }
	for (const triangle of triangles) {
		if (triangleArea(space, triangle) == 0.0) {
			return Result.err(AnimationBlendSpaceError.Degenerate);
		}
		space.triangles.push(triangle);
	}
	return Result.ok(move space);
}

export function setBlendSpacePosition(
	ref space: AnimationBlendSpace2D,
	x: float64,
	y: float64,
): Result<void, AnimationBlendSpaceError> {
	if (!Number.isFinite(x) || !Number.isFinite(y)) {
		return Result.err(AnimationBlendSpaceError.NonFinite);
	}
	if (x != space.x || y != space.y) { space.current = -1; }
	space.x = x;
	space.y = y;
	return Result.ok(null);
}

export function setBlendSpaceSmoothing(
	ref space: AnimationBlendSpace2D,
	xHalfLife: float64,
	yHalfLife: float64,
): Result<void, AnimationBlendSpaceError> {
	if (!Number.isFinite(xHalfLife) || !Number.isFinite(yHalfLife) || xHalfLife < 0.0 || yHalfLife < 0.0) {
		return Result.err(AnimationBlendSpaceError.Smooth);
	}
	space.xSmooth = xHalfLife;
	space.ySmooth = yHalfLife;
	return Result.ok(null);
}

export function resetBlendSpaceSmoothing(ref space: AnimationBlendSpace2D): void {
	space.xSmoothed = space.x;
	space.ySmoothed = space.y;
	space.xVelocity = 0.0;
	space.yVelocity = 0.0;
	space.current = -1;
}

function springStep(
	value: float64, velocity: float64, goal: float64, halfLife: float64, dt: float64,
	ref nextVelocity: float64,
): float64 {
	const damping: float64 = (4.0 * 0.69314718056) / (halfLife + 1e-5);
	const halfDamping: float64 = damping / 2.0;
	const j0: float64 = value - goal;
	const j1: float64 = velocity + j0 * halfDamping;
	const x: float64 = halfDamping * dt;
	const eydt: float64 = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x);
	nextVelocity = eydt * (velocity - j1 * halfDamping * dt);
	return eydt * (j0 + j1 * dt) + goal;
}

function refreshTriangle(ref space: AnimationBlendSpace2D): void {
	if (space.triangles.length < 1 || space.current != -1) { return; }
	const px: float64 = space.xSmoothed;
	const py: float64 = space.ySmoothed;
	for (let index = 0; index < space.triangles.length; index++) {
		const t = space.triangles[index];
		const ax: float64 = space.pointX[t.a]; const ay: float64 = space.pointY[t.a];
		const bx: float64 = space.pointX[t.b]; const by: float64 = space.pointY[t.b];
		const cx: float64 = space.pointX[t.c]; const cy: float64 = space.pointY[t.c];
		const area: float64 = (1.0 / triangleArea(space, t)) * 0.5;
		const s: float64 = area * (ay * cx - ax * cy + (cy - ay) * px + (ax - cx) * py);
		const u: float64 = area * (ax * by - ay * bx + (ay - by) * px + (bx - ax) * py);
		if (s >= 0.0 && u >= 0.0 && s + u < 1.0) {
			space.current = index as int32;
			space.weights[0] = 1.0 - s - u;
			space.weights[1] = s;
			space.weights[2] = u;
			break;
		}
	}
	if (space.current == -1) {
		let closestSquared: float64 = Infinity;
		let closestX: float64 = 0.0;
		let closestY: float64 = 0.0;
		for (let index = 0; index < space.triangles.length; index++) {
			const corners: Vec<int32> = [
				space.triangles[index].a, space.triangles[index].b, space.triangles[index].c,
			];
			for (let i = 0; i < 3; i++) {
				const next: int32 = (i + 1) % 3;
				const x1: float64 = space.pointX[corners[i]]; const y1: float64 = space.pointY[corners[i]];
				const dx: float64 = space.pointX[corners[next]] - x1;
				const dy: float64 = space.pointY[corners[next]] - y1;
				const k: float64 = Math.min(1.0, Math.max(
					0.0, ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)));
				const mx: float64 = dx * k + x1 - px;
				const my: float64 = dy * k + y1 - py;
				if (mx * mx + my * my < closestSquared) {
					closestSquared = mx * mx + my * my;
					space.current = index as int32;
					closestX = mx;
					closestY = my;
					space.weights[i] = 1.0 - k;
					space.weights[next] = k;
					space.weights[(i + 2) % 3] = 0.0;
				}
			}
		}
		closestX += px;
		closestY += py;
		const epsilon: float64 = 1e-10;
		space.outsideSpeedScale = (Math.sqrt(px * px + py * py) + epsilon) /
			(Math.sqrt(closestX * closestX + closestY * closestY) + epsilon);
	} else {
		space.outsideSpeedScale = 1.0;
	}
	const corners: Vec<int32> = [
		space.triangles[space.current].a, space.triangles[space.current].b,
		space.triangles[space.current].c,
	];
	let synced: int32 = 0;
	let unsyncedWeight: float64 = 0.0;
	for (let i = 0; i < 3; i++) {
		if (space.keepSync[corners[i]]) { synced++; } else { unsyncedWeight += space.weights[i]; }
	}
	const unsynced: int32 = 3 - synced;
	if (unsynced < 3) { unsyncedWeight /= (3 - unsynced) as float64; }
	space.blendLength = 0.0;
	for (let i = 0; i < 3; i++) {
		if (space.keepSync[corners[i]]) {
			space.blendLength += space.sides[corners[i]].clip.seconds * (space.weights[i] + unsyncedWeight);
		}
	}
}

export function advanceBlendSpace(
	ref space: AnimationBlendSpace2D,
	dt: float64,
): Result<void, AnimationBlendSpaceError> {
	if (!Number.isFinite(dt) || dt < 0.0) { return Result.err(AnimationBlendSpaceError.Delta); }
	let velocity: float64 = 0.0;
	if (space.xSmooth > 0.0) {
		space.xSmoothed = springStep(space.xSmoothed, space.xVelocity, space.x, space.xSmooth, dt, velocity);
		space.xVelocity = velocity;
		space.current = -1;
	} else { space.xSmoothed = space.x; }
	if (space.ySmooth > 0.0) {
		space.ySmoothed = springStep(space.ySmoothed, space.yVelocity, space.y, space.ySmooth, dt, velocity);
		space.yVelocity = velocity;
		space.current = -1;
	} else { space.ySmoothed = space.y; }
	let scale: float64 = 1.0;
	if (space.blendLength > 0.0) { scale /= space.blendLength; }
	if (space.scaleSpeedOutsideOfBounds) { scale *= space.outsideSpeedScale; }
	space.phase = (space.phase + dt * scale) % 1.0;
	refreshTriangle(space);
	for (let i = 0; i < space.sides.length; i++) {
		space.sides[i].time = space.keepSync[i]
			? space.sides[i].clip.seconds * space.phase
			: space.sides[i].clip.localTime(space.sides[i].time + dt);
	}
	return Result.ok(null);
}

export function evaluateBlendSpace(
	ref space: AnimationBlendSpace2D,
): Result<void, AnimationBlendSpaceError> {
	refreshTriangle(space);
	const triangle = space.triangles[space.current];
	const corners: Vec<int32> = [triangle.a, triangle.b, triangle.c];
	for (const corner of corners) {
		if (!sampleSide(space.compose.targets, [], space.sides[corner]).ok) {
			return Result.err(AnimationBlendSpaceError.Curve);
		}
	}
	const staged = stageWeightedCompose(
		space.compose, space.sides[triangle.a].child, space.sides[triangle.b].child,
		space.sides[triangle.c].child, space.weights);
	if (!staged.ok) { return Result.err(AnimationBlendSpaceError.Compose); }
	return Result.ok(null);
}
