export function approx(a: float32, b: float32): boolean {
	let d: float32 = a - b;
	if (d < 0.0) { d = -d; }
	return d < 0.005;
}

export function approxRel(a: float32, b: float32, tolPct: float32): boolean {
	let d: float32 = a - b;
	if (d < 0.0) { d = -d; }
	let m: float32 = b;
	if (m < 0.0) { m = -m; }
	return d <= m * tolPct * 0.01;
}

export function meshTriArea(mesh: float32[]): float32 {
	let total: float32 = 0.0;
	const len: int32 = mesh.length as int32;
	let i: int32 = 0;
	while (i + 24 <= len) {
		const ax: float32 = mesh[i];
		const ay: float32 = mesh[i + 1];
		const bx: float32 = mesh[i + 8];
		const by: float32 = mesh[i + 9];
		const cx: float32 = mesh[i + 16];
		const cy: float32 = mesh[i + 17];
		let cr: float32 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
		if (cr < 0.0) { cr = -cr; }
		total = total + cr * 0.5;
		i = i + 24;
	}
	return total;
}

export function meshHasVert(mesh: float32[], x: float32, y: float32): boolean {
	const len: int32 = mesh.length as int32;
	let i: int32 = 0;
	while (i + 8 <= len) {
		if (approx(mesh[i], x) && approx(mesh[i + 1], y)) { return true; }
		i = i + 8;
	}
	return false;
}

export function meshHasVertUV(mesh: float32[], x: float32, y: float32, u: float32, v: float32): boolean {
	const len: int32 = mesh.length as int32;
	let i: int32 = 0;
	while (i + 8 <= len) {
		if (approx(mesh[i], x) && approx(mesh[i + 1], y) && approx(mesh[i + 2], u) && approx(mesh[i + 3], v)) { return true; }
		i = i + 8;
	}
	return false;
}
