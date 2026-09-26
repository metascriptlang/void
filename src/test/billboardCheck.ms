import { AtlasTile, AtlasError } from "../void3d/billboard";

function tileOf(width: int32, frames: int32, frame: int32): AtlasTile {
	const tile: Result<AtlasTile, AtlasError> = AtlasTile.ofFrame(width, frames, frame);
	if (tile.ok) { return tile.value; }
	console.log(`frame ${frame} of ${frames} across ${width}: ${tile.error.toString()}`);
	unreachable;
}

function refusal(width: int32, frames: int32, frame: int32): AtlasError {
	const tile: Result<AtlasTile, AtlasError> = AtlasTile.ofFrame(width, frames, frame);
	if (!tile.ok) { return tile.error; }
	console.log(`frame ${frame} of ${frames} across ${width} was a tile`);
	unreachable;
}

test "an atlas four frames across splits into quarters, the whole height each" {
	const first: AtlasTile = tileOf(64, 4, 0);
	assert first.u == 0.0 && first.u2 == 0.25 && first.v == 0.0 && first.v2 == 1.0;
	const last: AtlasTile = tileOf(64, 4, 3);
	assert last.u == 0.75 && last.u2 == 1.0;
}

test "an atlas three frames across puts its edges at the float32 thirds" {
	const third: float32 = 0.33333334;
	const twoThirds: float32 = 0.6666667;
	const middle: AtlasTile = tileOf(48, 3, 1);
	assert middle.u == third && middle.u2 == twoThirds;
	assert middle.u < middle.u2 && tileOf(48, 3, 2).u == twoThirds;
}

test "a width the frames do not divide leaves its last columns out, as Tile.split does" {
	const clipped: float32 = 0.96;
	const last: AtlasTile = tileOf(50, 3, 2);
	assert last.u2 == clipped && last.u2 < 1.0;
}

test "a frame outside the atlas, no frames, or frames narrower than a pixel are refused" {
	assert refusal(64, 0, 0) == AtlasError.NoFrames;
	assert refusal(64, 4, 4) == AtlasError.FrameOutOfRange;
	assert refusal(64, 4, -1) == AtlasError.FrameOutOfRange;
	assert refusal(2, 3, 0) == AtlasError.NarrowerThanFrames;
}
