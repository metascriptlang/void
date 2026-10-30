import {
	CAP_BUTT,
	CAP_ROUND,
	CAP_SQUARE,
	FILLRULE_EVENODD,
	FILLRULE_NONZERO,
	JOIN_BEVEL,
	JOIN_ROUND,
	PAINT_COLOR,
	PAINT_LINEAR_GRADIENT,
	PAINT_NONE,
	PAINT_ORDER_FILL,
	PAINT_ORDER_STROKE,
	PAINT_RADIAL_GRADIENT,
	Paint,
	Shape,
	SvgImage,
} from "./image";
import { floatToInt } from "./text";
import { NSVG_PI, absf, sqrtf } from "./xform";

const SUBSAMPLES: int32 = 5;
const FIXSHIFT: int32 = 10;
const FIX: int32 = 1024;
const FIXMASK: int32 = 1023;
const MAX_WEIGHT: int32 = 51;

const PT_CORNER: int32 = 1;
const PT_BEVEL: int32 = 2;
const PT_LEFT: int32 = 4;

const NORMALIZE_EPSILON: float32 = 1e-6;
const MITER_EPSILON: float32 = 0.000001;
const MITER_SCALE_LIMIT: float32 = 600.0;
const MIN_STROKE_WIDTH: float32 = 0.01;
const TESSELLATION_TOLERANCE: float32 = 0.05;
const DISTANCE_TOLERANCE: float32 = 0.01;

class Corner {
	x: float32 = 0.0;
	y: float32 = 0.0;
}

class Cache {
	kind: int32 = PAINT_NONE;
	alpha: int32 = 0;
	xform: float32[] = [0, 0, 0, 0, 0, 0];
	colors: int32[] = [];
}

class Rasterizer {
	tessTol: float32 = TESSELLATION_TOLERANCE;
	distTol: float32 = DISTANCE_TOLERANCE;
	ex0: float32[] = [];
	ey0: float32[] = [];
	ex1: float32[] = [];
	ey1: float32[] = [];
	edir: int32[] = [];
	nedges: int32 = 0;
	px: float32[] = [];
	py: float32[] = [];
	pdx: float32[] = [];
	pdy: float32[] = [];
	plen: float32[] = [];
	pdmx: float32[] = [];
	pdmy: float32[] = [];
	pflags: int32[] = [];
	npoints: int32 = 0;
	qx: float32[] = [];
	qy: float32[] = [];
	qflags: int32[] = [];
	nq: int32 = 0;
	ndx: float32 = 0.0;
	ndy: float32 = 0.0;
	ax: int32[] = [];
	adx: int32[] = [];
	aey: float32[] = [];
	adir: int32[] = [];
	anext: int32[] = [];
	na: int32 = 0;
	freelist: int32 = -1;
	scanline: uint8[] = [];
	xmin: int32 = 0;
	xmax: int32 = 0;
	width: int32 = 0;
	height: int32 = 0;
}

function cosf(x: float32): float32 {
	return Math.cos(x as float64) as float32;
}

function sinf(x: float32): float32 {
	return Math.sin(x as float64) as float32;
}

function atan2f(y: float32, x: float32): float32 {
	return Math.atan2(y as float64, x as float64) as float32;
}

function acosf(x: float32): float32 {
	return Math.acos(x as float64) as float32;
}

function ceilf(x: float32): float32 {
	return Math.ceil(x as float64) as float32;
}

// nsvg__roundf: x + 0.5 is a double in the C and floorf takes it back as a float.
function roundf(x: float32): float32 {
	if (x >= 0) {
		const up: float32 = ((x as float64) + 0.5) as float32;
		return Math.floor(up as float64) as float32;
	}
	const down: float32 = ((x as float64) - 0.5) as float32;
	return Math.ceil(down as float64) as float32;
}

function clampf(a: float32, mn: float32, mx: float32): float32 {
	if (a != a) { return mn; }
	return a < mn ? mn : (a > mx ? mx : a);
}

function ptEquals(x1: float32, y1: float32, x2: float32, y2: float32, tol: float32): boolean {
	const dx: float32 = x2 - x1;
	const dy: float32 = y2 - y1;
	const lhs: float32 = dx * dx + dy * dy;
	const rhs: float32 = tol * tol;
	return lhs < rhs;
}

function setPoint(r: Rasterizer, k: int32, x: float32, y: float32, flags: int32): void {
	if (k >= (r.px.length as int32)) {
		r.px.push(0.0);
		r.py.push(0.0);
		r.pdx.push(0.0);
		r.pdy.push(0.0);
		r.plen.push(0.0);
		r.pdmx.push(0.0);
		r.pdmy.push(0.0);
		r.pflags.push(0);
	}
	r.px[k] = x;
	r.py[k] = y;
	r.pflags[k] = flags & 255;
}

function addPathPoint(r: Rasterizer, x: float32, y: float32, flags: int32): void {
	if (r.npoints > 0) {
		const last = r.npoints - 1;
		if (ptEquals(r.px[last], r.py[last], x, y, r.distTol)) {
			r.pflags[last] = (r.pflags[last] | flags) & 255;
			return;
		}
	}
	setPoint(r, r.npoints, x, y, flags);
	r.npoints += 1;
}

function appendPathPoint(r: Rasterizer, x: float32, y: float32, flags: int32): void {
	setPoint(r, r.npoints, x, y, flags);
	r.npoints += 1;
}

function duplicatePoints(r: Rasterizer): void {
	while ((r.qx.length as int32) < r.npoints) {
		r.qx.push(0.0);
		r.qy.push(0.0);
		r.qflags.push(0);
	}
	for (let i: int32 = 0; i < r.npoints; i++) {
		r.qx[i] = r.px[i];
		r.qy[i] = r.py[i];
		r.qflags[i] = r.pflags[i];
	}
	r.nq = r.npoints;
}

function addEdge(r: Rasterizer, x0: float32, y0: float32, x1: float32, y1: float32): void {
	if (y0 == y1) { return; }
	const k = r.nedges;
	if (k >= (r.ex0.length as int32)) {
		r.ex0.push(0.0);
		r.ey0.push(0.0);
		r.ex1.push(0.0);
		r.ey1.push(0.0);
		r.edir.push(0);
	}
	r.nedges += 1;
	if (y0 < y1) {
		r.ex0[k] = x0;
		r.ey0[k] = y0;
		r.ex1[k] = x1;
		r.ey1[k] = y1;
		r.edir[k] = 1;
	} else {
		r.ex0[k] = x1;
		r.ey0[k] = y1;
		r.ex1[k] = x0;
		r.ey1[k] = y0;
		r.edir[k] = -1;
	}
}

// nsvg__normalize: the unit direction lands in r.ndx, r.ndy; the result is the length.
function normalize(r: Rasterizer, x: float32, y: float32): float32 {
	const sum: float32 = x * x + y * y;
	const d: float32 = sqrtf(sum);
	let nx: float32 = x;
	let ny: float32 = y;
	if (d > NORMALIZE_EPSILON) {
		const id: float32 = 1.0 / d;
		nx = x * id;
		ny = y * id;
	}
	r.ndx = nx;
	r.ndy = ny;
	return d;
}

function flattenCubicBez(
	r: Rasterizer,
	x1: float32,
	y1: float32,
	x2: float32,
	y2: float32,
	x3: float32,
	y3: float32,
	x4: float32,
	y4: float32,
	level: int32,
	kind: int32,
): void {
	if (level > 10) { return; }
	const x12: float32 = (x1 + x2) * 0.5;
	const y12: float32 = (y1 + y2) * 0.5;
	const x23: float32 = (x2 + x3) * 0.5;
	const y23: float32 = (y2 + y3) * 0.5;
	const x34: float32 = (x3 + x4) * 0.5;
	const y34: float32 = (y3 + y4) * 0.5;
	const x123: float32 = (x12 + x23) * 0.5;
	const y123: float32 = (y12 + y23) * 0.5;
	const dx: float32 = x4 - x1;
	const dy: float32 = y4 - y1;
	const d2: float32 = absf((x2 - x4) * dy - (y2 - y4) * dx);
	const d3: float32 = absf((x3 - x4) * dy - (y3 - y4) * dx);
	const flat: float32 = (d2 + d3) * (d2 + d3);
	const limit: float32 = r.tessTol * (dx * dx + dy * dy);
	if (flat < limit) {
		addPathPoint(r, x4, y4, kind);
		return;
	}
	const x234: float32 = (x23 + x34) * 0.5;
	const y234: float32 = (y23 + y34) * 0.5;
	const x1234: float32 = (x123 + x234) * 0.5;
	const y1234: float32 = (y123 + y234) * 0.5;
	flattenCubicBez(r, x1, y1, x12, y12, x123, y123, x1234, y1234, level + 1, 0);
	flattenCubicBez(r, x1234, y1234, x234, y234, x34, y34, x4, y4, level + 1, kind);
}

function flattenPath(r: Rasterizer, pts: float32[], npts: int32, scale: float32, kind: int32): void {
	r.npoints = 0;
	const x0: float32 = pts[0] * scale;
	const y0: float32 = pts[1] * scale;
	addPathPoint(r, x0, y0, kind);
	for (let i: int32 = 0; i < npts - 1; i += 3) {
		const b = i * 2;
		const a0: float32 = pts[b] * scale;
		const a1: float32 = pts[b + 1] * scale;
		const a2: float32 = pts[b + 2] * scale;
		const a3: float32 = pts[b + 3] * scale;
		const a4: float32 = pts[b + 4] * scale;
		const a5: float32 = pts[b + 5] * scale;
		const a6: float32 = pts[b + 6] * scale;
		const a7: float32 = pts[b + 7] * scale;
		flattenCubicBez(r, a0, a1, a2, a3, a4, a5, a6, a7, 0, kind);
	}
}

function flattenShape(r: Rasterizer, shape: Shape, scale: float32): void {
	for (let k: int32 = 0; k < (shape.paths.length as int32); k++) {
		const path = shape.paths[k];
		flattenPath(r, path.pts, path.npts, scale, 0);
		const x0: float32 = path.pts[0] * scale;
		const y0: float32 = path.pts[1] * scale;
		addPathPoint(r, x0, y0, 0);
		let j = r.npoints - 1;
		for (let i: int32 = 0; i < r.npoints; i++) {
			addEdge(r, r.px[j], r.py[j], r.px[i], r.py[i]);
			j = i;
		}
	}
}

function initClosed(
	r: Rasterizer,
	left: Corner,
	right: Corner,
	p0: int32,
	p1: int32,
	lineWidth: float32,
): void {
	const w: float32 = lineWidth * 0.5;
	const len = normalize(r, r.px[p1] - r.px[p0], r.py[p1] - r.py[p0]);
	const dx = r.ndx;
	const dy = r.ndy;
	const mx: float32 = dx * len * 0.5;
	const my: float32 = dy * len * 0.5;
	const px: float32 = r.px[p0] + mx;
	const py: float32 = r.py[p0] + my;
	const dlx: float32 = dy;
	const dly: float32 = -dx;
	left.x = px - dlx * w;
	left.y = py - dly * w;
	right.x = px + dlx * w;
	right.y = py + dly * w;
}

function buttCap(
	r: Rasterizer,
	left: Corner,
	right: Corner,
	p: int32,
	dx: float32,
	dy: float32,
	lineWidth: float32,
	connect: boolean,
): void {
	const w: float32 = lineWidth * 0.5;
	const px = r.px[p];
	const py = r.py[p];
	const dlx: float32 = dy;
	const dly: float32 = -dx;
	const lx: float32 = px - dlx * w;
	const ly: float32 = py - dly * w;
	const rx: float32 = px + dlx * w;
	const ry: float32 = py + dly * w;
	addEdge(r, lx, ly, rx, ry);
	if (connect) {
		addEdge(r, left.x, left.y, lx, ly);
		addEdge(r, rx, ry, right.x, right.y);
	}
	left.x = lx;
	left.y = ly;
	right.x = rx;
	right.y = ry;
}

function squareCap(
	r: Rasterizer,
	left: Corner,
	right: Corner,
	p: int32,
	dx: float32,
	dy: float32,
	lineWidth: float32,
	connect: boolean,
): void {
	const w: float32 = lineWidth * 0.5;
	const px: float32 = r.px[p] - dx * w;
	const py: float32 = r.py[p] - dy * w;
	const dlx: float32 = dy;
	const dly: float32 = -dx;
	const lx: float32 = px - dlx * w;
	const ly: float32 = py - dly * w;
	const rx: float32 = px + dlx * w;
	const ry: float32 = py + dly * w;
	addEdge(r, lx, ly, rx, ry);
	if (connect) {
		addEdge(r, left.x, left.y, lx, ly);
		addEdge(r, rx, ry, right.x, right.y);
	}
	left.x = lx;
	left.y = ly;
	right.x = rx;
	right.y = ry;
}

function roundCap(
	r: Rasterizer,
	left: Corner,
	right: Corner,
	p: int32,
	dx: float32,
	dy: float32,
	lineWidth: float32,
	ncap: int32,
	connect: boolean,
): void {
	const w: float32 = lineWidth * 0.5;
	const px = r.px[p];
	const py = r.py[p];
	const dlx: float32 = dy;
	const dly: float32 = -dx;
	let lx: float32 = 0.0;
	let ly: float32 = 0.0;
	let rx: float32 = 0.0;
	let ry: float32 = 0.0;
	let prevx: float32 = 0.0;
	let prevy: float32 = 0.0;
	for (let i: int32 = 0; i < ncap; i++) {
		const fraction: float32 = (i as float32) / ((ncap - 1) as float32);
		const a: float32 = fraction * NSVG_PI;
		const ax: float32 = cosf(a) * w;
		const ay: float32 = sinf(a) * w;
		const x: float32 = px - dlx * ax - dx * ay;
		const y: float32 = py - dly * ax - dy * ay;
		if (i > 0) { addEdge(r, prevx, prevy, x, y); }
		prevx = x;
		prevy = y;
		if (i == 0) {
			lx = x;
			ly = y;
		} else if (i == ncap - 1) {
			rx = x;
			ry = y;
		}
	}
	if (connect) {
		addEdge(r, left.x, left.y, lx, ly);
		addEdge(r, rx, ry, right.x, right.y);
	}
	left.x = lx;
	left.y = ly;
	right.x = rx;
	right.y = ry;
}

function bevelJoin(
	r: Rasterizer,
	left: Corner,
	right: Corner,
	p0: int32,
	p1: int32,
	lineWidth: float32,
): void {
	const w: float32 = lineWidth * 0.5;
	const dlx0: float32 = r.pdy[p0];
	const dly0: float32 = -r.pdx[p0];
	const dlx1: float32 = r.pdy[p1];
	const dly1: float32 = -r.pdx[p1];
	const x1 = r.px[p1];
	const y1 = r.py[p1];
	const lx0: float32 = x1 - (dlx0 * w);
	const ly0: float32 = y1 - (dly0 * w);
	const rx0: float32 = x1 + (dlx0 * w);
	const ry0: float32 = y1 + (dly0 * w);
	const lx1: float32 = x1 - (dlx1 * w);
	const ly1: float32 = y1 - (dly1 * w);
	const rx1: float32 = x1 + (dlx1 * w);
	const ry1: float32 = y1 + (dly1 * w);
	addEdge(r, lx0, ly0, left.x, left.y);
	addEdge(r, lx1, ly1, lx0, ly0);
	addEdge(r, right.x, right.y, rx0, ry0);
	addEdge(r, rx0, ry0, rx1, ry1);
	left.x = lx1;
	left.y = ly1;
	right.x = rx1;
	right.y = ry1;
}

function miterJoin(
	r: Rasterizer,
	left: Corner,
	right: Corner,
	p0: int32,
	p1: int32,
	lineWidth: float32,
): void {
	const w: float32 = lineWidth * 0.5;
	const dlx0: float32 = r.pdy[p0];
	const dly0: float32 = -r.pdx[p0];
	const dlx1: float32 = r.pdy[p1];
	const dly1: float32 = -r.pdx[p1];
	const x1 = r.px[p1];
	const y1 = r.py[p1];
	let lx1: float32 = 0.0;
	let ly1: float32 = 0.0;
	let rx1: float32 = 0.0;
	let ry1: float32 = 0.0;
	if ((r.pflags[p1] & PT_LEFT) != 0) {
		const lx0: float32 = x1 - r.pdmx[p1] * w;
		const ly0: float32 = y1 - r.pdmy[p1] * w;
		lx1 = lx0;
		ly1 = ly0;
		addEdge(r, lx1, ly1, left.x, left.y);
		const rx0: float32 = x1 + (dlx0 * w);
		const ry0: float32 = y1 + (dly0 * w);
		rx1 = x1 + (dlx1 * w);
		ry1 = y1 + (dly1 * w);
		addEdge(r, right.x, right.y, rx0, ry0);
		addEdge(r, rx0, ry0, rx1, ry1);
	} else {
		const lx0: float32 = x1 - (dlx0 * w);
		const ly0: float32 = y1 - (dly0 * w);
		lx1 = x1 - (dlx1 * w);
		ly1 = y1 - (dly1 * w);
		addEdge(r, lx0, ly0, left.x, left.y);
		addEdge(r, lx1, ly1, lx0, ly0);
		const rx0: float32 = x1 + r.pdmx[p1] * w;
		const ry0: float32 = y1 + r.pdmy[p1] * w;
		rx1 = rx0;
		ry1 = ry0;
		addEdge(r, right.x, right.y, rx1, ry1);
	}
	left.x = lx1;
	left.y = ly1;
	right.x = rx1;
	right.y = ry1;
}

function roundJoin(
	r: Rasterizer,
	left: Corner,
	right: Corner,
	p0: int32,
	p1: int32,
	lineWidth: float32,
	ncap: int32,
): void {
	const w: float32 = lineWidth * 0.5;
	const dlx0: float32 = r.pdy[p0];
	const dly0: float32 = -r.pdx[p0];
	const dlx1: float32 = r.pdy[p1];
	const dly1: float32 = -r.pdx[p1];
	const a0 = atan2f(dly0, dlx0);
	const a1 = atan2f(dly1, dlx1);
	let da: float32 = a1 - a0;
	if (da < NSVG_PI) {
		const turned: float32 = NSVG_PI * 2;
		da = da + turned;
	}
	if (da > NSVG_PI) {
		const turned: float32 = NSVG_PI * 2;
		da = da - turned;
	}
	const arcs: float32 = (absf(da) / NSVG_PI) * (ncap as float32);
	let n = floatToInt(ceilf(arcs));
	if (n < 2) { n = 2; }
	if (n > ncap) { n = ncap; }
	let lx = left.x;
	let ly = left.y;
	let rx = right.x;
	let ry = right.y;
	const x1 = r.px[p1];
	const y1 = r.py[p1];
	for (let i: int32 = 0; i < n; i++) {
		const u: float32 = (i as float32) / ((n - 1) as float32);
		const a: float32 = a0 + u * da;
		const ax: float32 = cosf(a) * w;
		const ay: float32 = sinf(a) * w;
		const lx1: float32 = x1 - ax;
		const ly1: float32 = y1 - ay;
		const rx1: float32 = x1 + ax;
		const ry1: float32 = y1 + ay;
		addEdge(r, lx1, ly1, lx, ly);
		addEdge(r, rx, ry, rx1, ry1);
		lx = lx1;
		ly = ly1;
		rx = rx1;
		ry = ry1;
	}
	left.x = lx;
	left.y = ly;
	right.x = rx;
	right.y = ry;
}

function straightJoin(r: Rasterizer, left: Corner, right: Corner, p1: int32, lineWidth: float32): void {
	const w: float32 = lineWidth * 0.5;
	const lx: float32 = r.px[p1] - (r.pdmx[p1] * w);
	const ly: float32 = r.py[p1] - (r.pdmy[p1] * w);
	const rx: float32 = r.px[p1] + (r.pdmx[p1] * w);
	const ry: float32 = r.py[p1] + (r.pdmy[p1] * w);
	addEdge(r, lx, ly, left.x, left.y);
	addEdge(r, right.x, right.y, rx, ry);
	left.x = lx;
	left.y = ly;
	right.x = rx;
	right.y = ry;
}

function curveDivs(radius: float32, arc: float32, tol: float32): int32 {
	const ratio: float32 = radius / (radius + tol);
	const da: float32 = acosf(ratio) * 2.0;
	const span: float32 = arc / da;
	let divs = floatToInt(ceilf(span));
	if (divs < 2) { divs = 2; }
	return divs;
}

function expandStroke(
	r: Rasterizer,
	npoints: int32,
	closed: boolean,
	lineJoin: int32,
	lineCap: int32,
	lineWidth: float32,
): void {
	const half: float32 = lineWidth * 0.5;
	const ncap = curveDivs(half, NSVG_PI, r.tessTol);
	const left = new Corner();
	const right = new Corner();
	const firstLeft = new Corner();
	const firstRight = new Corner();
	let p0: int32 = 0;
	let p1: int32 = 0;
	let s: int32 = 0;
	let e: int32 = 0;
	if (closed) {
		p0 = npoints - 1;
		p1 = 0;
		s = 0;
		e = npoints;
	} else {
		p0 = 0;
		p1 = 1;
		s = 1;
		e = npoints - 1;
	}

	if (closed) {
		initClosed(r, left, right, p0, p1, lineWidth);
		firstLeft.x = left.x;
		firstLeft.y = left.y;
		firstRight.x = right.x;
		firstRight.y = right.y;
	} else {
		normalize(r, r.px[p1] - r.px[p0], r.py[p1] - r.py[p0]);
		const dx = r.ndx;
		const dy = r.ndy;
		if (lineCap == CAP_BUTT) {
			buttCap(r, left, right, p0, dx, dy, lineWidth, false);
		} else if (lineCap == CAP_SQUARE) {
			squareCap(r, left, right, p0, dx, dy, lineWidth, false);
		} else if (lineCap == CAP_ROUND) {
			roundCap(r, left, right, p0, dx, dy, lineWidth, ncap, false);
		}
	}

	for (let j = s; j < e; j++) {
		if ((r.pflags[p1] & PT_CORNER) != 0) {
			if (lineJoin == JOIN_ROUND) {
				roundJoin(r, left, right, p0, p1, lineWidth, ncap);
			} else if (lineJoin == JOIN_BEVEL || (r.pflags[p1] & PT_BEVEL) != 0) {
				bevelJoin(r, left, right, p0, p1, lineWidth);
			} else {
				miterJoin(r, left, right, p0, p1, lineWidth);
			}
		} else {
			straightJoin(r, left, right, p1, lineWidth);
		}
		p0 = p1;
		p1 += 1;
	}

	if (closed) {
		addEdge(r, firstLeft.x, firstLeft.y, left.x, left.y);
		addEdge(r, right.x, right.y, firstRight.x, firstRight.y);
	} else {
		normalize(r, r.px[p1] - r.px[p0], r.py[p1] - r.py[p0]);
		const dx: float32 = -r.ndx;
		const dy: float32 = -r.ndy;
		if (lineCap == CAP_BUTT) {
			buttCap(r, right, left, p1, dx, dy, lineWidth, true);
		} else if (lineCap == CAP_SQUARE) {
			squareCap(r, right, left, p1, dx, dy, lineWidth, true);
		} else if (lineCap == CAP_ROUND) {
			roundCap(r, right, left, p1, dx, dy, lineWidth, ncap, true);
		}
	}
}

function prepareStroke(r: Rasterizer, miterLimit: float32, lineJoin: int32): void {
	let p0 = r.npoints - 1;
	let p1: int32 = 0;
	for (let i: int32 = 0; i < r.npoints; i++) {
		const length = normalize(r, r.px[p1] - r.px[p0], r.py[p1] - r.py[p0]);
		r.pdx[p0] = r.ndx;
		r.pdy[p0] = r.ndy;
		r.plen[p0] = length;
		p0 = p1;
		p1 += 1;
	}

	p0 = r.npoints - 1;
	p1 = 0;
	for (let j: int32 = 0; j < r.npoints; j++) {
		const dlx0: float32 = r.pdy[p0];
		const dly0: float32 = -r.pdx[p0];
		const dlx1: float32 = r.pdy[p1];
		const dly1: float32 = -r.pdx[p1];
		let dmx: float32 = (dlx0 + dlx1) * 0.5;
		let dmy: float32 = (dly0 + dly1) * 0.5;
		const dmr2: float32 = dmx * dmx + dmy * dmy;
		if (dmr2 > MITER_EPSILON) {
			let s2: float32 = 1.0 / dmr2;
			if (s2 > MITER_SCALE_LIMIT) { s2 = MITER_SCALE_LIMIT; }
			dmx = dmx * s2;
			dmy = dmy * s2;
		}
		r.pdmx[p1] = dmx;
		r.pdmy[p1] = dmy;

		let flags: int32 = (r.pflags[p1] & PT_CORNER) != 0 ? PT_CORNER : 0;
		const cross: float32 = r.pdx[p1] * r.pdy[p0] - r.pdx[p0] * r.pdy[p1];
		if (cross > 0.0) { flags = flags | PT_LEFT; }
		if ((flags & PT_CORNER) != 0) {
			const limited: float32 = dmr2 * miterLimit * miterLimit;
			if (limited < 1.0 || lineJoin == JOIN_BEVEL || lineJoin == JOIN_ROUND) {
				flags = flags | PT_BEVEL;
			}
		}
		r.pflags[p1] = flags;
		p0 = p1;
		p1 += 1;
	}
}

function fmodf(a: float32, b: float32): float32 {
	return ((a as float64) % (b as float64)) as float32;
}

function strokeSegment(r: Rasterizer, miterLimit: float32, lineJoin: int32, lineCap: int32, lineWidth: float32): void {
	prepareStroke(r, miterLimit, lineJoin);
	expandStroke(r, r.npoints, false, lineJoin, lineCap, lineWidth);
}

function flattenShapeStroke(r: Rasterizer, shape: Shape, scale: float32): void {
	const miterLimit = shape.miterLimit;
	const lineJoin = shape.strokeLineJoin;
	const lineCap = shape.strokeLineCap;
	const lineWidth: float32 = shape.strokeWidth * scale;

	for (let k: int32 = 0; k < (shape.paths.length as int32); k++) {
		const path = shape.paths[k];
		flattenPath(r, path.pts, path.npts, scale, PT_CORNER);
		if (r.npoints < 2) { continue; }

		let closed = path.closed;
		let last = r.npoints - 1;
		if (ptEquals(r.px[last], r.py[last], r.px[0], r.py[0], r.distTol)) {
			r.npoints -= 1;
			last = r.npoints - 1;
			closed = true;
		}

		if (shape.strokeDashCount > 0) {
			let idash: int32 = 0;
			let dashState = true;
			let totalDist: float32 = 0.0;
			if (closed) { appendPathPoint(r, r.px[0], r.py[0], r.pflags[0]); }
			duplicatePoints(r);
			r.npoints = 0;
			let curX: float32 = r.qx[0];
			let curY: float32 = r.qy[0];
			appendPathPoint(r, curX, curY, r.qflags[0]);

			let allDashLen: float32 = 0.0;
			for (let j: int32 = 0; j < shape.strokeDashCount; j++) {
				allDashLen = allDashLen + shape.strokeDashArray[j];
			}
			if ((shape.strokeDashCount & 1) != 0) { allDashLen = allDashLen * 2.0; }
			let dashOffset: float32 = fmodf(shape.strokeDashOffset, allDashLen);
			if (dashOffset < 0.0) { dashOffset = dashOffset + allDashLen; }
			while (dashOffset > shape.strokeDashArray[idash]) {
				dashOffset = dashOffset - shape.strokeDashArray[idash];
				idash = (idash + 1) % shape.strokeDashCount;
			}
			let dashLen: float32 = (shape.strokeDashArray[idash] - dashOffset) * scale;

			let j: int32 = 1;
			while (j < r.nq) {
				const dx: float32 = r.qx[j] - curX;
				const dy: float32 = r.qy[j] - curY;
				const dsq: float32 = dx * dx + dy * dy;
				const dist: float32 = sqrtf(dsq);
				const reach: float32 = totalDist + dist;
				if (reach > dashLen) {
					const d: float32 = (dashLen - totalDist) / dist;
					const x: float32 = curX + dx * d;
					const y: float32 = curY + dy * d;
					addPathPoint(r, x, y, PT_CORNER);
					if (r.npoints > 1 && dashState) {
						strokeSegment(r, miterLimit, lineJoin, lineCap, lineWidth);
					}
					dashState = !dashState;
					idash = (idash + 1) % shape.strokeDashCount;
					dashLen = shape.strokeDashArray[idash] * scale;
					curX = x;
					curY = y;
					totalDist = 0.0;
					r.npoints = 0;
					appendPathPoint(r, curX, curY, PT_CORNER);
				} else {
					totalDist = totalDist + dist;
					curX = r.qx[j];
					curY = r.qy[j];
					appendPathPoint(r, curX, curY, r.qflags[j]);
					j += 1;
				}
			}
			if (r.npoints > 1 && dashState) {
				strokeSegment(r, miterLimit, lineJoin, lineCap, lineWidth);
			}
		} else {
			prepareStroke(r, miterLimit, lineJoin);
			expandStroke(r, r.npoints, closed, lineJoin, lineCap, lineWidth);
		}
	}
}

function cmpEdge(r: Rasterizer, order: int32[], a: int32, b: int32): int32 {
	const ya = r.ey0[order[a]];
	const yb = r.ey0[order[b]];
	if (ya < yb) { return -1; }
	if (ya > yb) { return 1; }
	return 0;
}

function swapAt(order: int32[], a: int32, b: int32): void {
	const t = order[a];
	order[a] = order[b];
	order[b] = t;
}

// The qsort of the Windows C runtime that svgMask.c links, step by step: ties among edges that
// start on one y0 keep the order this quicksort leaves them in, and a stable sort would not.
function qsortEdges(r: Rasterizer, order: int32[], n: int32): void {
	if (n < 2) { return; }
	const lostk: int32[] = [];
	const histk: int32[] = [];
	let lo: int32 = 0;
	let hi: int32 = n - 1;
	while (true) {
		const size = hi - lo + 1;
		let descend = false;
		if (size <= 8) {
			let top = hi;
			while (top > lo) {
				let max = lo;
				for (let p = lo + 1; p <= top; p++) {
					if (cmpEdge(r, order, p, max) > 0) { max = p; }
				}
				swapAt(order, max, top);
				top -= 1;
			}
		} else {
			let mid = lo + (size >> 1);
			if (cmpEdge(r, order, lo, mid) > 0) { swapAt(order, lo, mid); }
			if (cmpEdge(r, order, lo, hi) > 0) { swapAt(order, lo, hi); }
			if (cmpEdge(r, order, mid, hi) > 0) { swapAt(order, mid, hi); }
			let loguy = lo;
			let higuy = hi;
			while (true) {
				if (mid > loguy) {
					loguy += 1;
					while (loguy < mid && cmpEdge(r, order, loguy, mid) <= 0) { loguy += 1; }
				}
				if (mid <= loguy) {
					loguy += 1;
					while (loguy <= hi && cmpEdge(r, order, loguy, mid) <= 0) { loguy += 1; }
				}
				higuy -= 1;
				while (higuy > mid && cmpEdge(r, order, higuy, mid) > 0) { higuy -= 1; }
				if (higuy < loguy) { break; }
				swapAt(order, loguy, higuy);
				if (mid == higuy) { mid = loguy; }
			}
			higuy += 1;
			if (mid < higuy) {
				higuy -= 1;
				while (higuy > mid && cmpEdge(r, order, higuy, mid) == 0) { higuy -= 1; }
			}
			if (mid >= higuy) {
				higuy -= 1;
				while (higuy > lo && cmpEdge(r, order, higuy, mid) == 0) { higuy -= 1; }
			}
			if (higuy - lo >= hi - loguy) {
				if (lo < higuy) {
					lostk.push(lo);
					histk.push(higuy);
				}
				if (loguy < hi) {
					lo = loguy;
					descend = true;
				}
			} else {
				if (loguy < hi) {
					lostk.push(loguy);
					histk.push(hi);
				}
				if (lo < higuy) {
					hi = higuy;
					descend = true;
				}
			}
		}
		if (descend) { continue; }
		if (lostk.length == 0) { return; }
		lo = lostk.pop();
		hi = histk.pop();
	}
}

function sortEdges(r: Rasterizer): void {
	const n = r.nedges;
	const order: int32[] = [];
	for (let i: int32 = 0; i < n; i++) { order.push(i); }
	qsortEdges(r, order, n);
	const x0: float32[] = [];
	const y0: float32[] = [];
	const x1: float32[] = [];
	const y1: float32[] = [];
	const dir: int32[] = [];
	for (let i: int32 = 0; i < n; i++) {
		const e = order[i];
		x0.push(r.ex0[e]);
		y0.push(r.ey0[e]);
		x1.push(r.ex1[e]);
		y1.push(r.ey1[e]);
		dir.push(r.edir[e]);
	}
	r.ex0 = x0;
	r.ey0 = y0;
	r.ex1 = x1;
	r.ey1 = y1;
	r.edir = dir;
}

function addActive(r: Rasterizer, e: int32, startPoint: float32): int32 {
	let z: int32 = 0;
	if (r.freelist >= 0) {
		z = r.freelist;
		r.freelist = r.anext[z];
	} else {
		z = r.na;
		r.na += 1;
		if (z >= (r.ax.length as int32)) {
			r.ax.push(0);
			r.adx.push(0);
			r.aey.push(0.0);
			r.adir.push(0);
			r.anext.push(-1);
		}
	}
	const dxdy: float32 = (r.ex1[e] - r.ex0[e]) / (r.ey1[e] - r.ey0[e]);
	if (dxdy < 0) {
		const scaled: float32 = (FIX as float32) * -dxdy;
		r.adx[z] = floatToInt(-roundf(scaled));
	} else {
		const scaled: float32 = (FIX as float32) * dxdy;
		r.adx[z] = floatToInt(roundf(scaled));
	}
	const run: float32 = dxdy * (startPoint - r.ey0[e]);
	const at: float32 = r.ex0[e] + run;
	const fixed: float32 = (FIX as float32) * at;
	r.ax[z] = floatToInt(roundf(fixed));
	r.aey[z] = r.ey1[e];
	r.anext[z] = -1;
	r.adir[z] = r.edir[e];
	return z;
}

function fillScanline(r: Rasterizer, x0: int32, x1: int32): void {
	const len = r.width;
	let i = x0 >> FIXSHIFT;
	let j = x1 >> FIXSHIFT;
	if (i < r.xmin) { r.xmin = i; }
	if (j > r.xmax) { r.xmax = j; }
	if (i < len && j >= 0) {
		if (i == j) {
			r.scanline[i] = ((r.scanline[i] + (((x1 - x0) * MAX_WEIGHT) >> FIXSHIFT)) & 255) as uint8;
		} else {
			if (i >= 0) {
				r.scanline[i] =
					((r.scanline[i] + (((FIX - (x0 & FIXMASK)) * MAX_WEIGHT) >> FIXSHIFT)) & 255) as uint8;
			} else {
				i = -1;
			}
			if (j < len) {
				r.scanline[j] = ((r.scanline[j] + (((x1 & FIXMASK) * MAX_WEIGHT) >> FIXSHIFT)) & 255) as uint8;
			} else {
				j = len;
			}
			i += 1;
			while (i < j) {
				r.scanline[i] = ((r.scanline[i] + MAX_WEIGHT) & 255) as uint8;
				i += 1;
			}
		}
	}
}

function fillActiveEdges(r: Rasterizer, head: int32, fillRule: int32): void {
	let x0: int32 = 0;
	let w: int32 = 0;
	let e = head;
	if (fillRule == FILLRULE_NONZERO) {
		while (e >= 0) {
			if (w == 0) {
				x0 = r.ax[e];
				w += r.adir[e];
			} else {
				const x1 = r.ax[e];
				w += r.adir[e];
				if (w == 0) { fillScanline(r, x0, x1); }
			}
			e = r.anext[e];
		}
	} else if (fillRule == FILLRULE_EVENODD) {
		while (e >= 0) {
			if (w == 0) {
				x0 = r.ax[e];
				w = 1;
			} else {
				const x1 = r.ax[e];
				w = 0;
				fillScanline(r, x0, x1);
			}
			e = r.anext[e];
		}
	}
}

function div255(x: int32): int32 {
	return ((x + 1) * 257) >> 16;
}

function applyOpacity(alpha: int32, u: float32): int32 {
	const scaled: float32 = clampf(u, 0.0, 1.0) * 256.0;
	const iu = floatToInt(scaled);
	return ((alpha & 255) * iu) >> 8;
}

function lerpAlpha(a0: int32, a1: int32, u: float32): int32 {
	const scaled: float32 = clampf(u, 0.0, 1.0) * 256.0;
	const iu = floatToInt(scaled);
	return ((a0 * (256 - iu)) + (a1 * iu)) >> 8;
}

function initPaint(cache: Cache, paint: Paint, opacity: float32): void {
	cache.kind = paint.kind;
	if (paint.kind == PAINT_COLOR) {
		cache.alpha = applyOpacity(paint.alpha, opacity);
		return;
	}
	const grad = paint.gradient;
	if (grad == null) { throw new Error("void2d svg: a gradient paint has no gradient"); }
	for (let i: int32 = 0; i < 6; i++) { cache.xform[i] = grad.xform[i]; }
	while ((cache.colors.length as int32) < 256) { cache.colors.push(0); }
	const nstops = grad.stops.length as int32;
	if (nstops == 0) {
		for (let i: int32 = 0; i < 256; i++) { cache.colors[i] = 0; }
	} else if (nstops == 1) {
		const alpha = applyOpacity(grad.stops[0].alpha, opacity);
		for (let i: int32 = 0; i < 256; i++) { cache.colors[i] = alpha; }
	} else {
		let ca = applyOpacity(grad.stops[0].alpha, opacity);
		let cb: int32 = 0;
		let ua = clampf(grad.stops[0].offset, 0.0, 1.0);
		let ub = clampf(grad.stops[nstops - 1].offset, ua, 1.0);
		let scaled: float32 = ua * 255.0;
		let ia = floatToInt(scaled);
		scaled = ub * 255.0;
		let ib = floatToInt(scaled);
		for (let i: int32 = 0; i < ia; i++) { cache.colors[i] = ca; }
		for (let i: int32 = 0; i < nstops - 1; i++) {
			ca = applyOpacity(grad.stops[i].alpha, opacity);
			cb = applyOpacity(grad.stops[i + 1].alpha, opacity);
			ua = clampf(grad.stops[i].offset, 0.0, 1.0);
			ub = clampf(grad.stops[i + 1].offset, 0.0, 1.0);
			scaled = ua * 255.0;
			ia = floatToInt(scaled);
			scaled = ub * 255.0;
			ib = floatToInt(scaled);
			const count = ib - ia;
			if (count <= 0) { continue; }
			let u: float32 = 0.0;
			const du: float32 = 1.0 / (count as float32);
			for (let j: int32 = 0; j < count; j++) {
				cache.colors[ia + j] = lerpAlpha(ca, cb, u);
				u = u + du;
			}
		}
		for (let i = ib; i < 256; i++) { cache.colors[i] = cb; }
	}
}

function blendAlpha(dst: Span<uint8>, at: int32, cover: int32, ca: int32): void {
	let a = div255(cover * ca);
	const ia = 255 - a;
	a += div255(ia * (dst[at] as int32));
	dst[at] = (a & 255) as uint8;
}

function scanlineSolid(
	r: Rasterizer,
	dst: Span<uint8>,
	row: int32,
	count: int32,
	x: int32,
	y: int32,
	tx: float32,
	ty: float32,
	scale: float32,
	cache: Cache,
): void {
	if (cache.kind == PAINT_COLOR) {
		for (let i: int32 = 0; i < count; i++) {
			blendAlpha(dst, row + x + i, r.scanline[x + i] as int32, cache.alpha);
		}
	} else if (cache.kind == PAINT_LINEAR_GRADIENT) {
		const t = cache.xform;
		let fx: float32 = ((x as float32) - tx) / scale;
		const fy: float32 = ((y as float32) - ty) / scale;
		const dx: float32 = 1.0 / scale;
		for (let i: int32 = 0; i < count; i++) {
			const gy: float32 = fx * t[1] + fy * t[3] + t[5];
			const scaled: float32 = gy * 255.0;
			const ca = cache.colors[floatToInt(clampf(scaled, 0.0, 255.0))];
			blendAlpha(dst, row + x + i, r.scanline[x + i] as int32, ca);
			fx = fx + dx;
		}
	} else if (cache.kind == PAINT_RADIAL_GRADIENT) {
		const t = cache.xform;
		let fx: float32 = ((x as float32) - tx) / scale;
		const fy: float32 = ((y as float32) - ty) / scale;
		const dx: float32 = 1.0 / scale;
		for (let i: int32 = 0; i < count; i++) {
			const gx: float32 = fx * t[0] + fy * t[2] + t[4];
			const gy: float32 = fx * t[1] + fy * t[3] + t[5];
			const gsq: float32 = gx * gx + gy * gy;
			const gd: float32 = sqrtf(gsq);
			const scaled: float32 = gd * 255.0;
			const ca = cache.colors[floatToInt(clampf(scaled, 0.0, 255.0))];
			blendAlpha(dst, row + x + i, r.scanline[x + i] as int32, ca);
			fx = fx + dx;
		}
	}
}

function rasterizeSortedEdges(
	r: Rasterizer,
	dst: Span<uint8>,
	tx: float32,
	ty: float32,
	scale: float32,
	cache: Cache,
	fillRule: int32,
): void {
	let active: int32 = -1;
	let e: int32 = 0;
	for (let y: int32 = 0; y < r.height; y++) {
		for (let i: int32 = 0; i < r.width; i++) { r.scanline[i] = 0; }
		r.xmin = r.width;
		r.xmax = 0;
		for (let s: int32 = 0; s < SUBSAMPLES; s++) {
			const scany: float32 = ((y * SUBSAMPLES + s) as float32) + 0.5;

			let prev: int32 = -1;
			let z = active;
			while (z >= 0) {
				const next = r.anext[z];
				if (r.aey[z] <= scany) {
					if (prev < 0) {
						active = next;
					} else {
						r.anext[prev] = next;
					}
					r.anext[z] = r.freelist;
					r.freelist = z;
				} else {
					r.ax[z] = r.ax[z] + r.adx[z];
					prev = z;
				}
				z = next;
			}

			let changed = true;
			while (changed) {
				changed = false;
				let before: int32 = -1;
				let t = active;
				while (t >= 0 && r.anext[t] >= 0) {
					const q = r.anext[t];
					if (r.ax[t] > r.ax[q]) {
						r.anext[t] = r.anext[q];
						r.anext[q] = t;
						if (before < 0) {
							active = q;
						} else {
							r.anext[before] = q;
						}
						before = q;
						changed = true;
					} else {
						before = t;
						t = r.anext[t];
					}
				}
			}

			while (e < r.nedges && r.ey0[e] <= scany) {
				if (r.ey1[e] > scany) {
					const n = addActive(r, e, scany);
					if (active < 0) {
						active = n;
					} else if (r.ax[n] < r.ax[active]) {
						r.anext[n] = active;
						active = n;
					} else {
						let p = active;
						while (r.anext[p] >= 0 && r.ax[r.anext[p]] < r.ax[n]) { p = r.anext[p]; }
						r.anext[n] = r.anext[p];
						r.anext[p] = n;
					}
				}
				e += 1;
			}

			if (active >= 0) { fillActiveEdges(r, active, fillRule); }
		}

		if (r.xmin < 0) { r.xmin = 0; }
		if (r.xmax > r.width - 1) { r.xmax = r.width - 1; }
		if (r.xmin <= r.xmax) {
			scanlineSolid(r, dst, y * r.width, r.xmax - r.xmin + 1, r.xmin, y, tx, ty, scale, cache);
		}
	}
}

function placeEdges(r: Rasterizer, tx: float32, ty: float32): void {
	for (let i: int32 = 0; i < r.nedges; i++) {
		r.ex0[i] = tx + r.ex0[i];
		const y0: float32 = (ty + r.ey0[i]) * (SUBSAMPLES as float32);
		r.ey0[i] = y0;
		r.ex1[i] = tx + r.ex1[i];
		const y1: float32 = (ty + r.ey1[i]) * (SUBSAMPLES as float32);
		r.ey1[i] = y1;
	}
}

function startPass(r: Rasterizer): void {
	r.freelist = -1;
	r.na = 0;
	r.nedges = 0;
}

// nsvgRasterize with tessellation tolerance 0.05, as the alpha channel of a w x h image.
export function rasterize(
	image: SvgImage,
	tx: float32,
	ty: float32,
	scale: float32,
	w: int32,
	h: int32,
): Vec<uint8> {
	const r = new Rasterizer();
	r.width = w;
	r.height = h;
	let dst: Vec<uint8> = new Array(w * h);
	for (let i: int32 = 0; i < w * h; i++) { dst[i] = 0; }
	for (let i: int32 = 0; i < w; i++) { r.scanline.push(0); }
	const cache = new Cache();

	for (let k: int32 = 0; k < (image.shapes.length as int32); k++) {
		const shape = image.shapes[k];
		if (!shape.visible) { continue; }
		for (let j: int32 = 0; j < 3; j++) {
			const order = (shape.paintOrder >> (2 * j)) & 3;
			if (order == PAINT_ORDER_FILL && shape.fill.kind != PAINT_NONE) {
				startPass(r);
				flattenShape(r, shape, scale);
				placeEdges(r, tx, ty);
				if (r.nedges != 0) { sortEdges(r); }
				initPaint(cache, shape.fill, shape.opacity);
				rasterizeSortedEdges(r, dst, tx, ty, scale, cache, shape.fillRule);
			}
			const width: float32 = shape.strokeWidth * scale;
			if (order == PAINT_ORDER_STROKE && shape.stroke.kind != PAINT_NONE && width > MIN_STROKE_WIDTH) {
				startPass(r);
				flattenShapeStroke(r, shape, scale);
				placeEdges(r, tx, ty);
				if (r.nedges != 0) { sortEdges(r); }
				initPaint(cache, shape.stroke, shape.opacity);
				rasterizeSortedEdges(r, dst, tx, ty, scale, cache, FILLRULE_NONZERO);
			}
		}
	}
	return dst;
}
