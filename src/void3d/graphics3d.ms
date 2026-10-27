import { Vec3, vec3 } from "../math/math3d";
import {
	MeshData, Rgba, LIT_TEXTURED_VERTEX_STRIDE, addTexturedVertex, addTriangle,
	hasRoomFor, validIndexStorage, vertexCount, indexCount,
} from "./meshData";
import { addPoint } from "./bounds";

export struct Graphics3D {
	data: MeshData;
	current: Vec3;
	color: Rgba;
	width: float32;
}

export enum GraphicsError { NonFinite, DeltaRange, Shape, Capacity }

export function create(this typeof Graphics3D): Graphics3D {
	return {
		data: MeshData.withUvs(), current: vec3(0, 0, 0), width: 1.5,
		color: { red: 0, green: 0, blue: 0, alpha: 1 },
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
	const result = setGraphicsColorF(graphics,
		((color >> 16) & 0xff) as float32 / 255.0,
		((color >> 8) & 0xff) as float32 / 255.0,
		(color & 0xff) as float32 / 255.0, alpha);
	if (!result.ok) { return result; }
	if (width > 0) { graphics.width = width; }
	return Result.ok(null);
}

export function moveTo(
	ref graphics: Graphics3D, x: float32, y: float32, z: float32,
): Result<void, GraphicsError> {
	const point: Vec3 = vec3(x, y, z);
	if (!finitePoint(point)) { return Result.err(GraphicsError.NonFinite); }
	graphics.current = point;
	return Result.ok(null);
}

export function clearGraphics(ref graphics: Graphics3D): void {
	graphics.data = MeshData.withUvs();
}

export function lineTo(
	ref graphics: Graphics3D, x: float32, y: float32, z: float32,
): Result<void, GraphicsError> {
	const end: Vec3 = vec3(x, y, z);
	if (!finitePoint(end) || !finitePoint(graphics.current) || !finiteColor(graphics.color)) {
		return Result.err(GraphicsError.NonFinite);
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
