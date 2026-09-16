import { sinf, cosf } from "../math/mat4";

export const LIT_VERTEX_STRIDE: int32 = 10;

export struct Vec3 {
	x: float32;
	y: float32;
	z: float32;
}

export struct Rgba {
	red: float32;
	green: float32;
	blue: float32;
	alpha: float32;
}

export struct Box {
	base: Vec3;
	size: Vec3;
	yaw: float32;
	tilt: float32;
	color: Rgba;
}

struct BoxFrame {
	base: Vec3;
	yawSin: float32;
	yawCos: float32;
	tiltSin: float32;
	tiltCos: float32;
}

function toWorld(this frame: BoxFrame, local: Vec3): Vec3 {
	const tiltedY: float32 = local.y * frame.tiltCos - local.z * frame.tiltSin;
	const tiltedZ: float32 = local.y * frame.tiltSin + local.z * frame.tiltCos;
	return {
		x: frame.base.x + local.x * frame.yawCos + tiltedZ * frame.yawSin,
		y: frame.base.y + tiltedY,
		z: frame.base.z - local.x * frame.yawSin + tiltedZ * frame.yawCos,
	};
}

function rotate(this frame: BoxFrame, direction: Vec3): Vec3 {
	const origin: Vec3 = { x: 0.0, y: 0.0, z: 0.0 };
	const unplaced: BoxFrame = { ...frame, base: origin };
	return unplaced.toWorld(direction);
}

function pushVertex(ref vertices: Vec<float32>, position: Vec3, normal: Vec3, color: Rgba): void {
	vertices.push(position.x);
	vertices.push(position.y);
	vertices.push(position.z);
	vertices.push(normal.x);
	vertices.push(normal.y);
	vertices.push(normal.z);
	vertices.push(color.red);
	vertices.push(color.green);
	vertices.push(color.blue);
	vertices.push(color.alpha);
}

function pushQuad(ref vertices: Vec<float32>, a: Vec3, b: Vec3, c: Vec3, d: Vec3, normal: Vec3, color: Rgba): void {
	pushVertex(vertices, a, normal, color);
	pushVertex(vertices, b, normal, color);
	pushVertex(vertices, c, normal, color);
	pushVertex(vertices, a, normal, color);
	pushVertex(vertices, c, normal, color);
	pushVertex(vertices, d, normal, color);
}

export function pushBox(ref vertices: Vec<float32>, box: Box): void {
	const frame: BoxFrame = {
		base: box.base,
		yawSin: sinf(box.yaw),
		yawCos: cosf(box.yaw),
		tiltSin: sinf(box.tilt),
		tiltCos: cosf(box.tilt),
	};
	const halfX: float32 = box.size.x * 0.5;
	const halfZ: float32 = box.size.z * 0.5;
	const top: float32 = box.size.y;
	const leftBottomBack: Vec3 = frame.toWorld({ x: -halfX, y: 0.0, z: -halfZ });
	const rightBottomBack: Vec3 = frame.toWorld({ x: halfX, y: 0.0, z: -halfZ });
	const leftBottomFront: Vec3 = frame.toWorld({ x: -halfX, y: 0.0, z: halfZ });
	const rightBottomFront: Vec3 = frame.toWorld({ x: halfX, y: 0.0, z: halfZ });
	const leftTopBack: Vec3 = frame.toWorld({ x: -halfX, y: top, z: -halfZ });
	const rightTopBack: Vec3 = frame.toWorld({ x: halfX, y: top, z: -halfZ });
	const leftTopFront: Vec3 = frame.toWorld({ x: -halfX, y: top, z: halfZ });
	const rightTopFront: Vec3 = frame.toWorld({ x: halfX, y: top, z: halfZ });
	const color: Rgba = box.color;

	pushQuad(vertices, leftTopBack, rightTopBack, rightTopFront, leftTopFront, frame.rotate({ x: 0.0, y: 1.0, z: 0.0 }), color);
	pushQuad(vertices, rightBottomBack, rightBottomFront, rightTopFront, rightTopBack, frame.rotate({ x: 1.0, y: 0.0, z: 0.0 }), color);
	pushQuad(vertices, leftBottomFront, leftBottomBack, leftTopBack, leftTopFront, frame.rotate({ x: -1.0, y: 0.0, z: 0.0 }), color);
	pushQuad(vertices, leftBottomFront, rightBottomFront, rightTopFront, leftTopFront, frame.rotate({ x: 0.0, y: 0.0, z: 1.0 }), color);
	pushQuad(vertices, rightBottomBack, leftBottomBack, leftTopBack, rightTopBack, frame.rotate({ x: 0.0, y: 0.0, z: -1.0 }), color);
}

export function pushGround(ref vertices: Vec<float32>, halfSize: float32, color: Rgba): void {
	const up: Vec3 = { x: 0.0, y: 1.0, z: 0.0 };
	pushQuad(
		vertices,
		{ x: -halfSize, y: 0.0, z: -halfSize },
		{ x: halfSize, y: 0.0, z: -halfSize },
		{ x: halfSize, y: 0.0, z: halfSize },
		{ x: -halfSize, y: 0.0, z: halfSize },
		up,
		color,
	);
}
