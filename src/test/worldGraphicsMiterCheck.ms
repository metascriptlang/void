import { vec3 } from "../math/math3d";
import { worldGraphicsMiter, WorldMiterError } from "../void3d/worldGraphicsMiter";

function near(a: float32, b: float32): boolean { return Math.abs(a - b) < 0.00001; }

test "world miter straight X and Z use left offsets in XZ plane" {
	const x = worldGraphicsMiter(vec3(-1, 0, 0), vec3(0, 0, 0), vec3(1, 0, 0), 2);
	assert x.ok && x.value.x == 0 && x.value.y == 0 && x.value.z == 1;
	const z = worldGraphicsMiter(vec3(0, 0, -1), vec3(0, 0, 0), vec3(0, 0, 1), 4);
	assert z.ok && z.value.x == -2 && z.value.y == 0 && z.value.z == 0;
}

test "world miter left and right angle share one joined corner" {
	const left = worldGraphicsMiter(vec3(-2, 0, 0), vec3(0, 0, 0), vec3(0, 0, 2), 2);
	assert left.ok && near(left.value.x, -1) && near(left.value.z, 1);
	const right = worldGraphicsMiter(vec3(-2, 0, 0), vec3(0, 0, 0), vec3(0, 0, -2), 2);
	assert right.ok && near(right.value.x, 1) && near(right.value.z, 1);
}

test "world miter primary is not bevel capped at an acute corner" {
	const offset = worldGraphicsMiter(vec3(-1, 0, 0), vec3(0, 0, 0), vec3(-10, 0, 1), 2);
	assert offset.ok && near(offset.value.x, -20.04987562112089);
	assert Math.abs(offset.value.x) > 20;
	assert near(offset.value.z, 1) && offset.value.y == 0;
}

test "world miter explicit planar restriction ignores height differences" {
	const offset = worldGraphicsMiter(
		vec3(-1, -100, 0), vec3(0, 30, 0), vec3(1, 200, 0), 2,
	);
	assert offset.ok && offset.value.x == 0 && offset.value.y == 0 && offset.value.z == 1;
}

test "world miter zero width stays finite for a valid path" {
	const offset = worldGraphicsMiter(vec3(-1, 0, 0), vec3(0, 0, 0), vec3(1, 0, 0), 0);
	assert offset.ok && offset.value.x == 0 && offset.value.y == 0 && offset.value.z == 0;
}

test "world miter degenerate planar segments and reversals return errors, not NaNs" {
	const duplicate = worldGraphicsMiter(vec3(0, 0, 0), vec3(0, 0, 0), vec3(1, 0, 0), 2);
	assert !duplicate.ok && duplicate.error == WorldMiterError.Degenerate;
	const vertical = worldGraphicsMiter(vec3(0, 1, 0), vec3(0, 0, 0), vec3(1, 0, 0), 2);
	assert !vertical.ok && vertical.error == WorldMiterError.Degenerate;
	const reversal = worldGraphicsMiter(vec3(-1, 0, 0), vec3(0, 0, 0), vec3(-1, 0, 0), 2);
	assert !reversal.ok && reversal.error == WorldMiterError.Degenerate;
}

test "world miter refuses invalid width nonfinite input and float32 overflow" {
	const negative = worldGraphicsMiter(vec3(-1, 0, 0), vec3(0, 0, 0), vec3(1, 0, 0), -1);
	assert !negative.ok && negative.error == WorldMiterError.Width;
	const bad = worldGraphicsMiter(
		vec3((1.0 / 0.0) as float32, 0, 0), vec3(0, 0, 0), vec3(1, 0, 0), 2,
	);
	assert !bad.ok && bad.error == WorldMiterError.NonFinite;
	const overflow = worldGraphicsMiter(
		vec3(-1, 0, 0), vec3(0, 0, 0), vec3(-1, 0, 1), 3.0e38,
	);
	assert !overflow.ok && overflow.error == WorldMiterError.OutOfRange;
}
