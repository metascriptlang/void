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

export enum AtlasError {
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
): Result<AtlasTile, AtlasError> {
	if (frames <= 0) { return Result.err(AtlasError.NoFrames); }
	if (frame < 0 || frame >= frames) { return Result.err(AtlasError.FrameOutOfRange); }
	const stride: int32 = width / frames;
	if (stride == 0) { return Result.err(AtlasError.NarrowerThanFrames); }
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

// position(3), width and height, the tile u, v, u2, v2, then rgba: the Billboard layout (gpu3d.c).
export const BILLBOARD_INSTANCE_STRIDE: int32 = 13;

// What Particles.draw writes for a particle, with its root in world space (isAbsolute) and its
// size in world units. The texel is multiplied by `color`.
export struct BillboardInstance {
	position: Vec3;
	width: float32;
	height: float32;
	tile: AtlasTile;
	color: Rgba;
}

export function pushTo(this instance: BillboardInstance, ref out: Vec<float32>): void {
	out.push(instance.position.x);
	out.push(instance.position.y);
	out.push(instance.position.z);
	out.push(instance.width);
	out.push(instance.height);
	out.push(instance.tile.u);
	out.push(instance.tile.v);
	out.push(instance.tile.u2);
	out.push(instance.tile.v2);
	out.push(instance.color.red);
	out.push(instance.color.green);
	out.push(instance.color.blue);
	out.push(instance.color.alpha);
}
