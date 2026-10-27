import { Vertex, VERTEX_LINE, VERTEX_MOVE, truncInt, wrapInt16 } from "./trueType/fontInfo";
import { rasterize } from "./trueType/rasterize";

export struct Pt {
	x: float64;
	y: float64;
}

export class Path {
	xy: float64[] = [];
	n: int32 = 0;
}

export class Painter {
	pixels: uint8[];
	scratch: uint8[];
	width: int32;
	height: int32;
	padX: int32;
	padY: int32;
	cellWidth: int32;
	cellHeight: int32;
	boxThickness: int32;
	failed: boolean = false;
	flat: Path = new Path();
	left: Path = new Path();
	right: Path = new Path();
	inset: Path = new Path();
	poly: Path = new Path();

	constructor(cellWidth: int32, cellHeight: int32, boxThickness: int32) {
		this.padX = spritePadding(cellWidth);
		this.padY = spritePadding(cellHeight);
		this.width = spriteCanvasWidth(cellWidth);
		this.height = spriteCanvasHeight(cellHeight);
		this.cellWidth = cellWidth;
		this.cellHeight = cellHeight;
		this.boxThickness = boxThickness;
		this.pixels = zeroed(this.width * this.height);
		this.scratch = zeroed(this.width * this.height);
	}
}

function zeroed(count: int32): uint8[] {
	const bytes: uint8[] = new Array<uint8>(count);
	for (let i: int32 = 0; i < count; i++) { bytes[i] = 0; }
	return bytes;
}

export function spritePadding(cellSize: int32): int32 {
	return cellSize > 0 ? cellSize / 4 : 0;
}

export function spriteCanvasWidth(cellWidth: int32): int32 {
	return cellWidth + 2 * spritePadding(cellWidth);
}

export function spriteCanvasHeight(cellHeight: int32): int32 {
	return cellHeight + 2 * spritePadding(cellHeight);
}

function putPixel(p: Painter, x: int32, y: int32, value: uint8): void {
	const px: int32 = x + p.padX;
	const py: int32 = y + p.padY;
	if (px < 0 || py < 0 || px >= p.width || py >= p.height) { return; }
	p.pixels[py * p.width + px] = value;
}

export function fillBox(
	p: Painter, x0: int32, y0: int32, x1: int32, y1: int32, value: uint8,
): void {
	const left: int32 = x0 < x1 ? x0 : x1;
	const right: int32 = x0 < x1 ? x1 : x0;
	const top: int32 = y0 < y1 ? y0 : y1;
	const bottom: int32 = y0 < y1 ? y1 : y0;
	for (let y: int32 = top; y < bottom; y++) {
		for (let x: int32 = left; x < right; x++) { putPixel(p, x, y, value); }
	}
}

export function subSat(a: int32, b: int32): int32 {
	return a > b ? a - b : 0;
}

function fracMin(fraction: float64, size: int32): int32 {
	const s: float64 = size as float64;
	return truncInt(s - Math.round((1.0 - fraction) * s));
}

function fracMax(fraction: float64, size: int32): int32 {
	return truncInt(Math.round(fraction * (size as float64)));
}

export function fillFractions(
	p: Painter, x0: float64, x1: float64, y0: float64, y1: float64,
): void {
	fillBox(
		p, fracMin(x0, p.cellWidth), fracMin(y0, p.cellHeight),
		fracMax(x1, p.cellWidth), fracMax(y1, p.cellHeight), 255,
	);
}

function pathPush(path: Path, x: float64, y: float64): void {
	if (path.n > 0 && Math.abs(path.xy[2 * (path.n - 1)] - x) < 1e-9 &&
		Math.abs(path.xy[2 * (path.n - 1) + 1] - y) < 1e-9) {
		return;
	}
	if (2 * path.n == (path.xy.length as int32)) {
		path.xy.push(x);
		path.xy.push(y);
	} else {
		path.xy[2 * path.n] = x;
		path.xy[2 * path.n + 1] = y;
	}
	path.n++;
}

export function pathReset(path: Path): void {
	path.n = 0;
}

export function pathAdd(path: Path, x: float64, y: float64): void {
	pathPush(path, x, y);
}

export function distance(a: Pt, b: Pt): float64 {
	return Math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
}

export function pathCubic(path: Path, p0: Pt, p1: Pt, p2: Pt, p3: Pt): void {
	const length: float64 = distance(p0, p1) + distance(p1, p2) + distance(p2, p3);
	let steps: int32 = truncInt(Math.ceil(length * 1.5));
	if (steps < 8) { steps = 8; }
	if (steps > 256) { steps = 256; }
	for (let i: int32 = 1; i <= steps; i++) {
		const t: float64 = (i as float64) / (steps as float64);
		const u: float64 = 1.0 - t;
		const a: float64 = u * u * u;
		const b: float64 = 3.0 * u * u * t;
		const c: float64 = 3.0 * u * t * t;
		const d: float64 = t * t * t;
		pathPush(
			path, a * p0.x + b * p1.x + c * p2.x + d * p3.x,
			a * p0.y + b * p1.y + c * p2.y + d * p3.y,
		);
	}
}

// Coverage of the polygons in `xy` (x, y pairs; `counts` points per contour), quantized to the
// 16-bit outline units the glyph rasterizer works in. False when the points reach too far for it.
export function polygonCoverage(
	coverage: Span<uint8>, width: int32, height: int32,
	xy: Readonly<Span<float64>>, counts: Readonly<Span<int32>>,
): boolean {
	let total: int32 = 0;
	for (let i: int32 = 0; i < (counts.length as int32); i++) { total += counts[i]; }
	let reach: float64 = 1.0;
	for (let i: int32 = 0; i < total * 2; i++) {
		const magnitude: float64 = Math.abs(xy[i]);
		if (magnitude > reach) { reach = magnitude; }
	}
	let quantum: float64 = Math.floor(32000.0 / reach);
	if (quantum > 4096.0) { quantum = 4096.0; }
	if (quantum < 1.0) { return false; }
	let vertices: Vec<Vertex> = [];
	let at: int32 = 0;
	for (let i: int32 = 0; i < (counts.length as int32); i++) {
		for (let k: int32 = 0; k < counts[i]; k++) {
			vertices.push({
				x: wrapInt16(truncInt(Math.floor(xy[2 * at] * quantum + 0.5))),
				y: wrapInt16(truncInt(Math.floor(xy[2 * at + 1] * quantum + 0.5))),
				cx: 0,
				cy: 0,
				cx1: 0,
				cy1: 0,
				kind: k == 0 ? VERTEX_MOVE : VERTEX_LINE,
			});
			at++;
		}
	}
	const scale: float32 = (1.0 / quantum) as float32;
	rasterize(coverage, width, height, width, 0.35, vertices, scale, scale, 0.0, 0.0, 0, 0, false);
	return true;
}

export function fillContours(p: Painter, xy: float64[], counts: int32[], color: uint8): void {
	let total: int32 = 0;
	for (let i: int32 = 0; i < (counts.length as int32); i++) { total += counts[i]; }
	let shifted: float64[] = new Array<float64>(total * 2);
	for (let i: int32 = 0; i < total; i++) {
		shifted[2 * i] = xy[2 * i] + (p.padX as float64);
		shifted[2 * i + 1] = xy[2 * i + 1] + (p.padY as float64);
	}
	const need: int32 = p.width * p.height;
	for (let i: int32 = 0; i < need; i++) { p.scratch[i] = 0; }
	if (!polygonCoverage(p.scratch, p.width, p.height, shifted, counts)) {
		p.failed = true;
		return;
	}
	for (let i: int32 = 0; i < need; i++) {
		if (p.scratch[i] == 0) { continue; }
		const coverage: float64 = (p.scratch[i] as float64) / 255.0;
		const base: float64 = p.pixels[i] as float64;
		const blended: float64 = Math.floor(base + ((color as float64) - base) * coverage + 0.5);
		p.pixels[i] = truncInt(blended) as uint8;
	}
}

export function fillPolygon(p: Painter, xy: float64[], n: int32, color: uint8): void {
	fillContours(p, xy, [n], color);
}

export function fillTriangle(p: Painter, a: Pt, b: Pt, c: Pt): void {
	fillPolygon(p, [a.x, a.y, b.x, b.y, c.x, c.y], 3, 255);
}

export function offsetSide(path: Path, offset: float64, out: Path): void {
	pathReset(out);
	const n: int32 = path.n;
	if (n < 2) { return; }
	const p: float64[] = path.xy;
	for (let i: int32 = 0; i < n; i++) {
		const hasBefore: boolean = i > 0;
		const hasAfter: boolean = i + 1 < n;
		const here: Pt = { x: p[2 * i], y: p[2 * i + 1] };
		let before: Pt = { x: 0.0, y: 0.0 };
		let after: Pt = { x: 0.0, y: 0.0 };
		if (hasBefore) {
			const prior: Pt = { x: p[2 * (i - 1)], y: p[2 * (i - 1) + 1] };
			const len: float64 = distance(prior, here);
			before = { x: (here.x - prior.x) / len, y: (here.y - prior.y) / len };
		}
		if (hasAfter) {
			const next: Pt = { x: p[2 * (i + 1)], y: p[2 * (i + 1) + 1] };
			const len: float64 = distance(here, next);
			after = { x: (next.x - here.x) / len, y: (next.y - here.y) / len };
		}
		const unit0: Pt = hasBefore ? before : after;
		const unit1: Pt = hasAfter ? after : before;
		const n0: Pt = { x: -unit0.y, y: unit0.x };
		const n1: Pt = { x: -unit1.y, y: unit1.x };
		if (!hasBefore || !hasAfter) {
			const edge: Pt = hasBefore ? n0 : n1;
			pathPush(out, here.x + edge.x * offset, here.y + edge.y * offset);
			continue;
		}
		const dot: float64 = before.x * after.x + before.y * after.y;
		const cross: float64 = before.x * after.y - before.y * after.x;
		const along: float64 = 1.0 + dot;
		const outer: boolean = cross * offset < 0.0;
		if (outer && (along < 0.02 || Math.sqrt(2.0 / along) > 10.0)) {
			pathPush(out, here.x + n0.x * offset, here.y + n0.y * offset);
			pathPush(out, here.x + n1.x * offset, here.y + n1.y * offset);
		} else if (along < 1e-9) {
			pathPush(out, here.x + n0.x * offset, here.y + n0.y * offset);
		} else {
			pathPush(
				out, here.x + (n0.x + n1.x) * offset / along,
				here.y + (n0.y + n1.y) * offset / along,
			);
		}
	}
}

export function strokePath(p: Painter, path: Path, width: float64, color: uint8): void {
	offsetSide(path, width / 2.0, p.left);
	offsetSide(path, -width / 2.0, p.right);
	pathReset(p.poly);
	for (let i: int32 = 0; i < p.left.n; i++) {
		pathPush(p.poly, p.left.xy[2 * i], p.left.xy[2 * i + 1]);
	}
	for (let i: int32 = p.right.n - 1; i >= 0; i--) {
		pathPush(p.poly, p.right.xy[2 * i], p.right.xy[2 * i + 1]);
	}
	if (p.poly.n >= 3) { fillPolygon(p, p.poly.xy, p.poly.n, color); }
}

export function strokeLine(p: Painter, a: Pt, b: Pt, width: float64): void {
	pathReset(p.flat);
	pathPush(p.flat, a.x, a.y);
	pathPush(p.flat, b.x, b.y);
	strokePath(p, p.flat, width, 255);
}

export function insetTriangleRing(p: Painter, a: Pt, b: Pt, c: Pt, thickness: float64): void {
	const la: float64 = distance(b, c);
	const lb: float64 = distance(a, c);
	const lc: float64 = distance(a, b);
	const perimeter: float64 = la + lb + lc;
	const area: float64 = Math.abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2.0;
	const inradius: float64 = 2.0 * area / perimeter;
	const incenter: Pt = {
		x: (la * a.x + lb * b.x + lc * c.x) / perimeter,
		y: (la * a.y + lb * b.y + lc * c.y) / perimeter,
	};
	const k: float64 = inradius > thickness ? (inradius - thickness) / inradius : 0.0;
	const corners: Pt[] = [a, b, c];
	let inner: float64[] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
	for (let i: int32 = 0; i < 3; i++) {
		inner[2 * i] = incenter.x + k * (corners[i].x - incenter.x);
		inner[2 * i + 1] = incenter.y + k * (corners[i].y - incenter.y);
	}
	const ring: float64[] = [
		a.x, a.y, b.x, b.y, c.x, c.y,
		inner[4], inner[5], inner[2], inner[3], inner[0], inner[1],
	];
	fillContours(p, ring, [3, 3], 255);
}

export function flipHorizontal(p: Painter): void {
	for (let y: int32 = 0; y < p.height; y++) {
		const row: int32 = y * p.width;
		for (let x: int32 = 0; x < p.width / 2; x++) {
			const t: uint8 = p.pixels[row + x];
			p.pixels[row + x] = p.pixels[row + p.width - 1 - x];
			p.pixels[row + p.width - 1 - x] = t;
		}
	}
}

export function minDouble(a: float64, b: float64): float64 {
	return a < b ? a : b;
}
