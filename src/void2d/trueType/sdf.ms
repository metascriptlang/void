import { FontInfo, Vertex, VERTEX_CURVE, VERTEX_LINE, truncInt } from "./fontInfo";
import { getGlyphShape } from "../trueType";
import { getGlyphBitmapBoxSubpixel } from "./rasterize";

export struct Sdf {
	data: uint8[];
	width: int32;
	height: int32;
	xoff: int32;
	yoff: int32;
}

const THIRD: float32 = 1.0 / 3.0;
const HALF_PI: float64 = 3.141592 / 2;
const SQRT3: float32 = 1.732050808;

function minF(a: float32, b: float32): float32 {
	return a < b ? a : b;
}

function maxF(a: float32, b: float32): float32 {
	return a < b ? b : a;
}

function minI(a: int32, b: int32): int32 {
	return a < b ? a : b;
}

function maxI(a: int32, b: int32): int32 {
	return a < b ? b : a;
}

// stbtt__ray_intersect_bezier: hits holds [h0.x, h0.y, h1.x, h1.y].
function rayIntersectBezier(
	origX: float32,
	origY: float32,
	rayX: float32,
	rayY: float32,
	q0x: float32,
	q0y: float32,
	q1x: float32,
	q1y: float32,
	q2x: float32,
	q2y: float32,
	hits: float32[],
): int32 {
	const q0perp: float32 = q0y * rayX - q0x * rayY;
	const q1perp: float32 = q1y * rayX - q1x * rayY;
	const q2perp: float32 = q2y * rayX - q2x * rayY;
	const roperp: float32 = origY * rayX - origX * rayY;

	const a: float32 = q0perp - 2 * q1perp + q2perp;
	const b: float32 = q1perp - q0perp;
	const c: float32 = q0perp - roperp;

	let s0: float32 = 0;
	let s1: float32 = 0;
	let numS: int32 = 0;

	if (a != 0.0) {
		const discr: float32 = b * b - a * c;
		if (discr > 0.0) {
			const rcpna: float32 = -1 / a;
			const d: float32 = Math.sqrt(discr as float64) as float32;
			s0 = (b + d) * rcpna;
			s1 = (b - d) * rcpna;
			if (s0 >= 0.0 && s0 <= 1.0) { numS = 1; }
			if (d > 0.0 && s1 >= 0.0 && s1 <= 1.0) {
				if (numS == 0) { s0 = s1; }
				numS += 1;
			}
		}
	} else {
		s0 = c / (-2 * b);
		if (s0 >= 0.0 && s0 <= 1.0) { numS = 1; }
	}

	if (numS == 0) { return 0; }
	const rcpLen2: float32 = 1 / (rayX * rayX + rayY * rayY);
	const raynX: float32 = rayX * rcpLen2;
	const raynY: float32 = rayY * rcpLen2;

	const q0d: float32 = q0x * raynX + q0y * raynY;
	const q1d: float32 = q1x * raynX + q1y * raynY;
	const q2d: float32 = q2x * raynX + q2y * raynY;
	const rod: float32 = origX * raynX + origY * raynY;

	const q10d: float32 = q1d - q0d;
	const q20d: float32 = q2d - q0d;
	const q0rd: float32 = q0d - rod;

	hits[0] = q0rd + s0 * (2.0 - 2.0 * s0) * q10d + s0 * s0 * q20d;
	hits[1] = a * s0 + b;

	if (numS > 1) {
		hits[2] = q0rd + s1 * (2.0 - 2.0 * s1) * q10d + s1 * s1 * q20d;
		hits[3] = a * s1 + b;
		return 2;
	}
	return 1;
}

function lineCrossing(x: float32, y: float32, a: Vertex, b: Vertex): int32 {
	const x0 = a.x as int32;
	const y0 = a.y as int32;
	const x1 = b.x as int32;
	const y1 = b.y as int32;
	if (y > (minI(y0, y1) as float32) && y < (maxI(y0, y1) as float32) && x > (minI(x0, x1) as float32)) {
		const xInter: float32 = (y - (y0 as float32)) / ((y1 - y0) as float32) * ((x1 - x0) as float32) +
			(x0 as float32);
		if (xInter < x) { return y0 < y1 ? 1 : -1; }
	}
	return 0;
}

// stbtt__compute_crossings_x: winding of the ray from (-inf, y) to (x, y); the shape is `verts`.
export function computeCrossingsX(
	x: float32,
	yIn: float32,
	verts: Vec<Vertex>,
	hits: float32[],
): int32 {
	let y = yIn;
	let winding: int32 = 0;
	const yFrac: float32 = ((y as float64) % 1.0) as float32;
	if (yFrac < 0.01) {
		y += 0.01;
	} else if (yFrac > 0.99) {
		y -= 0.01;
	}
	const n = verts.length as int32;
	for (let i: int32 = 0; i < n; i++) {
		const v = verts[i];
		if (v.kind == VERTEX_LINE) {
			winding += lineCrossing(x, y, verts[i - 1], v);
		}
		if (v.kind == VERTEX_CURVE) {
			const p = verts[i - 1];
			const x0 = p.x as int32;
			const y0 = p.y as int32;
			const x1 = v.cx as int32;
			const y1 = v.cy as int32;
			const x2 = v.x as int32;
			const y2 = v.y as int32;
			const ax = minI(x0, minI(x1, x2));
			const ay = minI(y0, minI(y1, y2));
			const by = maxI(y0, maxI(y1, y2));
			if (y > (ay as float32) && y < (by as float32) && x > (ax as float32)) {
				const q0x = x0 as float32;
				const q0y = y0 as float32;
				const q1x = x1 as float32;
				const q1y = y1 as float32;
				const q2x = x2 as float32;
				const q2y = y2 as float32;
				if ((q0x == q1x && q0y == q1y) || (q1x == q2x && q1y == q2y)) {
					winding += lineCrossing(x, y, p, v);
				} else {
					const numHits = rayIntersectBezier(x, y, 1, 0, q0x, q0y, q1x, q1y, q2x, q2y, hits);
					if (numHits >= 1) {
						if (hits[0] < 0) { winding += hits[1] < 0 ? -1 : 1; }
					}
					if (numHits >= 2) {
						if (hits[2] < 0) { winding += hits[3] < 0 ? -1 : 1; }
					}
				}
			}
		}
	}
	return winding;
}

// stbtt__cuberoot: pow is the double libm one, with the exponent a float 1/3.
function cuberoot(x: float32): float32 {
	if (x < 0) { return -(Math.pow((-x) as float64, THIRD as float64) as float32); }
	return Math.pow(x as float64, THIRD as float64) as float32;
}

// stbtt__solve_cubic: x^3 + a*x^2 + b*x + c = 0, roots into r.
export function solveCubic(a: float32, b: float32, c: float32, r: float32[]): int32 {
	const s: float32 = -a / 3;
	const p: float32 = b - a * a / 3;
	const q: float32 = a * (2 * a * a - 9 * b) / 27 + c;
	const p3: float32 = p * p * p;
	const d: float32 = q * q + 4 * p3 / 27;
	if (d >= 0) {
		const z: float32 = Math.sqrt(d as float64) as float32;
		let u: float32 = (-q + z) / 2;
		let v: float32 = (-q - z) / 2;
		u = cuberoot(u);
		v = cuberoot(v);
		r[0] = s + u + v;
		return 1;
	}
	const u: float32 = Math.sqrt((-p / 3) as float64) as float32;
	const inner: float64 = -Math.sqrt((-27 / p3) as float64) * (q as float64) / 2;
	const v: float32 = (Math.acos(inner) as float32) / 3;
	const m: float32 = Math.cos(v as float64) as float32;
	const n: float32 = (Math.cos((v as float64) - HALF_PI) as float32) * SQRT3;
	r[0] = s + u * 2 * m;
	r[1] = s - u * (m + n);
	r[2] = s - u * (m - n);
	return 3;
}

function squaredDistance(px: float32, py: float32, sx: float32, sy: float32): float32 {
	return (px - sx) * (px - sx) + (py - sy) * (py - sy);
}

// stbtt_GetGlyphSDF: null for scale 0 or an empty glyph.
export function getGlyphSDF(
	info: FontInfo,
	scale: float32,
	glyph: int32,
	padding: int32,
	onedgeValue: uint8,
	pixelDistScale: float32,
): Sdf | null {
	const scaleX: float32 = scale;
	let scaleY: float32 = scale;
	if (scale == 0) { return null; }

	const box = getGlyphBitmapBoxSubpixel(info, glyph, scale, scale, 0.0, 0.0);
	if (box.x0 == box.x1 || box.y0 == box.y1) { return null; }
	const ix0 = box.x0 - padding;
	const iy0 = box.y0 - padding;
	const ix1 = box.x1 + padding;
	const iy1 = box.y1 + padding;
	const w = ix1 - ix0;
	const h = iy1 - iy0;

	scaleY = -scaleY;

	const eps2: float32 = (1.0 / 1024) * (1.0 / 1024);
	const verts = getGlyphShape(info, glyph);
	const numVerts = verts.length as int32;
	const data: uint8[] = new Array<uint8>(w * h);
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
			const dist: float32 = Math.sqrt(((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)) as float64) as float32;
			precompute[i] = (dist < (1.0 / 1024)) ? 0.0 : 1.0 / dist;
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

	for (let y: int32 = iy0; y < iy1; y++) {
		for (let x: int32 = ix0; x < ix1; x++) {
			let minDist: float32 = 999999.0;
			const sx: float32 = (x as float32) + 0.5;
			const sy: float32 = (y as float32) + 0.5;
			const xGspace: float32 = sx / scaleX;
			const yGspace: float32 = sy / scaleY;

			const winding = computeCrossingsX(xGspace, yGspace, verts, hits);

			for (let i: int32 = 0; i < numVerts; i++) {
				const v = verts[i];
				const x0: float32 = (v.x as float32) * scaleX;
				const y0: float32 = (v.y as float32) * scaleY;

				if (v.kind == VERTEX_LINE && precompute[i] != 0.0) {
					const x1: float32 = (verts[i - 1].x as float32) * scaleX;
					const y1: float32 = (verts[i - 1].y as float32) * scaleY;

					const dist2: float32 = (x0 - sx) * (x0 - sx) + (y0 - sy) * (y0 - sy);
					if (dist2 < minDist * minDist) { minDist = Math.sqrt(dist2 as float64) as float32; }

					const dist: float32 = (Math.abs(((x1 - x0) * (y0 - sy) - (y1 - y0) * (x0 - sx)) as float64) as float32) *
						precompute[i];
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
									const root: float32 = Math.sqrt(discriminant as float64) as float32;
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
						if (dist2 < minDist * minDist) { minDist = Math.sqrt(dist2 as float64) as float32; }

						let k: int32 = 0;
						while (k < 3) {
							if (num >= k + 1 && res[k] >= 0.0 && res[k] <= 1.0) {
								const t: float32 = res[k];
								const it: float32 = 1.0 - t;
								const px: float32 = it * it * x0 + 2 * t * it * x1 + t * t * x2;
								const py: float32 = it * it * y0 + 2 * t * it * y1 + t * t * y2;
								dist2 = squaredDistance(px, py, sx, sy);
								if (dist2 < minDist * minDist) { minDist = Math.sqrt(dist2 as float64) as float32; }
							}
							k += 1;
						}
					}
				}
			}
			if (winding == 0) { minDist = -minDist; }
			let val: float32 = (onedgeValue as float32) + pixelDistScale * minDist;
			if (val < 0) {
				val = 0;
			} else if (val > 255) {
				val = 255;
			}
			data[(y - iy0) * w + (x - ix0)] = (truncInt(val as float64) & 0xFF) as uint8;
		}
	}
	return { data: data, width: w, height: h, xoff: ix0, yoff: iy0 };
}
