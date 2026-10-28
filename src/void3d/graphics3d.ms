import { Vec3, vec3 } from "../math/math3d";
import {
	MeshData, Rgba, LIT_TEXTURED_VERTEX_STRIDE, addTexturedVertex, addTriangle,
	hasRoomFor, validIndexStorage, vertexCount, indexCount,
} from "./meshData";
import { addPoint } from "./bounds";
import { Camera3D, CameraView } from "./camera";
import {
	LINE_COLOR, LINE_FAR, LINE_LENGTH_SCALE, LINE_NEAR, LINE_PIXEL_SIZE, LINE_UNIFORM_LENGTH,
	LINE_WIDTH,
} from "./gpu3d";

export struct GraphicsPoint {
	position: Vec3;
	color: Rgba;
}

export struct Graphics3D {
	data: MeshData;
	current: Vec3;
	color: Rgba;
	width: float32;
	lineSize: float32;
	is3D: boolean;
	points: Vec<GraphicsPoint>;
}

export enum GraphicsError { NonFinite, DeltaRange, Shape, Capacity, Degenerate }

export function create(this typeof Graphics3D): Graphics3D {
	return {
		data: MeshData.withUvs(), current: vec3(0, 0, 0), width: 1.5, lineSize: 0,
		color: { red: 0, green: 0, blue: 0, alpha: 1 }, is3D: false, points: [],
	};
}

function finiteColor(color: Rgba): boolean {
	return Number.isFinite(color.red) && Number.isFinite(color.green) &&
		Number.isFinite(color.blue) && Number.isFinite(color.alpha);
}

function finitePoint(point: Vec3): boolean {
	return Number.isFinite(point.x) && Number.isFinite(point.y) && Number.isFinite(point.z);
}

export function setGraphicsColorF(
	ref graphics: Graphics3D, red: float32, green: float32, blue: float32, alpha: float32 = 1,
): Result<void, GraphicsError> {
	const color: Rgba = { red: red, green: green, blue: blue, alpha: alpha };
	if (!finiteColor(color)) { return Result.err(GraphicsError.NonFinite); }
	graphics.color = color;
	return Result.ok(null);
}

export function lineStyle(
	ref graphics: Graphics3D, width: float32 = 0, color: uint32 = 0, alpha: float32 = 1,
): Result<void, GraphicsError> {
	if (!Number.isFinite(width)) { return Result.err(GraphicsError.NonFinite); }
	const flushed = flushGraphics(graphics);
	if (!flushed.ok) { return flushed; }
	const result = setGraphicsColorF(graphics,
		((color >> 16) & 0xff) as float32 / 255.0,
		((color >> 8) & 0xff) as float32 / 255.0,
		(color & 0xff) as float32 / 255.0, alpha);
	if (!result.ok) { return result; }
	if (width > 0 && graphics.lineSize != width) {
		graphics.lineSize = width;
		if (!graphics.is3D) { graphics.width = width; }
	}
	return Result.ok(null);
}

export function moveTo(
	ref graphics: Graphics3D, x: float32, y: float32, z: float32,
): Result<void, GraphicsError> {
	const point: Vec3 = vec3(x, y, z);
	if (!finitePoint(point)) { return Result.err(GraphicsError.NonFinite); }
	if (graphics.is3D) {
		const flushed = flushGraphics(graphics);
		if (!flushed.ok) { return flushed; }
		return lineTo(graphics, x, y, z);
	}
	graphics.current = point;
	return Result.ok(null);
}

// The line program's block (gpu3d.ms LINE_*) for `graphics` drawn through `camera`'s `view`:
// lineStyle's width as LineShader's, Graphics' lengthScale of 1, the view's target as pixelSize
// (RenderContext's 2 / width, 2 / height) and the camera's near and far, then `color`, the
// material colour the vertex colours multiply.
export function writeLineBlock(
	graphics: Graphics3D, camera: Camera3D, view: CameraView, color: Rgba, out: Span<float32>,
): void {
	for (let i = 0; i < LINE_UNIFORM_LENGTH; i++) { out[i] = 0.0; }
	out[LINE_WIDTH] = graphics.width;
	out[LINE_LENGTH_SCALE] = 1.0;
	out[LINE_PIXEL_SIZE] = 2.0 / (view.texelWidth as float32);
	out[LINE_PIXEL_SIZE + 1] = 2.0 / (view.texelHeight as float32);
	out[LINE_NEAR] = camera.nearPlane;
	out[LINE_FAR] = camera.farPlane;
	out[LINE_COLOR] = color.red;
	out[LINE_COLOR + 1] = color.green;
	out[LINE_COLOR + 2] = color.blue;
	out[LINE_COLOR + 3] = color.alpha;
}

export function clearGraphics(ref graphics: Graphics3D): void {
	graphics.data = MeshData.withUvs();
	graphics.points = [];
}

// Graphics.is3D's setter: a switch drops what was drawn and what waits to be flushed.
export function setIs3D(ref graphics: Graphics3D, is3D: boolean): void {
	if (graphics.is3D == is3D) { return; }
	clearGraphics(graphics);
	graphics.is3D = is3D;
}

export function lineTo(
	ref graphics: Graphics3D, x: float32, y: float32, z: float32,
): Result<void, GraphicsError> {
	const end: Vec3 = vec3(x, y, z);
	if (!finitePoint(end) || !finitePoint(graphics.current) || !finiteColor(graphics.color)) {
		return Result.err(GraphicsError.NonFinite);
	}
	if (graphics.is3D) {
		addPoint(graphics.data.bounds, graphics.current);
		addPoint(graphics.data.bounds, end);
		graphics.points.push({ position: end, color: graphics.color });
		return Result.ok(null);
	}
	const delta: Vec3 = vec3(
		((x as float64) - graphics.current.x) as float32,
		((y as float64) - graphics.current.y) as float32,
		((z as float64) - graphics.current.z) as float32,
	);
	if (!finitePoint(delta)) { return Result.err(GraphicsError.DeltaRange); }
	if (!graphics.data.hasUvs || graphics.data.hasTangents || graphics.data.hasUvB ||
		graphics.data.hasSkin ||
		graphics.data.vertices.length % LIT_TEXTURED_VERTEX_STRIDE != 0 ||
		!graphics.data.validIndexStorage() || graphics.data.vertexCount() % 4 != 0 ||
		graphics.data.indexCount() / 6 != graphics.data.vertexCount() / 4 ||
		graphics.data.indexCount() % 6 != 0) {
		return Result.err(GraphicsError.Shape);
	}
	if (!graphics.data.hasRoomFor(4) || graphics.data.indexCount() > 2147483641) {
		return Result.err(GraphicsError.Capacity);
	}
	const start: int32 = graphics.data.vertexCount();
	for (let corner = 0; corner < 4; corner++) {
		const added = addTexturedVertex(graphics.data, graphics.current, delta,
			{ u: corner >= 2 ? 1.0 : 0.0, v: (corner % 2) as float32 }, graphics.color);
		if (!added.ok) { return Result.err(GraphicsError.Capacity); }
	}
	const first = addTriangle(graphics.data, start, start + 1, start + 2);
	const second = addTriangle(graphics.data, start + 2, start + 3, start + 1);
	if (!first.ok || !second.ok) { return Result.err(GraphicsError.Capacity); }
	addPoint(graphics.data.bounds, end);
	graphics.current = end;
	return Result.ok(null);
}

function mirrored(at: Vec3, from: Vec3): Vec3 {
	return vec3(at.x * 2 - from.x, at.y * 2 - from.y, at.z * 2 - from.z);
}

// Graphics.flush: the points lineTo gathered while is3D become a strip `lineSize` wide in the XY
// plane, mitred at every joint, closed when the last point is the first, with v alternating 0
// and 1 along it. A joint whose miter has no direction (a point repeated, a single point, a
// turn back on itself) is refused and its points are dropped, where Graphics.flushLine writes
// NaN vertices.
export function flushGraphics(ref graphics: Graphics3D): Result<void, GraphicsError> {
	if (graphics.points.length == 0 || !graphics.is3D) {
		graphics.points = [];
		return Result.ok(null);
	}
	let pts: Vec<Vec3> = [];
	for (const point of graphics.points) { pts.push(point.position); }
	let last: int32 = (pts.length as int32) - 1;
	let prev: Vec3 = pts[last];
	let p: Vec3 = pts[0];
	const closed: boolean = p.x == prev.x && p.y == prev.y && p.z == prev.z;
	let count: int32 = pts.length as int32;
	if (!closed) {
		pts.push(mirrored(prev, pts[last - 1]));
		prev = mirrored(p, pts[1]);
	} else if (count > 1) {
		count = count - 1;
		last = last - 1;
		prev = pts[last];
	}
	let offsets: Vec<float32> = [];
	for (let i = 0; i < count; i++) {
		const next: Vec3 = pts[(i + 1) % (pts.length as int32)];
		const nx1: number = prev.y - p.y;
		const ny1: number = p.x - prev.x;
		const ns1: number = 1 / Math.sqrt(nx1 * nx1 + ny1 * ny1);
		const nx2: number = p.y - next.y;
		const ny2: number = next.x - p.x;
		const ns2: number = 1 / Math.sqrt(nx2 * nx2 + ny2 * ny2);
		let nx: number = nx1 * ns1 + nx2 * ns2;
		let ny: number = ny1 * ns1 + ny2 * ns2;
		const ns: number = 1 / Math.sqrt(nx * nx + ny * ny);
		nx = nx * ns;
		ny = ny * ns;
		const d: number = graphics.lineSize * 0.5 / (nx * nx1 * ns1 + ny * ny1 * ns1);
		const ox: float32 = (nx * d) as float32;
		const oy: float32 = (ny * d) as float32;
		if (!Number.isFinite(ox) || !Number.isFinite(oy)) {
			graphics.points = [];
			return Result.err(GraphicsError.Degenerate);
		}
		offsets.push(ox);
		offsets.push(oy);
		prev = p;
		p = next;
	}
	if (!graphics.data.hasUvs || graphics.data.hasTangents || graphics.data.hasUvB ||
		graphics.data.hasSkin ||
		graphics.data.vertices.length % LIT_TEXTURED_VERTEX_STRIDE != 0 ||
		!graphics.data.validIndexStorage()) {
		return Result.err(GraphicsError.Shape);
	}
	if (!graphics.data.hasRoomFor(count * 2) ||
		graphics.data.indexCount() > 2147483647 - count * 6) {
		return Result.err(GraphicsError.Capacity);
	}
	const start: int32 = graphics.data.vertexCount();
	const up: Vec3 = vec3(0, 0, 1);
	let v: float32 = 0;
	for (let i = 0; i < count; i++) {
		const point: GraphicsPoint = graphics.points[i];
		const at: Vec3 = point.position;
		const ox: float32 = offsets[i * 2];
		const oy: float32 = offsets[i * 2 + 1];
		const left = addTexturedVertex(graphics.data, vec3(at.x + ox, at.y + oy, at.z), up,
			{ u: 0, v: v }, point.color);
		const right = addTexturedVertex(graphics.data, vec3(at.x - ox, at.y - oy, at.z), up,
			{ u: 1, v: v }, point.color);
		if (!left.ok || !right.ok) { return Result.err(GraphicsError.Capacity); }
		v = 1 - v;
	}
	for (let i = 0; i < count; i++) {
		if (i == count - 1 && !closed) { break; }
		const base: int32 = start + i * 2;
		const following: int32 = i == last ? start : base + 2;
		const first = addTriangle(graphics.data, base, base + 1, following);
		const second = addTriangle(graphics.data, following, base + 1, following + 1);
		if (!first.ok || !second.ok) { return Result.err(GraphicsError.Capacity); }
	}
	graphics.points = [];
	return Result.ok(null);
}
