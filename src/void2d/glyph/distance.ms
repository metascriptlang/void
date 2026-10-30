import {
	GlyphBox,
	Vertex,
	VERTEX_CUBIC,
	VERTEX_CURVE,
	VERTEX_LINE,
	truncInt,
} from "../trueType/fontInfo";
import { Point, tesselateCubic } from "../trueType/rasterize";
import { computeCrossingsX, solveCubic } from "../trueType/sdf";
import { shortOf } from "./outline";

export const SDF_EM: float32 = 32.0;
export const SDF_PAD: int32 = 4;
export const SDF_EDGE: int32 = 191;
export const SDF_DIST_SCALE: float32 = 255.0 / 8.0;

const FLATTEN_REACH: float32 = 32000.0;
const FLATTEN_GRID_LIMIT: int32 = 16;

function minF(a: float32, b: float32): float32 {
	return a < b ? a : b;
}

function maxF(a: float32, b: float32): float32 {
	return a > b ? a : b;
}

function absF(value: float32): float32 {
	return Math.abs(value as float64) as float32;
}

function sqrtF(value: float32): float32 {
	return Math.sqrt(value as float64) as float32;
}

function pointDistance(
	verts: Vec<Vertex>,
	precompute: float32[],
	scaleX: float32,
	scaleY: float32,
	sx: float32,
	sy: float32,
	hits: float32[],
	res: float32[],
): float32 {
	const eps: float32 = 1.0 / 1024;
	const eps2: float32 = eps * eps;
	let minDist: float32 = 999999.0;
	const xGspace: float32 = sx / scaleX;
	const yGspace: float32 = sy / scaleY;
	const numVerts = verts.length as int32;
	const winding = computeCrossingsX(xGspace, yGspace, verts, hits);
	for (let i: int32 = 0; i < numVerts; i++) {
		const v = verts[i];
		const x0: float32 = (v.x as float32) * scaleX;
		const y0: float32 = (v.y as float32) * scaleY;
		if (v.kind == VERTEX_LINE && precompute[i] != 0.0) {
			const x1: float32 = (verts[i - 1].x as float32) * scaleX;
			const y1: float32 = (verts[i - 1].y as float32) * scaleY;
			const dist2: float32 = (x0 - sx) * (x0 - sx) + (y0 - sy) * (y0 - sy);
			if (dist2 < minDist * minDist) { minDist = sqrtF(dist2); }
			const dist: float32 = absF((x1 - x0) * (y0 - sy) - (y1 - y0) * (x0 - sx)) * precompute[i];
			if (dist < minDist) {
				const dx: float32 = x1 - x0;
				const dy: float32 = y1 - y0;
				const px: float32 = x0 - sx;
				const py: float32 = y0 - sy;
				const t: float32 = -(px * dx + py * dy) / (dx * dx + dy * dy);
				if (t >= 0.0 && t <= 1.0) { minDist = dist; }
			}
		} else if (v.kind == VERTEX_CURVE) {
			const x2: float32 = (verts[i - 1].x as float32) * scaleX;
			const y2: float32 = (verts[i - 1].y as float32) * scaleY;
			const x1: float32 = (v.cx as float32) * scaleX;
			const y1: float32 = (v.cy as float32) * scaleY;
			const boxX0 = minF(minF(x0, x1), x2);
			const boxY0 = minF(minF(y0, y1), y2);
			const boxX1 = maxF(maxF(x0, x1), x2);
			const boxY1 = maxF(maxF(y0, y1), y2);
			if (sx > boxX0 - minDist && sx < boxX1 + minDist && sy > boxY0 - minDist && sy < boxY1 + minDist) {
				let num: int32 = 0;
				const ax: float32 = x1 - x0;
				const ay: float32 = y1 - y0;
				const bx: float32 = x0 - 2 * x1 + x2;
				const by: float32 = y0 - 2 * y1 + y2;
				const mx: float32 = x0 - sx;
				const my: float32 = y0 - sy;
				res[0] = 0;
				res[1] = 0;
				res[2] = 0;
				const aInv: float32 = precompute[i];
				if (aInv == 0.0) {
					const a: float32 = 3 * (ax * bx + ay * by);
					const b: float32 = 2 * (ax * ax + ay * ay) + (mx * bx + my * by);
					const c: float32 = mx * ax + my * ay;
					if (Math.abs(a as float64) < (eps2 as float64)) {
						if (Math.abs(b as float64) >= (eps2 as float64)) {
							res[num] = -c / b;
							num += 1;
						}
					} else {
						const discriminant: float32 = b * b - 4 * a * c;
						if (discriminant < 0) {
							num = 0;
						} else {
							const root: float32 = sqrtF(discriminant);
							res[0] = (-b - root) / (2 * a);
							res[1] = (-b + root) / (2 * a);
							num = 2;
						}
					}
				} else {
					const b: float32 = 3 * (ax * bx + ay * by) * aInv;
					const c: float32 = (2 * (ax * ax + ay * ay) + (mx * bx + my * by)) * aInv;
					const d: float32 = (mx * ax + my * ay) * aInv;
					num = solveCubic(b, c, d, res);
				}
				let dist2: float32 = (x0 - sx) * (x0 - sx) + (y0 - sy) * (y0 - sy);
				if (dist2 < minDist * minDist) { minDist = sqrtF(dist2); }
				for (let r: int32 = 0; r < num; r++) {
					if (res[r] >= 0.0 && res[r] <= 1.0) {
						const t: float32 = res[r];
						const it: float32 = 1.0 - t;
						const px: float32 = it * it * x0 + 2 * t * it * x1 + t * t * x2;
						const py: float32 = it * it * y0 + 2 * t * it * y1 + t * t * y2;
						dist2 = (px - sx) * (px - sx) + (py - sy) * (py - sy);
						if (dist2 < minDist * minDist) { minDist = sqrtF(dist2); }
					}
				}
			}
		}
	}
	if (winding == 0) { minDist = -minDist; }
	return minDist;
}

export function distanceFill(
	verts: Vec<Vertex>,
	scale: float32,
	shiftX: float32,
	box: GlyphBox,
	outline: boolean,
	bias: float32,
	out: Span<uint8>,
	stride: int32,
): void {
	const scaleX: float32 = scale;
	const scaleY: float32 = -scale;
	const eps: float32 = 1.0 / 1024;
	const eps2: float32 = eps * eps;
	const numVerts = verts.length as int32;
	const precompute: float32[] = new Array<float32>(numVerts);
	const hits: float32[] = new Array<float32>(4);
	const res: float32[] = new Array<float32>(3);
	let j: int32 = numVerts - 1;
	for (let i: int32 = 0; i < numVerts; i++) {
		const v = verts[i];
		if (v.kind == VERTEX_LINE) {
			const x0: float32 = (v.x as float32) * scaleX;
			const y0: float32 = (v.y as float32) * scaleY;
			const x1: float32 = (verts[j].x as float32) * scaleX;
			const y1: float32 = (verts[j].y as float32) * scaleY;
			const dist: float32 = sqrtF((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
			precompute[i] = (dist < eps) ? 0.0 : 1.0 / dist;
		} else if (v.kind == VERTEX_CURVE) {
			const x2: float32 = (verts[j].x as float32) * scaleX;
			const y2: float32 = (verts[j].y as float32) * scaleY;
			const x1: float32 = (v.cx as float32) * scaleX;
			const y1: float32 = (v.cy as float32) * scaleY;
			const x0: float32 = (v.x as float32) * scaleX;
			const y0: float32 = (v.y as float32) * scaleY;
			const bx: float32 = x0 - 2 * x1 + x2;
			const by: float32 = y0 - 2 * y1 + y2;
			const len2: float32 = bx * bx + by * by;
			precompute[i] = len2 >= eps2 ? 1.0 / len2 : 0.0;
		} else {
			precompute[i] = 0.0;
		}
		j = i;
	}
	for (let y: int32 = box.y0; y < box.y1; y++) {
		for (let x: int32 = box.x0; x < box.x1; x++) {
			const sx: float32 = (x as float32) + 0.5 - shiftX;
			const sy: float32 = (y as float32) + 0.5;
			const minDist = pointDistance(verts, precompute, scaleX, scaleY, sx, sy, hits, res);
			let val: float32 = 0.0;
			if (outline) {
				const covered: float32 = 0.5 + minDist + bias;
				val = covered <= 0.0 ? 0.0 : covered >= 1.0 ? 255.0 : covered * 255.0 + 0.5;
			} else {
				val = (SDF_EDGE as float32) + SDF_DIST_SCALE * (minDist + bias);
			}
			if (val < 0) {
				val = 0;
			} else if (val > 255) {
				val = 255;
			}
			out[(y - box.y0) * stride + (x - box.x0)] = (truncInt(val as float64) & 0xFF) as uint8;
		}
	}
}

function outlineQuantise(value: float32, grid: int32): int16 {
	return shortOf(Math.floor((value * (grid as float32) + 0.5) as float64) as float32);
}

export struct Flattened {
	vertices: Vec<Vertex>;
	grid: int32;
}

export function flattenCubics(input: Vec<Vertex>, flatness: float32): Flattened {
	let reach: float32 = 1.0;
	const count = input.length as int32;
	for (let i: int32 = 0; i < count; i++) {
		const v = input[i];
		const used = v.kind == VERTEX_CUBIC ? 6 : v.kind == VERTEX_CURVE ? 4 : 2;
		for (let k: int32 = 0; k < used; k++) {
			const value: float32 = (k == 0 ? v.x : k == 1 ? v.y : k == 2 ? v.cx : k == 3 ? v.cy : k == 4 ? v.cx1 : v.cy1) as float32;
			if (absF(value) > reach) { reach = absF(value); }
		}
	}
	let g: int32 = 1;
	while (g < FLATTEN_GRID_LIMIT && reach * ((g * 2) as float32) <= FLATTEN_REACH) { g *= 2; }
	const flatnessSquared: float32 = flatness * flatness;
	let out: Vec<Vertex> = [];
	let px: float32 = 0.0;
	let py: float32 = 0.0;
	for (let i: int32 = 0; i < count; i++) {
		const v = input[i];
		if (v.kind == VERTEX_CUBIC) {
			let points: Vec<Point> = [];
			tesselateCubic(
				points, px, py, v.cx as float32, v.cy as float32, v.cx1 as float32, v.cy1 as float32,
				v.x as float32, v.y as float32, flatnessSquared, 0,
			);
			for (let k: int32 = 0; k < (points.length as int32); k++) {
				out.push({
					x: outlineQuantise(points[k].x, g),
					y: outlineQuantise(points[k].y, g),
					cx: 0,
					cy: 0,
					cx1: 0,
					cy1: 0,
					kind: VERTEX_LINE,
				});
			}
		} else {
			out.push({
				x: outlineQuantise(v.x as float32, g),
				y: outlineQuantise(v.y as float32, g),
				cx: outlineQuantise(v.cx as float32, g),
				cy: outlineQuantise(v.cy as float32, g),
				cx1: v.cx1,
				cy1: v.cy1,
				kind: v.kind,
			});
		}
		px = v.x as float32;
		py = v.y as float32;
	}
	return { vertices: out, grid: g };
}
