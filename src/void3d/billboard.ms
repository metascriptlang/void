// h3d.parts.Particles drawn with a texture: a billboard's instance, and the frames its atlas
// splits into.

import { Vec3 } from "../math/math3d";
import { Rgba } from "./meshData";

// h2d.Tile's uv rect: (u, v) the top left and (u2, v2) the bottom right, in [0, 1].
export struct AtlasTile {
	u: float32;
	v: float32;
	u2: float32;
	v2: float32;
}

export enum AtlasTileError {
	NoFrames,
	FrameOutOfRange,
	NarrowerThanFrames,
}

// h2d.Tile.split(frames) of a whole texture `width` pixels across, then frame `frame` of it.
// Heaps truncates the stride to whole pixels, so a width `frames` does not divide leaves the
// last columns unused, and computes the uv in Float before Particles.draw writes float32.
export function ofFrame(
	this typeof AtlasTile,
	width: int32,
	frames: int32,
	frame: int32,
): Result<AtlasTile, AtlasTileError> {
	if (frames <= 0) { return Result.err(AtlasTileError.NoFrames); }
	if (frame < 0 || frame >= frames) { return Result.err(AtlasTileError.FrameOutOfRange); }
	const stride: int32 = width / frames;
	if (stride <= 0) { return Result.err(AtlasTileError.NarrowerThanFrames); }
	const left: float64 = (frame * stride) as float64;
	const right: float64 = ((frame + 1) * stride) as float64;
	const across: float64 = width as float64;
	return Result.ok({
		u: (left / across) as float32,
		v: 0.0,
		u2: (right / across) as float32,
		v2: 1.0,
	});
}

// h2d.Tile.split(frames) itself: every frame's tile, in order.
export function split(
	this typeof AtlasTile,
	width: int32,
	frames: int32,
): Result<Vec<AtlasTile>, AtlasTileError> {
	if (frames <= 0) { return Result.err(AtlasTileError.NoFrames); }
	let tiles: Vec<AtlasTile> = [];
	for (let frame = 0; frame < frames; frame++) {
		tiles.push(try AtlasTile.ofFrame(width, frames, frame));
	}
	return Result.ok(tiles);
}

// Bevy's sprite Anchor: the point of the quad that sits at the instance's position, in quad
// units across and up, centre at 0. Heaps' Particles.draw always centres.
export struct Anchor {
	x: float32;
	y: float32;
}

export const ANCHOR_CENTER: Anchor = { x: 0.0, y: 0.0 };
export const ANCHOR_BOTTOM_LEFT: Anchor = { x: -0.5, y: -0.5 };
export const ANCHOR_BOTTOM_CENTER: Anchor = { x: 0.0, y: -0.5 };
export const ANCHOR_BOTTOM_RIGHT: Anchor = { x: 0.5, y: -0.5 };
export const ANCHOR_CENTER_LEFT: Anchor = { x: -0.5, y: 0.0 };
export const ANCHOR_CENTER_RIGHT: Anchor = { x: 0.5, y: 0.0 };
export const ANCHOR_TOP_LEFT: Anchor = { x: -0.5, y: 0.5 };
export const ANCHOR_TOP_CENTER: Anchor = { x: 0.0, y: 0.5 };
export const ANCHOR_TOP_RIGHT: Anchor = { x: 0.5, y: 0.5 };

export const BILLBOARD_INSTANCE_STRIDE: int32 = 15;

// What Particles.draw writes for a particle, with its root in world space (isAbsolute) and its
// size in world units. The texel is multiplied by `color`.
export struct BillboardInstance {
	position: Vec3;
	width: float32;
	height: float32;
	anchor: Anchor;
	tile: AtlasTile;
	color: Rgba;
}

export function pushTo(this instance: BillboardInstance, ref out: Vec<float32>): void {
	out.push(instance.position.x);
	out.push(instance.position.y);
	out.push(instance.position.z);
	out.push(instance.width);
	out.push(instance.height);
	out.push(instance.anchor.x);
	out.push(instance.anchor.y);
	out.push(instance.tile.u);
	out.push(instance.tile.v);
	out.push(instance.tile.u2);
	out.push(instance.tile.v2);
	out.push(instance.color.red);
	out.push(instance.color.green);
	out.push(instance.color.blue);
	out.push(instance.color.alpha);
}
