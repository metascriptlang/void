import {
	GlyphBox,
	Vertex,
	VERTEX_CUBIC,
	VERTEX_CURVE,
	VERTEX_MOVE,
	truncInt,
	wrapInt16,
} from "../trueType/fontInfo";

export function shortOf(value: float32): int16 {
	return wrapInt16(truncInt(value as float64));
}

function floorF(value: float32): float32 {
	return Math.floor(value as float64) as float32;
}

function sqrtF(value: float32): float32 {
	return Math.sqrt(value as float64) as float32;
}

struct OutlinePoints {
	x: float32[];
	y: float32[];
	slot: int32[];
}

function pushPoint(ref points: OutlinePoints, vertices: Readonly<Span<Vertex>>, v: int32, k: int32): void {
	const vertex = vertices[v];
	if (k == 0) {
		points.x.push(vertex.x as float32);
		points.y.push(vertex.y as float32);
	} else if (k == 1) {
		points.x.push(vertex.cx as float32);
		points.y.push(vertex.cy as float32);
	} else {
		points.x.push(vertex.cx1 as float32);
		points.y.push(vertex.cy1 as float32);
	}
	points.slot.push(v * 3 + k);
}

function outlinePoints(vertices: Readonly<Span<Vertex>>, ref points: OutlinePoints, ref ends: int32[]): int32 {
	let n: int32 = 0;
	let contours: int32 = 0;
	for (let i: int32 = 0; i < (vertices.length as int32); i++) {
		const kind = vertices[i].kind;
		if (kind == VERTEX_MOVE) {
			if (n > 0) {
				ends[contours] = n - 1;
				contours++;
			}
		} else if (kind == VERTEX_CURVE) {
			pushPoint(points, vertices, i, 1);
			n++;
		} else if (kind == VERTEX_CUBIC) {
			pushPoint(points, vertices, i, 1);
			pushPoint(points, vertices, i, 2);
			n += 2;
		}
		pushPoint(points, vertices, i, 0);
		n++;
	}
	if (n > 0) {
		ends[contours] = n - 1;
		contours++;
	}
	return contours;
}

function normLen(ref x: float32, ref y: float32): float32 {
	const len: float32 = sqrtF(x * x + y * y);
	if (len > 0.0) {
		x = x / len;
		y = y / len;
	}
	return len;
}

function emboldenContour(
	ref px: float32[], ref py: float32[], first: int32, last: int32, strength: float32, trueType: boolean,
): void {
	const xs: float32 = strength * 0.5;
	const ys: float32 = strength * 0.5;
	let inX: float32 = 0.0;
	let inY: float32 = 0.0;
	let anchorX: float32 = 0.0;
	let anchorY: float32 = 0.0;
	let lIn: float32 = 0.0;
	let lAnchor: float32 = 0.0;
	let i: int32 = last;
	let j: int32 = first;
	let k: int32 = -1;
	for (let outer: int32 = 0; j != i && i != k; j = j < last ? j + 1 : first) {
		let outX: float32 = 0.0;
		let outY: float32 = 0.0;
		let lOut: float32 = 0.0;
		if (j != k) {
			outX = px[j] - px[i];
			outY = py[j] - py[i];
			lOut = normLen(outX, outY);
			if (lOut == 0.0) { continue; }
		} else {
			outX = anchorX;
			outY = anchorY;
			lOut = lAnchor;
		}
		if (lIn != 0.0) {
			if (k < 0) {
				k = i;
				anchorX = inX;
				anchorY = inY;
				lAnchor = lIn;
			}
			let d: float32 = inX * outX + inY * outY;
			let shiftX: float32 = 0.0;
			let shiftY: float32 = 0.0;
			if (d > -0.9375) {
				d = d + 1.0;
				shiftX = inY + outY;
				shiftY = inX + outX;
				if (trueType) { shiftX = -shiftX; } else { shiftY = -shiftY; }
				let q: float32 = outX * inY - outY * inX;
				if (trueType) { q = -q; }
				const l: float32 = lIn < lOut ? lIn : lOut;
				shiftX = xs * q <= l * d ? shiftX * xs / d : shiftX * l / q;
				shiftY = ys * q <= l * d ? shiftY * ys / d : shiftY * l / q;
			}
			for (let inner: int32 = 0; i != j; i = i < last ? i + 1 : first) {
				px[i] = px[i] + (xs + shiftX);
				py[i] = py[i] + (ys + shiftY);
			}
		} else {
			i = j;
		}
		inX = outX;
		inY = outY;
		lIn = lOut;
	}
}

function embolden(ref vertices: Vec<Vertex>, strength: float32): void {
	let points: OutlinePoints = { x: [], y: [], slot: [] };
	let ends: int32[] = new Array<int32>(vertices.length as int32);
	const contours = outlinePoints(vertices, points, ends);
	let area: float32 = 0.0;
	let first: int32 = 0;
	for (let c: int32 = 0; c < contours; c++) {
		let prev: int32 = ends[c];
		for (let i: int32 = first; i <= ends[c]; i++) {
			area = area + (points.y[i] - points.y[prev]) * (points.x[i] + points.x[prev]);
			prev = i;
		}
		first = ends[c] + 1;
	}
	if (area != 0.0) {
		first = 0;
		for (let c: int32 = 0; c < contours; c++) {
			const last = ends[c];
			const closed = last > first && points.x[last] == points.x[first] && points.y[last] == points.y[first];
			emboldenContour(points.x, points.y, first, closed ? last - 1 : last, strength, area < 0.0);
			if (closed) {
				points.x[last] = points.x[first];
				points.y[last] = points.y[first];
			}
			first = ends[c] + 1;
		}
	}
	const total = contours > 0 ? ends[contours - 1] + 1 : 0;
	for (let i: int32 = 0; i < total; i++) {
		const slot = points.slot[i];
		const v = slot / 3;
		const k = slot % 3;
		const x = shortOf(floorF(points.x[i] + 0.5));
		const y = shortOf(floorF(points.y[i] + 0.5));
		if (k == 0) {
			vertices[v].x = x;
			vertices[v].y = y;
		} else if (k == 1) {
			vertices[v].cx = x;
			vertices[v].cy = y;
		} else {
			vertices[v].cx1 = x;
			vertices[v].cy1 = y;
		}
	}
}

export function applySynthetic(ref vertices: Vec<Vertex>, emboldenUnits: float32, skew: float32): void {
	const count = vertices.length as int32;
	if (count <= 0) { return; }
	if (emboldenUnits > 0.0) { embolden(vertices, emboldenUnits); }
	if (skew != 0.0) {
		for (let i: int32 = 0; i < count; i++) {
			const v = vertices[i];
			vertices[i].x = shortOf(floorF((v.x as float32) + (v.y as float32) * skew + 0.5));
			if (v.kind == VERTEX_CURVE || v.kind == VERTEX_CUBIC) {
				vertices[i].cx = shortOf(floorF((v.cx as float32) + (v.cy as float32) * skew + 0.5));
			}
			if (v.kind == VERTEX_CUBIC) {
				vertices[i].cx1 = shortOf(floorF((v.cx1 as float32) + (v.cy1 as float32) * skew + 0.5));
			}
		}
	}
}

export function shapeBox(vertices: Readonly<Span<Vertex>>, scale: float32, shiftX: float32): GlyphBox {
	const count = vertices.length as int32;
	if (count <= 0) { return { x0: 0, y0: 0, x1: 0, y1: 0 }; }
	let x0: float32 = vertices[0].x as float32;
	let x1: float32 = x0;
	let y0: float32 = vertices[0].y as float32;
	let y1: float32 = y0;
	for (let i: int32 = 0; i < count; i++) {
		const v = vertices[i];
		const used = v.kind == VERTEX_CUBIC ? 3 : v.kind == VERTEX_CURVE ? 2 : 1;
		for (let k: int32 = 0; k < used; k++) {
			const x: float32 = (k == 0 ? v.x : k == 1 ? v.cx : v.cx1) as float32;
			const y: float32 = (k == 0 ? v.y : k == 1 ? v.cy : v.cy1) as float32;
			if (x < x0) { x0 = x; }
			if (x > x1) { x1 = x; }
			if (y < y0) { y0 = y; }
			if (y > y1) { y1 = y; }
		}
	}
	const left: float32 = x0 * scale + shiftX;
	const top: float32 = -y1 * scale;
	const right: float32 = x1 * scale + shiftX;
	const bottom: float32 = -y0 * scale;
	return {
		x0: truncInt(Math.floor(left as float64)),
		y0: truncInt(Math.floor(top as float64)),
		x1: truncInt(Math.ceil(right as float64)),
		y1: truncInt(Math.ceil(bottom as float64)),
	};
}

export function hasCubic(vertices: Readonly<Span<Vertex>>): boolean {
	for (let i: int32 = 0; i < (vertices.length as int32); i++) {
		if (vertices[i].kind == VERTEX_CUBIC) { return true; }
	}
	return false;
}
