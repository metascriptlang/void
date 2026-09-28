import { Vec3, vec3 } from "../math/math3d";
import { OrthoCamera, CameraBasis } from "../void3d/camera";
import {
	AtlasTile,
	AtlasTileError,
	BillboardInstance,
	BILLBOARD_INSTANCE_STRIDE,
	ANCHOR_CENTER,
	ANCHOR_BOTTOM_LEFT,
	ANCHOR_BOTTOM_CENTER,
	ANCHOR_BOTTOM_RIGHT,
	ANCHOR_CENTER_LEFT,
	ANCHOR_CENTER_RIGHT,
	ANCHOR_TOP_LEFT,
	ANCHOR_TOP_CENTER,
	ANCHOR_TOP_RIGHT,
} from "../void3d/billboard";

function tileOf(width: int32, frames: int32, frame: int32): AtlasTile {
	const tile: Result<AtlasTile, AtlasTileError> = AtlasTile.ofFrame(width, frames, frame);
	if (tile.ok) { return tile.value; }
	console.log(`frame ${frame} of ${frames} across ${width}: ${tile.error.toString()}`);
	unreachable;
}

function refusal(width: int32, frames: int32, frame: int32): AtlasTileError {
	const tile: Result<AtlasTile, AtlasTileError> = AtlasTile.ofFrame(width, frames, frame);
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
	assert refusal(64, 0, 0) == AtlasTileError.NoFrames;
	assert refusal(64, 4, 4) == AtlasTileError.FrameOutOfRange;
	assert refusal(64, 4, -1) == AtlasTileError.FrameOutOfRange;
	assert refusal(2, 3, 0) == AtlasTileError.NarrowerThanFrames;
	assert refusal(0, 4, 0) == AtlasTileError.NarrowerThanFrames;
	assert refusal(-64, 4, 1) == AtlasTileError.NarrowerThanFrames;
}

test "an atlas split gives every frame's tile in order, and refuses what a frame refuses" {
	const tiles: Result<Vec<AtlasTile>, AtlasTileError> = AtlasTile.split(64, 4);
	assert tiles.ok;
	if (tiles.ok) {
		assert (tiles.value.length as int32) == 4;
		for (let frame = 0; frame < 4; frame++) {
			assert tiles.value[frame] == tileOf(64, 4, frame);
		}
	}
	const none: Result<Vec<AtlasTile>, AtlasTileError> = AtlasTile.split(64, 0);
	assert !none.ok && none.error == AtlasTileError.NoFrames;
	const negative: Result<Vec<AtlasTile>, AtlasTileError> = AtlasTile.split(-64, 4);
	assert !negative.ok && negative.error == AtlasTileError.NarrowerThanFrames;
}

test "a billboard instance is written in the order of the Billboard layout" {
	const instance: BillboardInstance = {
		position: vec3(1.0, 2.0, 3.0),
		width: 4.0,
		height: 5.0,
		anchor: { x: 6.0, y: 7.0 },
		tile: { u: 8.0, v: 9.0, u2: 10.0, v2: 11.0 },
		color: { red: 12.0, green: 13.0, blue: 14.0, alpha: 15.0 },
	};
	let out: Vec<float32> = [];
	instance.pushTo(out);
	assert (out.length as int32) == BILLBOARD_INSTANCE_STRIDE;
	for (let i = 0; i < BILLBOARD_INSTANCE_STRIDE; i++) {
		assert out[i] == ((i + 1) as float32);
	}
}

test "Bevy's anchors: the centre is zero, a side is half a quad away" {
	assert ANCHOR_CENTER.x == 0.0 && ANCHOR_CENTER.y == 0.0;
	assert ANCHOR_BOTTOM_CENTER.x == 0.0 && ANCHOR_BOTTOM_CENTER.y == -0.5;
	assert ANCHOR_TOP_CENTER.x == 0.0 && ANCHOR_TOP_CENTER.y == 0.5;
	assert ANCHOR_CENTER_LEFT.x == -0.5 && ANCHOR_CENTER_LEFT.y == 0.0;
	assert ANCHOR_CENTER_RIGHT.x == 0.5 && ANCHOR_CENTER_RIGHT.y == 0.0;
	assert ANCHOR_BOTTOM_LEFT.x == -0.5 && ANCHOR_BOTTOM_LEFT.y == -0.5;
	assert ANCHOR_BOTTOM_RIGHT.x == 0.5 && ANCHOR_BOTTOM_RIGHT.y == -0.5;
	assert ANCHOR_TOP_LEFT.x == -0.5 && ANCHOR_TOP_LEFT.y == 0.5;
	assert ANCHOR_TOP_RIGHT.x == 0.5 && ANCHOR_TOP_RIGHT.y == 0.5;
}

function near(a: float32, b: float32): boolean {
	const difference: float32 = a - b;
	return difference < 0.000001 && difference > -0.000001;
}

test "the billboard program normal, right cross up, points back toward the camera" {
	const yaws: Vec<float32> = [0.0, 0.785398, 2.5, -1.2];
	const pitches: Vec<float32> = [0.2, 0.6, 1.2];
	for (const yaw of yaws) {
		for (const pitch of pitches) {
			const camera: OrthoCamera = {
				target: vec3(0.0, 0.0, 0.0),
				yaw: yaw,
				pitch: pitch,
				worldPerTexel: 0.05,
				nearPlane: -50.0,
				farPlane: 50.0,
				snap: false,
			};
			const basis: CameraBasis = camera.basisOf();
			const normal: Vec3 = basis.right.cross(basis.up);
			assert near(normal.x, -basis.forward.x) && near(normal.y, -basis.forward.y);
			assert near(normal.z, -basis.forward.z);
		}
	}
}
