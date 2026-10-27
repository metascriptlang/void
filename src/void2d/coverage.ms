// The device-pixel arithmetic of the 2D replay: a command's scissor rect, the area a polygon
// covers inside it, and the vertex buffer's growth target. Ported from batcher.c with its
// widths: the scissor in float32, the coverage in float64.

import {
	CMD_CLIP_X, CMD_CLIP_Y, CMD_CLIP_W, CMD_CLIP_H, CMD_RT_MODE, CMD_SCOPE, SCOPE_FLOATS,
} from "./displayList";

export const INITIAL_BUFFER_BYTES: int32 = 1 << 20;
export const MAX_BUFFER_BYTES: int32 = 192 << 20;
const COVER_MAX_VERTS: int32 = 12;
const INT32_LOW: int32 = -2147483648;

export struct ScissorRect {
	x0: int32;
	y0: int32;
	x1: int32;
	y1: int32;
}

// The C cast of a float to int on x86-64 (cvttss2si): truncation, and INT32_MIN for NaN and for
// every value outside the int range. Written out so every target gives the answer the C gave.
export function truncated(value: float64): int32 {
	if (!(value > -2147483649.0 && value < 2147483648.0)) { return INT32_LOW; }
	return value as int32;
}

export function scissorMin(edge: float32, scale: float32): int32 {
	const device: float32 = edge * scale;
	return truncated(Math.floor(device as float64));
}

export function scissorMax(edge: float32, scale: float32): int32 {
	const device: float32 = edge * scale;
	return truncated(Math.ceil(device as float64));
}

// max(2x, next power of two), no shrink, 0 past the cap.
export function growthTarget(have: int32, need: int32): int32 {
	if (need > MAX_BUFFER_BYTES) { return 0; }
	if (need <= have) { return have; }
	let want: int32 = have > 0 ? have * 2 : INITIAL_BUFFER_BYTES;
	while (want < need) { want *= 2; }
	if (want > MAX_BUFFER_BYTES) { want = MAX_BUFFER_BYTES; }
	return want;
}

// A command's device scale: its render target's, else the frame's.
export function deviceScaleOf(cmd: Readonly<Span<float32>>, dpiScale: float32): float32 {
	return cmd[CMD_RT_MODE] != 0.0 ? cmd[CMD_RT_MODE] : dpiScale;
}

// Where the command's scope row starts in `scopes`, or -1 when it has none.
export function scopeAt(cmd: Readonly<Span<float32>>, scopeCount: int32, hasScopes: boolean): int32 {
	const scope: int32 = truncated(cmd[CMD_SCOPE] as float64);
	if (scope < 0 || scope >= scopeCount || !hasScopes) { return -1; }
	return scope * SCOPE_FLOATS;
}

// Floor the near edge and ceil the far edge in device pixels, so no pixel the exact clip planes
// accept is discarded.
export function scissorRectOf(
	cmd: Readonly<Span<float32>>,
	scopes: Readonly<Span<float32>>,
	scope: int32,
	dpiScale: float32,
	fbW: float32,
	fbH: float32,
): ScissorRect {
	const scale: float32 = deviceScaleOf(cmd, dpiScale);
	const limitW: int32 = scissorMax(fbW, scale);
	const limitH: int32 = scissorMax(fbH, scale);
	let x: float32 = cmd[CMD_CLIP_X];
	let y: float32 = cmd[CMD_CLIP_Y];
	let w: float32 = cmd[CMD_CLIP_W];
	let h: float32 = cmd[CMD_CLIP_H];
	if (scope >= 0) {
		const shiftX: float32 = scopes[scope];
		const shiftY: float32 = scopes[scope + 1];
		const originX: float32 = scopes[scope + 2];
		const originY: float32 = scopes[scope + 3];
		const sizeW: float32 = scopes[scope + 4];
		const sizeH: float32 = scopes[scope + 5];
		if (w > 0.0 && h > 0.0) {
			const left: float32 = x + shiftX > originX ? x + shiftX : originX;
			const top: float32 = y + shiftY > originY ? y + shiftY : originY;
			const right: float32 = x + shiftX + w < originX + sizeW ? x + shiftX + w : originX + sizeW;
			const bottom: float32 = y + shiftY + h < originY + sizeH ? y + shiftY + h : originY + sizeH;
			x = left;
			y = top;
			w = right - left;
			h = bottom - top;
		} else {
			x = originX;
			y = originY;
			w = sizeW;
			h = sizeH;
		}
		if (w <= 0.0 || h <= 0.0) { return { x0: 0, y0: 0, x1: 0, y1: 0 }; }
	}
	if (w <= 0.0 || h <= 0.0) { return { x0: 0, y0: 0, x1: limitW, y1: limitH }; }
	let x0: int32 = scissorMin(x, scale);
	let y0: int32 = scissorMin(y, scale);
	let x1: int32 = scissorMax(x + w, scale);
	let y1: int32 = scissorMax(y + h, scale);
	if (x0 < 0) { x0 = 0; }
	if (y0 < 0) { y0 = 0; }
	if (x0 > limitW) { x0 = limitW; }
	if (y0 > limitH) { y0 = limitH; }
	if (x1 < 0) { x1 = 0; }
	if (y1 < 0) { y1 = 0; }
	if (x1 > limitW) { x1 = limitW; }
	if (y1 > limitH) { y1 = limitH; }
	if (x1 < x0) { x1 = x0; }
	if (y1 < y0) { y1 = y0; }
	return { x0, y0, x1, y1 };
}

// Points are x, y pairs. Keeps the part of the polygon on the `sign` side of the axis line.
function clipToHalfPlane(
	input: Readonly<Span<float64>>,
	n: int32,
	output: Span<float64>,
	axis: int32,
	limit: float64,
	sign: float64,
): int32 {
	let m: int32 = 0;
	for (let i: int32 = 0; i < n; i++) {
		const next: int32 = (i + 1) % n;
		const ax: float64 = input[i * 2];
		const ay: float64 = input[i * 2 + 1];
		const bx: float64 = input[next * 2];
		const by: float64 = input[next * 2 + 1];
		const da: float64 = ((axis != 0 ? ay : ax) - limit) * sign;
		const db: float64 = ((axis != 0 ? by : bx) - limit) * sign;
		if (da >= 0.0) {
			output[m * 2] = ax;
			output[m * 2 + 1] = ay;
			m++;
		}
		if ((da >= 0.0) != (db >= 0.0)) {
			const t: float64 = da / (da - db);
			output[m * 2] = ax + (bx - ax) * t;
			output[m * 2 + 1] = ay + (by - ay) * t;
			m++;
		}
	}
	return m;
}

// Device pixels a convex polygon (x, y pairs in device coordinates, at most 12 points) covers
// inside the scissor rect.
export function clippedArea(poly: Readonly<Span<float64>>, count: int32, rect: ScissorRect): float64 {
	if (count > COVER_MAX_VERTS) { unreachable; }
	let pointsA: float64[24] = [
		0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
	];
	let pointsB: float64[24] = [
		0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
	];
	const a: Span<float64> = pointsA[0..24];
	const b: Span<float64> = pointsB[0..24];
	for (let i: int32 = 0; i < count * 2; i++) { a[i] = poly[i]; }
	let n: int32 = clipToHalfPlane(a, count, b, 0, rect.x0 as float64, 1.0);
	if (n != 0) { n = clipToHalfPlane(b, n, a, 0, rect.x1 as float64, -1.0); }
	if (n != 0) { n = clipToHalfPlane(a, n, b, 1, rect.y0 as float64, 1.0); }
	if (n != 0) { n = clipToHalfPlane(b, n, a, 1, rect.y1 as float64, -1.0); }
	let twice: float64 = 0.0;
	for (let i: int32 = 0; i < n; i++) {
		const next: int32 = (i + 1) % n;
		twice += a[i * 2] * a[next * 2 + 1] - a[next * 2] * a[i * 2 + 1];
	}
	return (twice < 0.0 ? -twice : twice) * 0.5;
}

// The device pixels one affine quad (a b c d at `at` in `affine`) covers inside a rect.
export function quadClippedArea(
	affine: Readonly<Span<float32>>,
	at: int32,
	ox: float64,
	oy: float64,
	lx0: float64,
	ly0: float64,
	lx1: float64,
	ly1: float64,
	scale: float64,
	rect: ScissorRect,
): float64 {
	const a0: float64 = affine[at] as float64;
	const a1: float64 = affine[at + 1] as float64;
	const a2: float64 = affine[at + 2] as float64;
	const a3: float64 = affine[at + 3] as float64;
	let quad: float64[8] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
	for (let i: int32 = 0; i < 4; i++) {
		const cx: float64 = (i == 1 || i == 2) ? lx1 : lx0;
		const cy: float64 = i >= 2 ? ly1 : ly0;
		quad[i * 2] = (a0 * cx + a2 * cy + ox) * scale;
		quad[i * 2 + 1] = (a1 * cx + a3 * cy + oy) * scale;
	}
	return clippedArea(quad[0..8], 4, rect);
}

// The device pixels one unit-quad instance (affine a b c d, origin, size) covers inside a rect:
// the arithmetic the profiler's overdraw counter sums.
export function quadCoverage(
	affine: Readonly<Span<float32>>,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	scale: float32,
	x0: int32,
	y0: int32,
	x1: int32,
	y1: int32,
): float64 {
	return quadClippedArea(
		affine, 0, x as float64, y as float64, 0.0, 0.0, w as float64, h as float64,
		scale as float64, { x0, y0, x1, y1 },
	);
}
