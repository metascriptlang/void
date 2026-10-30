export function snapEdge(v: float32): float32 {
	return Math.ceil((v - 0.5) as float64) as float32;
}

export function snapOffset(v: float32): float32 {
	if (v >= 0.0) {
		return Math.ceil((v - 0.5) as float64) as float32;
	}
	return -Math.ceil(((-v) - 0.5) as float64) as float32;
}

export function snapStroke(widthDevice: float32): float32 {
	if (widthDevice <= 0.0) { return 0.0; }
	const r: float32 = Math.floor((widthDevice + 0.5) as float64) as float32;
	return r < 1.0 ? 1.0 : r;
}

export function dilateStroke(widthLocal: float32, pixelsPerLocal: float32): float32 {
	if (widthLocal <= 0.0 || pixelsPerLocal <= 0.0) { return 0.0; }
	const minimum: float32 = 1.0 / pixelsPerLocal;
	return widthLocal < minimum ? minimum : widthLocal;
}

export function axisAligned(a: float32, b: float32, c: float32, d: float32): boolean {
	return b == 0.0 && c == 0.0 && a > 0.0 && d > 0.0;
}

export function snapBoxEdges(
	lx0: float32, ly0: float32, sx: float32, sy: float32,
	a: float32, tx: float32, d: float32, ty: float32,
): [float32, float32, float32, float32] {
	const x0d: float32 = snapEdge(a * lx0 + tx);
	const y0d: float32 = snapEdge(d * ly0 + ty);
	const x1d: float32 = snapEdge(a * (lx0 + sx) + tx);
	const y1d: float32 = snapEdge(d * (ly0 + sy) + ty);
	return [
		(x0d - tx) / a, (y0d - ty) / d,
		(x1d - tx) / a - ((x0d - tx) / a), (y1d - ty) / d - ((y0d - ty) / d),
	];
}
