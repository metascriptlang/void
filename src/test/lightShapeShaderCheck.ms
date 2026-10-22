// The lit programs' spot, rectangle and capsule slots run on the CPU: shader3d.ms's samplers held
// to hand values worked from pbr/Light.hx on float64, to lightShape.ms (the CPU oracle of the
// same representative points), and a point slot held bit-identical with the shape arrays zero.

import { Vec3, vec3 } from "../math/math3d";
import { Texture2d, Vec3f, Vec4f, mat4x4f, vec3f, vec4f } from "../shader/std";
import {
	SpotLightShape,
	RectangleLightShape,
	CapsuleLightShape,
} from "../void3d/lightShape";
import {
	LitBindings,
	capsuleSample,
	capsuleSpecularDir,
	lightAt,
	litFs,
	pbrDirect,
	pbrDirectSpecular,
	pointLightAt,
	rectangleSample,
	rectangleSpecularDir,
	spotSample,
	srgbToLinear,
	linearToSrgb,
} from "../void3d/shader3d";

const QUARTER: float32 = 0.7853981633974483;

function near(a: float32, b: float32, tolerance: float32 = 1e-4): boolean {
	return Math.abs(a - b) <= tolerance;
}

function nearVec(a: Vec3f, x: float32, y: float32, z: float32): boolean {
	return near(a.x, x) && near(a.y, y) && near(a.z, z);
}

function none(): Vec4f {
	return vec4f(0.0, 0.0, 0.0, 0.0);
}

function identity() {
	return mat4x4f(
		vec4f(1.0, 0.0, 0.0, 0.0), vec4f(0.0, 1.0, 0.0, 0.0),
		vec4f(0.0, 0.0, 1.0, 0.0), vec4f(0.0, 0.0, 0.0, 1.0),
	);
}

function texture(): Texture2d {
	return { width: 1, height: 1, texels: [1.0, 1.0, 1.0, 1.0] };
}

// A spot over the origin: at (0, 4, 0) looking down, range 8, a 90 degree cone.
const SPOT_AT: Vec4f = vec4f(0.0, 4.0, 0.0, 1.0);
const SPOT_TINT: Vec4f = vec4f(1.0, 1.0, 1.0, 8.0);
const DOWN: Vec4f = vec4f(0.0, -1.0, 0.0, 1.0);

function spotCone(falloff: float32): Vec4f {
	return vec4f(Math.cos(QUARTER) as float32, Math.cos(Math.min(QUARTER, falloff)) as float32,
		0.0, 0.0);
}

test "a spot light under its apex takes the window alone and points straight up" {
	const sample: Vec4f = spotSample(vec3f(0.0, 0.0, 0.0), SPOT_AT, SPOT_TINT, DOWN, spotCone(0.0));
	assert nearVec(sample.xyz, 0.0, 1.0, 0.0);
	assert near(sample.w, 0.25);
}

test "a spot light's cone ramps from the outer cosine to the inner one" {
	const wide: Vec4f = spotSample(vec3f(2.0, 0.0, 0.0), SPOT_AT, SPOT_TINT, DOWN, spotCone(0.0));
	assert nearVec(wide.xyz, -0.4472136, 0.8944272, 0.0);
	assert near(wide.w, 0.19446601 * 0.63955188);
	const soft: Vec4f = spotSample(vec3f(2.0, 0.0, 0.0), SPOT_AT, SPOT_TINT, DOWN,
		spotCone(0.3490658504));
	assert near(soft.w, 0.19446601 * 0.80538183);
}

test "a spot light lights nothing outside its cone or past its range" {
	const outside: Vec4f = spotSample(vec3f(5.0, 0.0, 0.0), SPOT_AT, SPOT_TINT, DOWN, spotCone(0.0));
	assert outside.w == 0.0;
	const far: Vec4f = spotSample(vec3f(0.0, -4.5, 0.0), SPOT_AT, SPOT_TINT, DOWN, spotCone(0.0));
	assert far.w == 0.0;
	const on: Vec4f = spotSample(vec3f(0.0, 4.0, 0.0), SPOT_AT, SPOT_TINT, DOWN, spotCone(0.0));
	assert on.w == 0.0;
}

test "a spot light agrees with lightShape.ms on its cone weight" {
	const shape: SpotLightShape = {
		position: vec3(0.0, 4.0, 0.0), forward: vec3(0.0, -1.0, 0.0), range: 8.0,
		cone: { fullAngleRadians: 1.5707963268, falloffRadians: 0.3490658504 },
	};
	const weight = shape.angularWeight(vec3(2.0, 0.0, 0.0));
	assert weight.ok;
	const sample: Vec4f = spotSample(vec3f(2.0, 0.0, 0.0), SPOT_AT, SPOT_TINT, DOWN,
		spotCone(0.3490658504));
	assert near(sample.w, 0.19446601 * weight.value);
}

// A rectangle at (0, 3, 0) facing down: half width 1 along x, half height 0.5 along z, a 90
// degree horizontal and a 60 degree vertical cone, range 10.
const RECT_AT: Vec4f = vec4f(0.0, 3.0, 0.0, 1.0);
const RECT_TINT: Vec4f = vec4f(1.0, 1.0, 1.0, 10.0);
const RECT_A: Vec4f = vec4f(0.0, -1.0, 0.0, 2.0);
const RECT_B: Vec4f = vec4f(1.0, 0.0, 0.0, 1.0);
const RECT_C: Vec4f = vec4f(0.0, 0.0, 1.0, 0.5);
const RECT_D: Vec4f = vec4f(0.70710678, 1.0, 0.8660254, 1.0);
const RAISED: Vec3f = vec3f(0.0, 1.0, 0.0);

function rectangleAt(position: Vec3f): Vec4f {
	return rectangleSample(position, RAISED, RECT_AT, RECT_TINT, RECT_A, RECT_B, RECT_C, RECT_D);
}

test "a rectangle light over its footprint is lit from straight above" {
	const sample: Vec4f = rectangleAt(vec3f(0.5, 0.0, 0.2));
	assert nearVec(sample.xyz, 0.0, 1.0, 0.0);
	assert near(sample.w, 0.48994670);
}

test "a rectangle light clamps the plane point to its half sizes and narrows by the cone" {
	const sample: Vec4f = rectangleAt(vec3f(3.0, 0.0, 0.0));
	assert nearVec(sample.xyz, -0.5547002, 0.8320503, 0.0);
	assert near(sample.w, 0.17440678);
}

test "a rectangle light agrees with lightShape.ms on point and cone weight" {
	const shape: RectangleLightShape = {
		position: vec3(0.0, 3.0, 0.0), forward: vec3(0.0, -1.0, 0.0), right: vec3(1.0, 0.0, 0.0),
		up: vec3(0.0, 0.0, 1.0), halfWidth: 1.0, halfHeight: 0.5,
		horizontal: { fullAngleRadians: 1.5707963268, falloffRadians: 0.0 },
		vertical: { fullAngleRadians: 1.0471975512, falloffRadians: 0.0 },
		range: 10.0,
	};
	const point = shape.diffusePoint(vec3(3.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0));
	assert point.ok;
	const weight = shape.angularWeight(point.value.delta);
	assert weight.ok;
	const sample: Vec4f = rectangleAt(vec3f(3.0, 0.0, 0.0));
	assert nearVec(sample.xyz, point.value.direction.x, point.value.direction.y,
		point.value.direction.z);
	const window = 1.0 - point.value.delta.length() / 10.0;
	assert near(sample.w, window * window * weight.value);
}

test "a rectangle light's specular direction traces the reflected ray to the plane" {
	const reflected: Vec3f = vec3f(0.70710678, 0.70710678, 0.0);
	const direction: Vec3f = rectangleSpecularDir(vec3f(0.0, 0.0, 0.0), reflected, RAISED,
		RECT_AT, RECT_A, RECT_B, RECT_C);
	assert nearVec(direction, 0.3162278, 0.9486833, 0.0);
}

test "a rectangle seen edge on, and a ray in its plane, divide nothing by zero" {
	const edge: Vec4f = rectangleSample(vec3f(0.0, 0.0, 0.0), vec3f(1.0, 0.0, 0.0), RECT_AT,
		RECT_TINT, vec4f(1.0, 0.0, 0.0, 2.0), RECT_B, RECT_C, RECT_D);
	assert edge.w == 0.0;
	const kept: Vec3f = rectangleSpecularDir(vec3f(0.0, 0.0, 0.0), vec3f(1.0, 0.0, 0.0), RAISED,
		RECT_AT, vec4f(1.0, 0.0, 0.0, 2.0), RECT_B, RECT_C);
	assert nearVec(kept, 0.0, 1.0, 0.0);
}

// A capsule at (0, 2, 0) along x: half length 1, radius 0.5, range 6.
const CAPSULE_AT: Vec4f = vec4f(0.0, 2.0, 0.0, 1.0);
const CAPSULE_TINT: Vec4f = vec4f(1.0, 1.0, 1.0, 6.0);
const CAPSULE_A: Vec4f = vec4f(1.0, 0.0, 0.0, 3.0);
const CAPSULE_B: Vec4f = vec4f(1.0, 0.5, 0.0, 0.0);

test "a capsule light stands at the closest point of its segment" {
	const middle: Vec4f = capsuleSample(vec3f(0.0, 0.0, 0.0), CAPSULE_AT, CAPSULE_TINT, CAPSULE_A,
		CAPSULE_B);
	assert nearVec(middle.xyz, 0.0, 1.0, 0.0);
	assert near(middle.w, 0.44444444);
	const end: Vec4f = capsuleSample(vec3f(3.0, 0.0, 0.0), CAPSULE_AT, CAPSULE_TINT, CAPSULE_A,
		CAPSULE_B);
	assert nearVec(end.xyz, -0.7071068, 0.7071068, 0.0);
	assert near(end.w, 0.27941318);
}

test "a capsule light agrees with lightShape.ms on its diffuse point and specular direction" {
	const shape: CapsuleLightShape = {
		position: vec3(0.0, 2.0, 0.0), axis: vec3(1.0, 0.0, 0.0), halfLength: 1.0, radius: 0.5,
		range: 6.0,
	};
	const point = shape.diffusePoint(vec3(3.0, 0.0, 0.0));
	assert point.ok;
	const sample: Vec4f = capsuleSample(vec3f(3.0, 0.0, 0.0), CAPSULE_AT, CAPSULE_TINT, CAPSULE_A,
		CAPSULE_B);
	assert nearVec(sample.xyz, point.value.direction.x, point.value.direction.y,
		point.value.direction.z);
	const reflected: Vec3 = vec3(0.5, 1.0, 0.3).normalized();
	const heaps = shape.specularDirection(vec3(0.0, 0.0, 0.0), reflected);
	assert heaps.ok;
	const direction: Vec3f = capsuleSpecularDir(vec3f(0.0, 0.0, 0.0),
		vec3f(reflected.x, reflected.y, reflected.z), vec3f(0.0, 1.0, 0.0), CAPSULE_AT, CAPSULE_A,
		CAPSULE_B);
	assert nearVec(direction, heaps.value.x, heaps.value.y, heaps.value.z);
	assert nearVec(direction, 0.43166736, 0.87343376, 0.22533698);
}

test "a capsule light's radius widens the specular point and zero radius keeps the line point" {
	const reflected: Vec3 = vec3(0.5, 1.0, 0.3).normalized();
	const ray: Vec3f = vec3f(reflected.x, reflected.y, reflected.z);
	const wide: Vec3f = capsuleSpecularDir(vec3f(0.0, 0.0, 0.0), ray, vec3f(0.0, 1.0, 0.0),
		CAPSULE_AT, CAPSULE_A, CAPSULE_B);
	const thin: Vec3f = capsuleSpecularDir(vec3f(0.0, 0.0, 0.0), ray, vec3f(0.0, 1.0, 0.0),
		CAPSULE_AT, CAPSULE_A, vec4f(1.0, 0.0, 0.0, 0.0));
	assert !nearVec(wide, thin.x, thin.y, thin.z);
	const through: Vec3f = capsuleSpecularDir(vec3f(0.0, 0.0, 0.0), vec3f(0.0, 1.0, 0.0),
		vec3f(0.0, 1.0, 0.0), CAPSULE_AT, CAPSULE_A, CAPSULE_B);
	assert nearVec(through, 0.0, 1.0, 0.0);
	const along: Vec3f = capsuleSpecularDir(vec3f(0.0, 2.0, 0.0), vec3f(1.0, 0.0, 0.0),
		vec3f(0.0, 0.0, 1.0), CAPSULE_AT, CAPSULE_A, CAPSULE_B);
	assert nearVec(along, 0.0, 0.0, 1.0);
}

test "a point slot is pointLightAt untouched with the shape arrays zero" {
	const position: Vec3f = vec3f(1.0, 0.5, -0.5);
	const normal: Vec3f = vec3f(0.0, 1.0, 0.0);
	const at: Vec4f = vec4f(0.5, 3.0, 0.25, 1.5);
	const tint: Vec4f = vec4f(0.9, 0.6, 0.3, 7.0);
	const shaped: Vec3f = lightAt(position, normal, at, tint, none(), none(), none(), none());
	const plain: Vec3f = pointLightAt(position, normal, at, tint);
	assert shaped.x == plain.x && shaped.y == plain.y && shaped.z == plain.z;
	assert plain.x > 0.0;
}

test "pbrDirectSpecular with one direction twice is pbrDirect to the bit" {
	const albedo: Vec3f = vec3f(0.8, 0.2, 0.05);
	const view: Vec3f = vec3f(0.3, 0.2, 0.9);
	const light: Vec3f = vec3f(0.5, -0.1, 0.8);
	const radiance: Vec3f = vec3f(2.0, 0.5, 1.5);
	const normal: Vec3f = vec3f(0.0, 0.0, 1.0);
	const direct: Vec3f = pbrDirect(albedo, 0.2, 0.6, normal, view, light, radiance, 1.0, 0.0, 1.0);
	const twice: Vec3f = pbrDirectSpecular(albedo, 0.2, 0.6, normal, view, light, light, radiance,
		1.0, 0.0, 1.0);
	assert direct.x == twice.x && direct.y == twice.y && direct.z == twice.z;
}

test "the specular direction moves the highlight and leaves n.l alone" {
	const albedo: Vec3f = vec3f(0.8, 0.2, 0.05);
	const normal: Vec3f = vec3f(0.0, 0.0, 1.0);
	const view: Vec3f = vec3f(0.0, 0.6, 0.8);
	const light: Vec3f = vec3f(0.0, -0.6, 0.8);
	const radiance: Vec3f = vec3f(1.0, 1.0, 1.0);
	const mirror: Vec3f = vec3f(0.0, -0.6, 0.8);
	const moved: Vec3f = vec3f(0.0, 0.6, 0.8);
	const peak: Vec3f = pbrDirectSpecular(albedo, 0.0, 0.2, normal, view, light, mirror, radiance,
		1.0, 0.0, 1.0);
	const off: Vec3f = pbrDirectSpecular(albedo, 0.0, 0.2, normal, view, light, moved, radiance,
		1.0, 0.0, 1.0);
	assert peak.x > off.x * 1.5;
	const blind: Vec3f = pbrDirectSpecular(albedo, 0.0, 0.2, normal, view, vec3f(0.0, 0.0, -1.0),
		moved, radiance, 1.0, 0.0, 1.0);
	assert blind.x == 0.0;
}

function bindingsWith(
	at: Vec4f, tint: Vec4f, a: Vec4f, b: Vec4f, c: Vec4f, d: Vec4f,
): LitBindings {
	return {
		pbrMaterialParams: {
			material: vec4f(0.0, 0.0, 0.0, 0.5),
			pbr: vec4f(0.0, 0.7, 1.0, 0.0),
		},
		materialParams: { material: vec4f(0.0, 0.0, 0.0, 0.5) },
		lightParams: {
			ambient: vec4f(0.0, 0.0, 0.0, 1.0),
			dirLight: none(),
			dirColor: none(),
			pointLight: [at, none(), none(), none()],
			pointColor: [tint, none(), none(), none()],
			shapeA: [a, none(), none(), none()],
			shapeB: [b, none(), none(), none()],
			shapeC: [c, none(), none(), none()],
			shapeD: [d, none(), none(), none()],
		},
		frameParams: {
			frame: vec4f(0.0, 1.0, 0.0, 0.0),
			cameraPosition: vec4f(0.0, 5.0, 1.0, 1.0),
		},
		shadowParams: { shadowMatrix: identity(), shadow: vec4f(0.0, 1.0, 0.0, 0.0) },
		shadowMap: texture(),
		shadowSampler: { nearest: true },
		baseTexture: texture(),
		baseSampler: { nearest: true },
		backTexture: texture(),
		dissolveTexture: texture(),
		dissolveSampler: { nearest: true },
		emissiveTexture: texture(),
		normalTexture: texture(),
		metalRoughTexture: texture(),
		occlusionTexture: texture(),
	};
}

function surfaceColor(b: LitBindings, pbr: boolean): Vec3f {
	return litFs({
		worldPosition: vec3f(0.0, 0.0, 0.0),
		worldNormal: vec3f(0.0, 1.0, 0.0),
		baseColor: vec4f(1.0, 1.0, 1.0, 1.0),
		frontFacing: true,
	}, b, { pbr: pbr }).color.rgb;
}

test "a legacy lit surface under a spot takes tint times window times cone times n.l times power" {
	const lit: LitBindings = bindingsWith(vec4f(0.0, 4.0, 0.0, 2.0), SPOT_TINT, DOWN, spotCone(0.0),
		none(), none());
	const expected: float32 = 0.25 * 1.0 * 2.0;
	assert near(surfaceColor(lit, false).x, linearToSrgb(vec3f(expected, expected, expected)).x);
}

test "a pbr surface under a spot takes the direct brdf with the cone in its radiance" {
	const lit: LitBindings = bindingsWith(vec4f(0.0, 4.0, 0.0, 2.0), SPOT_TINT, DOWN, spotCone(0.0),
		none(), none());
	const radiance: float32 = 0.25 * 2.0;
	const direct: Vec3f = pbrDirect(vec3f(1.0, 1.0, 1.0), 0.0, 0.7, vec3f(0.0, 1.0, 0.0),
		vec3f(0.0, 5.0, 1.0), vec3f(0.0, 4.0, 0.0), vec3f(radiance, radiance, radiance), 1.0, 0.0,
		1.0);
	assert near(surfaceColor(lit, true).x, linearToSrgb(direct).x);
	const outside: LitBindings = bindingsWith(vec4f(3.0, 1.0, 0.0, 2.0), SPOT_TINT, DOWN,
		spotCone(0.0), none(), none());
	assert surfaceColor(outside, true).x == 0.0;
	assert surfaceColor(outside, false).x == 0.0;
}

test "a pbr surface under a capsule light takes its highlight from the radius-widened point" {
	const lit: LitBindings = bindingsWith(CAPSULE_AT, CAPSULE_TINT, CAPSULE_A, CAPSULE_B, none(),
		none());
	const dull: LitBindings = bindingsWith(CAPSULE_AT, CAPSULE_TINT, CAPSULE_A,
		vec4f(1.0, 0.0, 0.0, 0.0), none(), none());
	assert surfaceColor(lit, true).x > surfaceColor(dull, true).x;
	assert surfaceColor(dull, true).x > 0.0;
	assert surfaceColor(lit, false).x > 0.0;
}

test "linear light of a shaped slot uses the tint's sRGB decode like a point slot" {
	const tint: Vec4f = vec4f(0.5, 0.5, 0.5, 8.0);
	const sample: Vec4f = spotSample(vec3f(0.0, 0.0, 0.0), SPOT_AT, tint, DOWN, spotCone(0.0));
	const lit: Vec3f = lightAt(vec3f(0.0, 0.0, 0.0), vec3f(0.0, 1.0, 0.0), SPOT_AT, tint, DOWN,
		spotCone(0.0), none(), none());
	assert near(lit.x, srgbToLinear(vec3f(0.5, 0.5, 0.5)).x * sample.w);
}
