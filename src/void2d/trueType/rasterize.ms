import { FontInfo, GlyphBox, Vertex, VERTEX_CUBIC, VERTEX_CURVE, VERTEX_LINE, VERTEX_MOVE, truncInt } from "./fontInfo";
import { getGlyphBox, getGlyphShape } from "../trueType";

export struct Point {
	x: float32;
	y: float32;
}

struct Edge {
	x0: float32;
	y0: float32;
	x1: float32;
	y1: float32;
	invert: boolean;
}

struct ActiveEdge {
	next: int32;
	fx: float32;
	fdx: float32;
	fdy: float32;
	direction: float32;
	sy: float32;
	ey: float32;
}

const FLATNESS_IN_PIXELS: float32 = 0.35;
const MAX_TESSELLATION_DEPTH: int32 = 16;

// stbtt_GetGlyphBitmapBoxSubpixel: the pixel box a glyph touches; zeros for an empty glyph.
export function getGlyphBitmapBoxSubpixel(
	info: FontInfo,
	glyph: int32,
	scaleX: float32,
	scaleY: float32,
	shiftX: float32,
	shiftY: float32,
): GlyphBox {
	const box = getGlyphBox(info, glyph);
	if (box == null) { return { x0: 0, y0: 0, x1: 0, y1: 0 }; }
	return {
		x0: truncInt(Math.floor(((box.x0 as float32) * scaleX + shiftX) as float64)),
		y0: truncInt(Math.floor((((0 - box.y1) as float32) * scaleY + shiftY) as float64)),
		x1: truncInt(Math.ceil(((box.x1 as float32) * scaleX + shiftX) as float64)),
		y1: truncInt(Math.ceil((((0 - box.y0) as float32) * scaleY + shiftY) as float64)),
	};
}

function addCurvePoint(ref points: Vec<Point>, x: float32, y: float32): void {
	points.push({ x: x, y: y });
}

function tesselateCurve(
	ref points: Vec<Point>,
	x0: float32,
	y0: float32,
	x1: float32,
	y1: float32,
	x2: float32,
	y2: float32,
	flatnessSquared: float32,
	n: int32,
): void {
	const mx: float32 = (x0 + 2 * x1 + x2) / 4;
	const my: float32 = (y0 + 2 * y1 + y2) / 4;
	const dx: float32 = (x0 + x2) / 2 - mx;
	const dy: float32 = (y0 + y2) / 2 - my;
	if (n > MAX_TESSELLATION_DEPTH) { return; }
	if (dx * dx + dy * dy > flatnessSquared) {
		tesselateCurve(points, x0, y0, (x0 + x1) / 2.0, (y0 + y1) / 2.0, mx, my, flatnessSquared, n + 1);
		tesselateCurve(points, mx, my, (x1 + x2) / 2.0, (y1 + y2) / 2.0, x2, y2, flatnessSquared, n + 1);
	} else {
		addCurvePoint(points, x2, y2);
	}
}

// stbtt__tesselate_cubic: appends the flattened points; the C count pass is `points.length`.
export function tesselateCubic(
	ref points: Vec<Point>,
	x0: float32,
	y0: float32,
	x1: float32,
	y1: float32,
	x2: float32,
	y2: float32,
	x3: float32,
	y3: float32,
	flatnessSquared: float32,
	n: int32,
): void {
	const dx0: float32 = x1 - x0;
	const dy0: float32 = y1 - y0;
	const dx1: float32 = x2 - x1;
	const dy1: float32 = y2 - y1;
	const dx2: float32 = x3 - x2;
	const dy2: float32 = y3 - y2;
	const dx: float32 = x3 - x0;
	const dy: float32 = y3 - y0;
	const longlen: float32 = (Math.sqrt((dx0 * dx0 + dy0 * dy0) as float64) +
		Math.sqrt((dx1 * dx1 + dy1 * dy1) as float64) +
		Math.sqrt((dx2 * dx2 + dy2 * dy2) as float64)) as float32;
	const shortlen: float32 = Math.sqrt((dx * dx + dy * dy) as float64) as float32;
	const flatness: float32 = longlen * longlen - shortlen * shortlen;
	if (n > MAX_TESSELLATION_DEPTH) { return; }
	if (flatness > flatnessSquared) {
		const x01: float32 = (x0 + x1) / 2;
		const y01: float32 = (y0 + y1) / 2;
		const x12: float32 = (x1 + x2) / 2;
		const y12: float32 = (y1 + y2) / 2;
		const x23: float32 = (x2 + x3) / 2;
		const y23: float32 = (y2 + y3) / 2;
		const xa: float32 = (x01 + x12) / 2;
		const ya: float32 = (y01 + y12) / 2;
		const xb: float32 = (x12 + x23) / 2;
		const yb: float32 = (y12 + y23) / 2;
		const mx: float32 = (xa + xb) / 2;
		const my: float32 = (ya + yb) / 2;
		tesselateCubic(points, x0, y0, x01, y01, xa, ya, mx, my, flatnessSquared, n + 1);
		tesselateCubic(points, mx, my, xb, yb, x23, y23, x3, y3, flatnessSquared, n + 1);
	} else {
		addCurvePoint(points, x3, y3);
	}
}

struct Flattened {
	points: Vec<Point>;
	lengths: Vec<int32>;
}

// stbtt_FlattenCurves: the contours' points and their lengths; no lengths when there is no move.
function flattenCurves(vertices: Readonly<Span<Vertex>>, flatness: float32): Flattened {
	let flat: Flattened = { points: [], lengths: [] };
	let moves: int32 = 0;
	for (let i: int32 = 0; i < (vertices.length as int32); i++) {
		if (vertices[i].kind == VERTEX_MOVE) { moves += 1; }
	}
	if (moves == 0) { return flat; }
	const flatnessSquared: float32 = flatness * flatness;
	let start: int32 = 0;
	let n: int32 = -1;
	let x: float32 = 0;
	let y: float32 = 0;
	for (let i: int32 = 0; i < (vertices.length as int32); i++) {
		const v = vertices[i];
		if (v.kind == VERTEX_MOVE) {
			if (n >= 0) { flat.lengths.push((flat.points.length as int32) - start); }
			n += 1;
			start = flat.points.length as int32;
			x = v.x as float32;
			y = v.y as float32;
			addCurvePoint(flat.points, x, y);
		} else if (v.kind == VERTEX_LINE) {
			x = v.x as float32;
			y = v.y as float32;
			addCurvePoint(flat.points, x, y);
		} else if (v.kind == VERTEX_CURVE) {
			tesselateCurve(
				flat.points, x, y,
				v.cx as float32, v.cy as float32,
				v.x as float32, v.y as float32,
				flatnessSquared, 0,
			);
			x = v.x as float32;
			y = v.y as float32;
		} else if (v.kind == VERTEX_CUBIC) {
			tesselateCubic(
				flat.points, x, y,
				v.cx as float32, v.cy as float32,
				v.cx1 as float32, v.cy1 as float32,
				v.x as float32, v.y as float32,
				flatnessSquared, 0,
			);
			x = v.x as float32;
			y = v.y as float32;
		}
	}
	flat.lengths.push((flat.points.length as int32) - start);
	return flat;
}

function edgeBefore(a: Edge, b: Edge): boolean {
	return a.y0 < b.y0;
}

function swapEdges(edges: Edge[], a: int32, b: int32): void {
	const t = edges[a];
	edges[a] = edges[b];
	edges[b] = t;
}

function insertionSortEdges(edges: Edge[], n: int32): void {
	for (let i: int32 = 1; i < n; i++) {
		const t = edges[i];
		let j = i;
		while (j > 0) {
			if (!edgeBefore(t, edges[j - 1])) { break; }
			edges[j] = edges[j - 1];
			j -= 1;
		}
		if (i != j) { edges[j] = t; }
	}
}

function quicksortEdges(edges: Edge[], first: int32, count: int32): void {
	let p = first;
	let n = count;
	while (n > 12) {
		const m = n >> 1;
		const c01 = edgeBefore(edges[p], edges[p + m]);
		const c12 = edgeBefore(edges[p + m], edges[p + n - 1]);
		if (c01 != c12) {
			const c = edgeBefore(edges[p], edges[p + n - 1]);
			const z = (c == c12) ? 0 : n - 1;
			swapEdges(edges, p + z, p + m);
		}
		swapEdges(edges, p, p + m);
		let i: int32 = 1;
		let j: int32 = n - 1;
		while (true) {
			while (edgeBefore(edges[p + i], edges[p])) { i += 1; }
			while (edgeBefore(edges[p], edges[p + j])) { j -= 1; }
			if (i >= j) { break; }
			swapEdges(edges, p + i, p + j);
			i += 1;
			j -= 1;
		}
		if (j < n - i) {
			quicksortEdges(edges, p, j);
			p += i;
			n -= i;
		} else {
			quicksortEdges(edges, p + i, n - i);
			n = j;
		}
	}
}

function newActive(e: Edge, offX: int32, startPoint: float32): ActiveEdge {
	const dxdy: float32 = (e.x1 - e.x0) / (e.y1 - e.y0);
	return {
		next: -1,
		fx: e.x0 + dxdy * (startPoint - e.y0) - (offX as float32),
		fdx: dxdy,
		fdy: dxdy != 0 ? (1.0 / dxdy) : 0.0,
		direction: e.invert ? 1.0 : -1.0,
		sy: e.y0,
		ey: e.y1,
	};
}

function handleClippedEdge(
	buf: float32[],
	base: int32,
	x: int32,
	e: ActiveEdge,
	startX: float32,
	startY: float32,
	endX: float32,
	endY: float32,
): void {
	if (startY == endY) { return; }
	if (startY > e.ey) { return; }
	if (endY < e.sy) { return; }
	let x0 = startX;
	let y0 = startY;
	let x1 = endX;
	let y1 = endY;
	if (y0 < e.sy) {
		x0 += (x1 - x0) * (e.sy - y0) / (y1 - y0);
		y0 = e.sy;
	}
	if (y1 > e.ey) {
		x1 += (x1 - x0) * (e.ey - y1) / (y1 - y0);
		y1 = e.ey;
	}
	const left = x as float32;
	const right = (x + 1) as float32;
	const slot = base + x;
	if (x0 <= left && x1 <= left) {
		buf[slot] += e.direction * (y1 - y0);
	} else if (x0 >= right && x1 >= right) {
		return;
	} else {
		buf[slot] += e.direction * (y1 - y0) * (1 - ((x0 - left) + (x1 - left)) / 2);
	}
}

function trapezoidArea(height: float32, topWidth: float32, bottomWidth: float32): float32 {
	return (topWidth + bottomWidth) / 2.0 * height;
}

function positionTrapezoidArea(
	height: float32,
	tx0: float32,
	tx1: float32,
	bx0: float32,
	bx1: float32,
): float32 {
	return trapezoidArea(height, tx1 - tx0, bx1 - bx0);
}

function triangleArea(height: float32, width: float32): float32 {
	return height * width / 2;
}

// stbtt__fill_active_edges_new: scanline is buf[0..], the fill row starts at buf[fillBase].
function fillActiveEdges(
	buf: float32[],
	fillBase: int32,
	len: int32,
	arena: ActiveEdge[],
	first: int32,
	yTop: float32,
): void {
	const yBottom: float32 = yTop + 1;
	let at = first;
	while (at >= 0) {
		const e = arena[at];
		if (e.fdx == 0) {
			const x0 = e.fx;
			if (x0 < (len as float32)) {
				if (x0 >= 0) {
					handleClippedEdge(buf, 0, truncInt(x0 as float64), e, x0, yTop, x0, yBottom);
					handleClippedEdge(
						buf, fillBase - 1, truncInt(x0 as float64) + 1, e, x0, yTop, x0, yBottom,
					);
				} else {
					handleClippedEdge(buf, fillBase - 1, 0, e, x0, yTop, x0, yBottom);
				}
			}
		} else {
			let x0 = e.fx;
			let dx = e.fdx;
			let xb: float32 = x0 + dx;
			let xTop: float32 = 0;
			let xBottom: float32 = 0;
			let sy0: float32 = 0;
			let sy1: float32 = 0;
			let dy = e.fdy;
			if (e.sy > yTop) {
				xTop = x0 + dx * (e.sy - yTop);
				sy0 = e.sy;
			} else {
				xTop = x0;
				sy0 = yTop;
			}
			if (e.ey < yBottom) {
				xBottom = x0 + dx * (e.ey - yTop);
				sy1 = e.ey;
			} else {
				xBottom = xb;
				sy1 = yBottom;
			}
			if (xTop >= 0 && xBottom >= 0 && xTop < (len as float32) && xBottom < (len as float32)) {
				if (truncInt(xTop as float64) == truncInt(xBottom as float64)) {
					const x = truncInt(xTop as float64);
					const height: float32 = (sy1 - sy0) * e.direction;
					const right = (x as float32) + 1.0;
					buf[x] += positionTrapezoidArea(height, xTop, right, xBottom, right);
					const filled = fillBase + x;
					buf[filled] += height;
				} else {
					if (xTop > xBottom) {
						sy0 = yBottom - (sy0 - yTop);
						sy1 = yBottom - (sy1 - yTop);
						let t = sy0;
						sy0 = sy1;
						sy1 = t;
						t = xBottom;
						xBottom = xTop;
						xTop = t;
						dx = -dx;
						dy = -dy;
						t = x0;
						x0 = xb;
						xb = t;
					}
					const x1 = truncInt(xTop as float64);
					const x2 = truncInt(xBottom as float64);
					let yCrossing: float32 = yTop + dy * (((x1 + 1) as float32) - x0);
					let yFinal: float32 = yTop + dy * ((x2 as float32) - x0);
					if (yCrossing > yBottom) { yCrossing = yBottom; }
					const sign = e.direction;
					let area: float32 = sign * (yCrossing - sy0);
					buf[x1] += triangleArea(area, ((x1 + 1) as float32) - xTop);
					if (yFinal > yBottom) {
						yFinal = yBottom;
						dy = (yFinal - yCrossing) / ((x2 - (x1 + 1)) as float32);
					}
					const step: float32 = sign * dy;
					for (let x: int32 = x1 + 1; x < x2; x++) {
						buf[x] += area + step / 2;
						area += step;
					}
					const rightEdge = (x2 as float32) + 1.0;
					buf[x2] += area + sign * positionTrapezoidArea(
						sy1 - yFinal, x2 as float32, rightEdge, xBottom, rightEdge,
					);
					const filledEnd = fillBase + x2;
					buf[filledEnd] += sign * (sy1 - sy0);
				}
			} else {
				for (let x: int32 = 0; x < len; x++) {
					const y0 = yTop;
					const left = x as float32;
					const right = (x + 1) as float32;
					const x3 = xb;
					const y3 = yBottom;
					const y1: float32 = (left - x0) / dx + yTop;
					const y2: float32 = (right - x0) / dx + yTop;
					if (x0 < left && x3 > right) {
						handleClippedEdge(buf, 0, x, e, x0, y0, left, y1);
						handleClippedEdge(buf, 0, x, e, left, y1, right, y2);
						handleClippedEdge(buf, 0, x, e, right, y2, x3, y3);
					} else if (x3 < left && x0 > right) {
						handleClippedEdge(buf, 0, x, e, x0, y0, right, y2);
						handleClippedEdge(buf, 0, x, e, right, y2, left, y1);
						handleClippedEdge(buf, 0, x, e, left, y1, x3, y3);
					} else if (x0 < left && x3 > left) {
						handleClippedEdge(buf, 0, x, e, x0, y0, left, y1);
						handleClippedEdge(buf, 0, x, e, left, y1, x3, y3);
					} else if (x3 < left && x0 > left) {
						handleClippedEdge(buf, 0, x, e, x0, y0, left, y1);
						handleClippedEdge(buf, 0, x, e, left, y1, x3, y3);
					} else if (x0 < right && x3 > right) {
						handleClippedEdge(buf, 0, x, e, x0, y0, right, y2);
						handleClippedEdge(buf, 0, x, e, right, y2, x3, y3);
					} else if (x3 < right && x0 > right) {
						handleClippedEdge(buf, 0, x, e, x0, y0, right, y2);
						handleClippedEdge(buf, 0, x, e, right, y2, x3, y3);
					} else {
						handleClippedEdge(buf, 0, x, e, x0, y0, x3, y3);
					}
				}
			}
		}
		at = e.next;
	}
}

// stbtt__rasterize_sorted_edges (rasterizer version 2): `edges[n]` is the sentinel.
function rasterizeSortedEdges(
	pixels: Span<uint8>,
	width: int32,
	height: int32,
	stride: int32,
	edges: Edge[],
	n: int32,
	offX: int32,
	offY: int32,
): void {
	let arena: ActiveEdge[] = [];
	let active: int32 = -1;
	let buf: float32[] = new Array<float32>(width * 2 + 1);
	let y: int32 = offY;
	let ei: int32 = 0;
	let sentinel = edges[n];
	sentinel.y0 = ((offY + height) as float32) + 1;
	edges[n] = sentinel;
	for (let j: int32 = 0; j < height; j++) {
		const scanYTop: float32 = (y as float32) + 0.0;
		const scanYBottom: float32 = (y as float32) + 1.0;
		for (let i: int32 = 0; i < width * 2 + 1; i++) { buf[i] = 0; }
		let previous: int32 = -1;
		let at = active;
		while (at >= 0) {
			const z = arena[at];
			if (z.ey <= scanYTop) {
				if (previous < 0) {
					active = z.next;
				} else {
					arena[previous].next = z.next;
				}
			} else {
				previous = at;
			}
			at = z.next;
		}
		while (edges[ei].y0 <= scanYBottom) {
			if (edges[ei].y0 != edges[ei].y1) {
				let z = newActive(edges[ei], offX, scanYTop);
				if (j == 0 && offY != 0) {
					if (z.ey < scanYTop) { z.ey = scanYTop; }
				}
				z.next = active;
				arena.push(z);
				active = (arena.length as int32) - 1;
			}
			ei += 1;
		}
		if (active >= 0) { fillActiveEdges(buf, width + 1, width, arena, active, scanYTop); }
		let sum: float32 = 0;
		for (let i: int32 = 0; i < width; i++) {
			sum += buf[width + i];
			let k: float32 = buf[i] + sum;
			k = (Math.abs(k as float64) as float32) * 255 + 0.5;
			let m = truncInt(k as float64);
			if (m > 255) { m = 255; }
			pixels[j * stride + i] = (m & 0xFF) as uint8;
		}
		at = active;
		while (at >= 0) {
			arena[at].fx += arena[at].fdx;
			at = arena[at].next;
		}
		y += 1;
	}
}

function rasterizeContours(
	pixels: Span<uint8>,
	width: int32,
	height: int32,
	stride: int32,
	flat: Flattened,
	scaleX: float32,
	scaleY: float32,
	shiftX: float32,
	shiftY: float32,
	offX: int32,
	offY: int32,
	invert: boolean,
): void {
	const yScaleInv: float32 = invert ? -scaleY : scaleY;
	let edges: Edge[] = [];
	let m: int32 = 0;
	for (let i: int32 = 0; i < (flat.lengths.length as int32); i++) {
		const count = flat.lengths[i];
		let j = count - 1;
		for (let k: int32 = 0; k < count; k++) {
			const pj = flat.points[m + j];
			const pk = flat.points[m + k];
			j = k;
			if (pj.y == pk.y) { continue; }
			const flip = invert ? pj.y > pk.y : pj.y < pk.y;
			const a = flip ? pj : pk;
			const b = flip ? pk : pj;
			edges.push({
				x0: a.x * scaleX + shiftX,
				y0: a.y * yScaleInv + shiftY,
				x1: b.x * scaleX + shiftX,
				y1: b.y * yScaleInv + shiftY,
				invert: flip,
			});
		}
		m += count;
	}
	const n = edges.length as int32;
	edges.push({ x0: 0, y0: 0, x1: 0, y1: 0, invert: false });
	quicksortEdges(edges, 0, n);
	insertionSortEdges(edges, n);
	rasterizeSortedEdges(pixels, width, height, stride, edges, n, offX, offY);
}

// stbtt_Rasterize: coverage of `vertices` into a width x height window of `pixels`.
export function rasterize(
	pixels: Span<uint8>,
	width: int32,
	height: int32,
	stride: int32,
	flatnessInPixels: float32,
	vertices: Readonly<Span<Vertex>>,
	scaleX: float32,
	scaleY: float32,
	shiftX: float32,
	shiftY: float32,
	offX: int32,
	offY: int32,
	invert: boolean,
): void {
	const scale: float32 = scaleX > scaleY ? scaleY : scaleX;
	const flat = flattenCurves(vertices, flatnessInPixels / scale);
	if (flat.lengths.length == 0) { return; }
	rasterizeContours(
		pixels, width, height, stride, flat, scaleX, scaleY, shiftX, shiftY, offX, offY, invert,
	);
}

// stbtt_MakeGlyphBitmapSubpixel: the rasterizer glyph.c runs on a glyph's own outline.
export function makeGlyphBitmapSubpixel(
	info: FontInfo,
	pixels: Span<uint8>,
	outWidth: int32,
	outHeight: int32,
	outStride: int32,
	scaleX: float32,
	scaleY: float32,
	shiftX: float32,
	shiftY: float32,
	glyph: int32,
): void {
	const vertices = getGlyphShape(info, glyph);
	const box = getGlyphBitmapBoxSubpixel(info, glyph, scaleX, scaleY, shiftX, shiftY);
	if (outWidth != 0 && outHeight != 0) {
		rasterize(
			pixels, outWidth, outHeight, outStride, FLATNESS_IN_PIXELS, vertices,
			scaleX, scaleY, shiftX, shiftY, box.x0, box.y0, true,
		);
	}
}
