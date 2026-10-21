import { Vec3, vec3 } from "../math/math3d";
import {
	OrientedBounds3D, OrientedBoundsError, overlapsOrientedBounds,
} from "../void3d/orientedBounds";

function box(center: Vec3, halfSize: Vec3): OrientedBounds3D {
	return {
		center: center, halfSize: halfSize,
		axisX: vec3(1, 0, 0), axisY: vec3(0, 1, 0), axisZ: vec3(0, 0, 1),
	};
}

function overlap(a: OrientedBounds3D, b: OrientedBounds3D, expected: boolean): boolean {
	const result = overlapsOrientedBounds(a, b);
	return result.ok && result.value == expected;
}

function permuted(b: OrientedBounds3D, shift: int32): OrientedBounds3D {
	if (shift == 0) { return b; }
	if (shift == 1) {
		return {
			center: b.center, axisX: b.axisY, axisY: b.axisZ, axisZ: b.axisX,
			halfSize: vec3(b.halfSize.y, b.halfSize.z, b.halfSize.x),
		};
	}
	return {
		center: b.center, axisX: b.axisZ, axisY: b.axisX, axisZ: b.axisY,
		halfSize: vec3(b.halfSize.z, b.halfSize.x, b.halfSize.y),
	};
}

function facePair(): OrientedBounds3D[] {
	return [
		box(vec3(0, 0, 0), vec3(0.675848662853241, 1.1299715042114258, 0.27346915006637573)),
		{
			center: vec3(-2.6321215629577637, 1.8770520687103271, 1.2805380821228027),
			axisX: vec3(0.6560178399085999, -0.6074200868606567, -0.4479747712612152),
			axisY: vec3(-0.3000214397907257, 0.33476123213768005, -0.8932648301124573),
			axisZ: vec3(0.6925516128540039, 0.7203997373580933, 0.037370312958955765),
			halfSize: vec3(1.362998366355896, 1.7964725494384766, 1.9112564325332642),
		},
	];
}

function crossPair(): OrientedBounds3D[] {
	return [
		box(vec3(0, 0, 0), vec3(1.138477087020874, 0.7072117924690247, 1.2375452518463135)),
		{
			center: vec3(0.6164657473564148, 2.567338705062866, 0.9917023181915283),
			axisX: vec3(-0.2681606411933899, 0.032723426818847656, 0.9628182649612427),
			axisY: vec3(0.8427367806434631, 0.4922158122062683, 0.21798698604106903),
			axisZ: vec3(-0.4667811095714569, 0.869857907295227, -0.1595701426267624),
			halfSize: vec3(1.9177899360656738, 0.4249114692211151, 1.8558366298675537),
		},
	];
}

test "oriented bounds SAT identity self overlap and closed face edge corner contact" {
	const a = box(vec3(0, 0, 0), vec3(1, 1, 1));
	assert overlap(a, a, true);
	assert overlap(a, box(vec3(2, 0, 0), vec3(1, 1, 1)), true);
	assert overlap(a, box(vec3(2, 2, 0), vec3(1, 1, 1)), true);
	assert overlap(a, box(vec3(2, 2, 2), vec3(1, 1, 1)), true);
	assert overlap(a, box(vec3(-2.01, 0, 0), vec3(1, 1, 1)), false);
}

test "oriented bounds rotated and reflected axes preserve physical box" {
	const a = box(vec3(0, 0, 0), vec3(1, 1, 1));
	let b = box(vec3(2.2, 0, 0), vec3(1, 1, 1));
	b.axisX = vec3(0.7071067811865476, 0.7071067811865476, 0);
	b.axisY = vec3(-0.7071067811865476, 0.7071067811865476, 0);
	assert overlap(a, b, true);
	b.axisY = b.axisY.scaled(-1);
	assert overlap(a, b, true);
	b.center.x = 3;
	assert overlap(a, b, false);
}

test "oriented bounds each of six face normals is independently necessary" {
	const pair = facePair();
	for (let i: int32 = 0; i < 3; i++) {
		const shifted = permuted(pair[1], i);
		assert overlap(pair[0], shifted, false);
		assert overlap(shifted, pair[0], false);
	}
}

test "oriented bounds all nine edge cross axes are independently necessary" {
	const pair = crossPair();
	for (let i: int32 = 0; i < 3; i++) {
		for (let j: int32 = 0; j < 3; j++) {
			const a = permuted(pair[0], i);
			const b = permuted(pair[1], j);
			assert overlap(a, b, false);
			assert overlap(b, a, false);
		}
	}
}

test "oriented bounds zero half extents remain closed geometric points and planes" {
	const point = box(vec3(0, 0, 0), vec3(0, 0, 0));
	assert overlap(point, point, true);
	assert overlap(point, box(vec3(1, 0, 0), vec3(0, 0, 0)), false);
	const flat = box(vec3(0, 0, 0), vec3(1, 0, 1));
	assert overlap(flat, flat, true);
	assert overlap(flat, box(vec3(0, 0.25, 0), vec3(1, 0, 1)), false);
}

test "oriented bounds reference epsilon intentionally keeps near contact conservative" {
	const a = box(vec3(0, 0, 0), vec3(0.5, 1e10, 0.5));
	assert overlap(a, box(vec3(1.5, 0, 0), vec3(0.5, 1e10, 0.5)), true);
	assert overlap(a, box(vec3(3, 0, 0), vec3(0.5, 1e10, 0.5)), false);
}

test "oriented bounds widen center differences before float32 subtraction overflow" {
	const a = box(vec3(-3e38, 0, 0), vec3(3e38, 1, 1));
	const b = box(vec3(3e38, 0, 0), vec3(3e38, 1, 1));
	assert overlap(a, b, true);
	assert overlap(a, box(vec3(3e38, 0, 0), vec3(1e38, 1, 1)), false);
	assert a.center.x == -3e38 && b.center.x == 3e38;
}

test "oriented bounds refuse nonfinite negative half sizes and invalid frames" {
	const a = box(vec3(0, 0, 0), vec3(1, 1, 1));
	let bad = a;
	bad.halfSize.y = -1;
	const negative = overlapsOrientedBounds(a, bad);
	assert !negative.ok && negative.error == OrientedBoundsError.NegativeHalfSize;
	bad = a;
	bad.axisX.x = 2;
	const nonunit = overlapsOrientedBounds(bad, a);
	assert !nonunit.ok && nonunit.error == OrientedBoundsError.NonOrthonormalAxes;
	bad = a;
	bad.axisY = bad.axisX;
	const parallel = overlapsOrientedBounds(a, bad);
	assert !parallel.ok && parallel.error == OrientedBoundsError.NonOrthonormalAxes;
	bad = a;
	bad.center.z = (1.0 / 0.0) as float32;
	const nonfinite = overlapsOrientedBounds(bad, a);
	assert !nonfinite.ok && nonfinite.error == OrientedBoundsError.NonFinite;
	assert a.center.z == 0 && a.axisX.x == 1 && a.halfSize.y == 1;
}
