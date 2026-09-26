// h3d.parts.Particles drawn with a texture: the frames a billboard's atlas splits into.

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
