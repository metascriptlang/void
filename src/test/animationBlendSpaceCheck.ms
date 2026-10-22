import { vec3 } from "../math/math3d";
import { Transform3D } from "../void3d/scene";
import { GltfCurve, GltfCurvePath, GltfCurveMode, forValues } from "../void3d/gltfCurve";
import {
	AnimationCompose, AnimationComponent, AnimationRestTarget,
	AnimationChildSample, stageWeightedCompose,
} from "../void3d/animationCompose";
import { AnimationTransitionClip, forTracks } from "../void3d/animationTransition";
import {
	AnimationBlendSpace2D, AnimationBlendSpaceError, AnimationBlendSpacePoint, triangulate,
	setBlendSpacePosition, setBlendSpaceSmoothing, advanceBlendSpace, evaluateBlendSpace, create,
} from "../void3d/animationBlendSpace";


function close(actual: float64, expected: float64): boolean {
	return Math.abs(actual - expected) < 0.000002;
}

function ramp(path: GltfCurvePath, seconds: float32, last: Vec<float32>): AnimationTransitionClip {
	let values: Vec<float32> = [0.0, 0.0, 0.0];
	for (const value of last) { values.push(value); }
	const curve = GltfCurve.forValues(path, GltfCurveMode.Linear, [0.0, seconds], values);
	if (!curve.ok) { unreachable; }
	const made = AnimationTransitionClip.forTracks([{ sourceNode: 0, curve: curve.value }], [], true);
	if (!made.ok) { unreachable; }
	return made.value;
}

function targets(): Vec<AnimationRestTarget> {
	return [{ sourceNode: 0, rest: Transform3D.identity() }];
}

function points(syncThird: boolean): Vec<AnimationBlendSpacePoint> {
	return [
		{ x: 0.0, y: 0.0, clip: ramp(GltfCurvePath.Translation, 2.0, [2.0, 0.0, 0.0]), keepSync: true },
		{ x: 4.0, y: 0.0, clip: ramp(GltfCurvePath.Translation, 4.0, [0.0, 4.0, 0.0]), keepSync: true },
		{ x: 0.0, y: 4.0, clip: ramp(GltfCurvePath.Translation, 2.0, [0.0, 0.0, 2.0]), keepSync: syncThird },
	];
}

function fixture(syncThird: boolean): AnimationBlendSpace2D {
	const made = AnimationBlendSpace2D.create(targets(), points(syncThird));
	if (!made.ok) { unreachable; }
	return made.value;
}

function weightOf(space: AnimationBlendSpace2D, point: int32): float64 {
	const triangle = space.triangles[space.current];
	if (triangle.a == point) { return space.weights[0]; }
	if (triangle.b == point) { return space.weights[1]; }
	if (triangle.c == point) { return space.weights[2]; }
	return 0.0;
}

test "animationBlendSpace inside a triangle the weights are barycentric per point" {
	let space = fixture(true);
	assert space.triangles.length == 1;
	assert setBlendSpacePosition(space, 1.0, 1.0).ok && advanceBlendSpace(space, 0.0).ok;
	assert close(weightOf(space, 0), 0.5) && close(weightOf(space, 1), 0.25);
	assert close(weightOf(space, 2), 0.25);
	assert setBlendSpacePosition(space, 3.0, 0.5).ok && advanceBlendSpace(space, 0.0).ok;
	assert close(weightOf(space, 0), 0.125) && close(weightOf(space, 1), 0.75);
	assert close(weightOf(space, 2), 0.125);
	assert close(space.outsideSpeedScale, 1.0);
}

test "animationBlendSpace outside every triangle takes the closest edge and its speed ratio" {
	let space = fixture(true);
	assert setBlendSpacePosition(space, 3.0, -1.0).ok && advanceBlendSpace(space, 0.0).ok;
	assert close(weightOf(space, 0), 0.25) && close(weightOf(space, 1), 0.75);
	assert weightOf(space, 2) == 0.0;
	assert close(space.outsideSpeedScale, 1.0540925533894598);
}

test "animationBlendSpace phase advances over the previous blend length and clips sit at duration times phase" {
	let space = fixture(true);
	assert setBlendSpacePosition(space, 1.0, 1.0).ok;
	assert advanceBlendSpace(space, 0.25).ok;
	assert close(space.phase, 0.25) && close(space.blendLength, 2.5);
	assert close(space.sides[0].time, 0.5) && close(space.sides[1].time, 1.0);
	assert close(space.sides[2].time, 0.5);
	assert evaluateBlendSpace(space).ok;
	const out = space.compose.output[0].value.position;
	assert close(out.x, 0.5 * 0.5) && close(out.y, 0.25 * 1.0) && close(out.z, 0.25 * 0.5);
	assert advanceBlendSpace(space, 0.5).ok;
	assert close(space.phase, 0.45);
	assert close(space.sides[0].time, 0.9) && close(space.sides[1].time, 1.8);
	space.scaleSpeedOutsideOfBounds = true;
	assert setBlendSpacePosition(space, 3.0, -1.0).ok;
	assert advanceBlendSpace(space, 0.0).ok;
	assert close(space.blendLength, 3.5);
	assert advanceBlendSpace(space, 0.25).ok;
	assert close(space.phase, 0.45 + 0.25 * 1.0540925533894598 / 3.5);
}

test "animationBlendSpace an unsynced point advances by dt and shares its weight with the synced ones" {
	let space = fixture(false);
	assert setBlendSpacePosition(space, 1.0, 1.0).ok;
	assert advanceBlendSpace(space, 0.25).ok;
	assert close(space.blendLength, 2.75);
	assert close(space.sides[2].time, 0.25) && close(space.sides[0].time, 0.5);
	assert advanceBlendSpace(space, 0.5).ok;
	assert close(space.phase, 0.25 + 0.5 / 2.75);
	assert close(space.sides[0].time, 2.0 * (0.25 + 0.5 / 2.75));
	assert close(space.sides[2].time, 0.75);
}

test "animationBlendSpace smoothing is simpleSpringDamper over the half life" {
	let space = fixture(true);
	assert setBlendSpaceSmoothing(space, 0.5, 0.0).ok;
	assert setBlendSpacePosition(space, 1.0, 1.0).ok;
	assert advanceBlendSpace(space, 0.1).ok;
	assert close(space.xSmoothed, 0.03176698545853818);
	assert close(space.xVelocity, 0.5827152412889413);
	assert close(space.ySmoothed, 1.0);
	assert !setBlendSpaceSmoothing(space, -1.0, 0.0).ok;
}

test "animationCompose weighted blend takes rotation about the rest and skips zero weights in presence" {
	const created = AnimationCompose.create([{
		sourceNode: 0,
		rest: { ...Transform3D.identity(), rotation: { x: 0.0, y: 0.0, z: 0.70710678, w: 0.70710678 } },
	}]);
	assert created.ok;
	if (!created.ok) { return; }
	let compose = created.value;
	const translation = 0 as BitSet<AnimationComponent>;
	const a: AnimationChildSample = { seconds: 0.0, samples: [{
		sourceNode: 0, value: { ...Transform3D.identity(), position: vec3(1.0, 0.0, 0.0) },
		present: AnimationComponent.Translation | AnimationComponent.Rotation,
	}] };
	const b: AnimationChildSample = { seconds: 0.0, samples: [{
		sourceNode: 0,
		value: { ...Transform3D.identity(), rotation: { x: 0.0, y: 0.0, z: -1.0, w: 0.0 } },
		present: translation.incl(AnimationComponent.Rotation),
	}] };
	const c: AnimationChildSample = { seconds: 0.0, samples: [{
		sourceNode: 0,
		value: {
			...Transform3D.identity(), position: vec3(0.0, 0.0, 3.0),
			rotation: { x: 0.0, y: 0.0, z: 0.5, w: 0.8660254 },
		},
		present: AnimationComponent.Translation | AnimationComponent.Rotation,
	}] };
	assert stageWeightedCompose(compose, a, b, c, [0.5, 0.25, 0.25]).ok;
	const out = compose.output[0];
	assert close(out.value.position.x, 0.5) && close(out.value.position.z, 0.75);
	assert close(out.value.rotation.z, 0.4637034049132155) && close(out.value.rotation.w, 0.8859904922017451);
	assert out.present.has(AnimationComponent.Rotation) && out.present.has(AnimationComponent.Translation);
	assert stageWeightedCompose(compose, a, b, c, [0.5, 0.0, 0.5]).ok;
	assert compose.output[0].present == (AnimationComponent.Translation | AnimationComponent.Rotation);
	assert stageWeightedCompose(compose, a, b, c, [0.0, 1.0, 0.0]).ok;
	assert compose.output[0].present == translation.incl(AnimationComponent.Rotation);
	assert !stageWeightedCompose(compose, a, b, c, [0.5, 0.5, 0.5]).ok;
	assert !stageWeightedCompose(compose, a, b, c, [1.5, -0.5, 0.0]).ok;
	assert !stageWeightedCompose(compose, a, b, c, [NaN as float64, 0.5, 0.5]).ok;
	assert !stageWeightedCompose(compose, a, b, c, [0.5, 0.5]).ok;
}

test "animationBlendSpace triangulates a convex quad into two triangles that use every point" {
	const triangles = triangulate([0.0, 1.0, 0.0, 1.0], [0.0, 0.0, 1.0, 0.9]);
	assert triangles.ok;
	if (!triangles.ok) { return; }
	assert triangles.value.length == 2;
	let seen: Vec<boolean> = [false, false, false, false];
	for (const triangle of triangles.value) {
		seen[triangle.a] = true; seen[triangle.b] = true; seen[triangle.c] = true;
	}
	assert seen[0] && seen[1] && seen[2] && seen[3];
}

test "animationBlendSpace refuses too few, degenerate, duplicate and unmappable points" {
	const two = AnimationBlendSpace2D.create(targets(), [points(true)[0], points(true)[1]]);
	assert !two.ok;
	if (!two.ok) { assert two.error == AnimationBlendSpaceError.PointCount; }
	assert !triangulate([0.0, 1.0], [0.0, 1.0]).ok;
	let line = points(true);
	line[0].x = 0.0; line[0].y = 0.0; line[1].x = 1.0; line[1].y = 1.0; line[2].x = 2.0; line[2].y = 2.0;
	const flat = AnimationBlendSpace2D.create(targets(), line);
	assert !flat.ok;
	if (!flat.ok) { assert flat.error == AnimationBlendSpaceError.Degenerate; }
	let row = points(true);
	row[2].y = 0.0;
	const axis = AnimationBlendSpace2D.create(targets(), row);
	assert !axis.ok;
	if (!axis.ok) { assert axis.error == AnimationBlendSpaceError.Degenerate; }
	let same = points(true);
	same[2].x = same[1].x; same[2].y = same[1].y;
	const duplicate = AnimationBlendSpace2D.create(targets(), same);
	assert !duplicate.ok;
	if (!duplicate.ok) { assert duplicate.error == AnimationBlendSpaceError.Degenerate; }
	let nan = points(true);
	nan[0].x = NaN as float64;
	assert !AnimationBlendSpace2D.create(targets(), nan).ok;
	const noNode = AnimationBlendSpace2D.create([], points(true));
	assert !noNode.ok;
	if (!noNode.ok) { assert noNode.error == AnimationBlendSpaceError.Target; }
	let space = fixture(true);
	assert !setBlendSpacePosition(space, NaN as float64, 0.0).ok;
	assert !advanceBlendSpace(space, -1.0).ok && !advanceBlendSpace(space, NaN as float64).ok;
}
