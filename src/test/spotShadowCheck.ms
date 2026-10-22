import { Vec3, Quat, Mat4, vec3, axisAngle, identityQuat } from "../math/math3d";
import { Texture2d, Vec3f, Vec4f, mat4x4f, vec3f, vec4f } from "../shader/std";
import {
	Scene3D,
	NodeId3D,
	LightKind,
	LightInstance,
	LightShape,
	LightError,
	addLightNode,
	collectLights,
	closeScene,
} from "../void3d/scene";
import { DrawContext, DrawItem } from "../void3d/draw";
import {
	LIGHT_UNIFORM_LENGTH,
	LIGHT_SHAPE_BASE,
	LIGHT_SHAPE_ARRAY_LENGTH,
	MAX_POINT_LIGHTS,
	VERTEX_UNIFORM_LENGTH,
} from "../void3d/gpu3d";
import { CameraView } from "../void3d/camera";
import {
	SpotShadowError,
	shadowedSpotCount,
	firstShadowedSpot,
	spotShadowView,
	sunIsLit,
} from "../void3d/spotShadow";
import { DirShadowMap, ShadowError, DIR_SHADOW_UNIFORM_LENGTH } from "../void3d/dirShadowMap";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	beginFrame,
	attachShadow,
} from "../void3d/renderer";
import {
	LitBindings,
	dirShadowAt,
	litFs,
	mapShadowAt,
	slotShadowAt,
} from "../void3d/shader3d";

const NO_SHAPE: LightShape = {
	angle: 0.0, verticalAngle: 0.0, falloff: 0.0, width: 0.0, height: 0.0, length: 0.0,
	capsuleRadius: 0.0,
};
const RIGHT_ANGLE: float32 = 1.5707963268;
const UNIT: Vec3 = vec3(1, 1, 1);
const DOWN: Quat = axisAngle(vec3(1, 0, 0), RIGHT_ANGLE);

function near(a: float32, b: float32, tolerance: float32 = 1e-4): boolean {
	return Math.abs(a - b) <= tolerance;
}

function block(): Vec<float32> {
	let values: Vec<float32> = [];
	for (let i = 0; i < LIGHT_UNIFORM_LENGTH; i++) { values.push(0); }
	return move values;
}

function spotOf(range: float32, shadows: boolean): LightInstance {
	return {
		kind: LightKind.Spot, color: vec3(1, 1, 1), radius: range, power: 1, priority: 0,
		shape: { ...NO_SHAPE, angle: RIGHT_ANGLE }, shadows: shadows,
	};
}

function otherOf(kind: LightKind, shadows: boolean): LightInstance {
	const shape: LightShape = {
		...NO_SHAPE, angle: 1.0, verticalAngle: 1.0, width: 1.0, height: 1.0, length: 1.0,
		capsuleRadius: 0.2,
	};
	return {
		kind: kind, color: vec3(1, 1, 1), radius: 8, power: 1, priority: 0, shape: shape,
		shadows: shadows,
	};
}

function place(scene: Scene3D, light: LightInstance, position: Vec3, rotation: Quat): NodeId3D {
	return addLightNode(scene, scene.rootId(),
		{ position: position, rotation: rotation, scale: UNIT }, light);
}

function errorOf(result: Result<int32, LightError>): LightError | null {
	return result.ok ? null : result.error;
}

function downSpot(shadows: boolean): Vec<float32> {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	place(scene, spotOf(8, shadows), vec3(0, 4, 0), DOWN);
	let values = block();
	if (errorOf(collectLights(scene, values)) !== null) { unreachable; }
	return move values;
}

function viewOf(values: Vec<float32>): CameraView {
	const view: Result<CameraView, SpotShadowError> = spotShadowView(values, 0);
	if (!view.ok) { unreachable; }
	return view.value;
}

function clipOf(m: Mat4, p: Vec3): Vec4f {
	return vec4f(
		p.x * m.m11 + p.y * m.m21 + p.z * m.m31 + m.m41,
		p.x * m.m12 + p.y * m.m22 + p.z * m.m32 + m.m42,
		p.x * m.m13 + p.y * m.m23 + p.z * m.m33 + m.m43,
		p.x * m.m14 + p.y * m.m24 + p.z * m.m34 + m.m44,
	);
}

test "a spot shadow's camera takes near range/20, far range and the full angle as fovY" {
	const values: Vec<float32> = downSpot(true);
	assert near(values[LIGHT_SHAPE_BASE + 1], -1.0);
	const m: Mat4 = viewOf(values).viewProj;
	const nearest: Vec4f = clipOf(m, vec3(0, 4.0 - 0.4, 0));
	assert near(nearest.z / nearest.w, 0.0, 1e-5) && near(nearest.w, 0.4);
	const farthest: Vec4f = clipOf(m, vec3(0, 4.0 - 8.0, 0));
	assert near(farthest.z / farthest.w, 1.0, 1e-5) && near(farthest.w, 8.0);
	const mid: Vec4f = clipOf(m, vec3(0, 2.0, 0));
	assert near(mid.z / mid.w, 8.0 * (2.0 - 0.4) / ((8.0 - 0.4) * 2.0), 1e-5);
	assert near(mid.x / mid.w, 0.0) && near(mid.y / mid.w, 0.0);
	const edge: Vec4f = clipOf(m, vec3(0, 2.0, 2.0));
	const radial: float32 = Math.sqrt((edge.x * edge.x + edge.y * edge.y) as float64) as float32;
	assert near(radial / edge.w, 1.0, 1e-5);
}

test "the shadowing spot is the slot that carries the flag, with its full angle beside the cone" {
	const lit: Vec<float32> = downSpot(true);
	assert shadowedSpotCount(lit) == 1 && firstShadowedSpot(lit) == 0;
	assert lit[LIGHT_SHAPE_BASE + LIGHT_SHAPE_ARRAY_LENGTH + 2] == 1.0;
	assert near(lit[LIGHT_SHAPE_BASE + LIGHT_SHAPE_ARRAY_LENGTH + 3], RIGHT_ANGLE);
	const plain: Vec<float32> = downSpot(false);
	assert shadowedSpotCount(plain) == 0 && firstShadowedSpot(plain) == -1;
	assert plain[LIGHT_SHAPE_BASE + LIGHT_SHAPE_ARRAY_LENGTH + 2] == 0.0;
	assert !sunIsLit(lit);
}

test "a rectangle's right axis in the cone slot's third float is not a shadow flag" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	place(scene, otherOf(LightKind.Rectangle, false), vec3(0, 3, 0), axisAngle(vec3(0, 1, 0), 0.7));
	let values = block();
	assert errorOf(collectLights(scene, values)) === null;
	assert values[LIGHT_SHAPE_BASE + LIGHT_SHAPE_ARRAY_LENGTH + 2] != 0.0;
	assert shadowedSpotCount(values) == 0 && firstShadowedSpot(values) == -1;
}

test "a spot slot that cannot make a camera is a named error, not a guess" {
	let values: Vec<float32> = downSpot(true);
	values[12 + MAX_POINT_LIGHTS * 4 + 3] = 0.0;
	const view: Result<CameraView, SpotShadowError> = spotShadowView(values, 0);
	assert !view.ok && view.error == SpotShadowError.BadSpot;
}

test "two shadowing spots, or a shadowed point, rectangle, capsule or sun, are refused by name" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	place(scene, spotOf(8, true), vec3(0, 4, 0), DOWN);
	place(scene, spotOf(8, false), vec3(1, 4, 0), DOWN);
	let values = block();
	assert errorOf(collectLights(scene, values)) === null;
	place(scene, spotOf(8, true), vec3(2, 4, 0), DOWN);
	assert errorOf(collectLights(scene, values)) == LightError.TooManyShadowedSpots;
	const kinds: Vec<LightKind> =
		[LightKind.Point, LightKind.Rectangle, LightKind.Capsule, LightKind.Directional];
	for (const kind of kinds) {
		const other = Scene3D.create(DrawContext.withUniformCapacity(0));
		defer closeScene(other);
		place(other, otherOf(kind, true), vec3(0, 3, 0), identityQuat());
		let again = block();
		assert errorOf(collectLights(other, again)) == LightError.UnshadowableLight;
	}
}

function slotOf(values: Vec<float32>, base: int32): Vec4f {
	return vec4f(values[base], values[base + 1], values[base + 2], values[base + 3]);
}

function depthTexture(depth: float32): Texture2d {
	return { width: 1, height: 1, texels: [depth, depth, depth, depth] };
}

function spotLights(values: Vec<float32>): LitBindings {
	const colour: int32 = 12 + MAX_POINT_LIGHTS * 4;
	const none: Vec4f = vec4f(0.0, 0.0, 0.0, 0.0);
	return {
		pbrMaterialParams: {
			material: vec4f(0.0, 0.0, 0.0, 0.5),
			pbr: vec4f(0.0, 0.7, 1.0, 0.0),
		},
		materialParams: { material: vec4f(0.0, 0.0, 0.0, 0.5) },
		lightParams: {
			ambient: vec4f(0.0, 0.0, 0.0, 1.0),
			dirLight: none,
			dirColor: none,
			pointLight: [slotOf(values, 12), none, none, none],
			pointColor: [slotOf(values, colour), none, none, none],
			shapeA: [slotOf(values, LIGHT_SHAPE_BASE), none, none, none],
			shapeB: [slotOf(values, LIGHT_SHAPE_BASE + LIGHT_SHAPE_ARRAY_LENGTH), none, none, none],
			shapeC: [none, none, none, none],
			shapeD: [none, none, none, none],
		},
		frameParams: {
			frame: vec4f(0.0, 1.0, 0.0, 0.0),
			cameraPosition: vec4f(0.0, 5.0, 1.0, 1.0),
		},
		shadowParams: { shadowMatrix: mat4x4f(none, none, none, none), shadow: none },
		shadowMap: depthTexture(1.0),
		shadowSampler: { nearest: true },
		baseTexture: depthTexture(1.0),
		baseSampler: { nearest: true },
		backTexture: depthTexture(1.0),
		dissolveTexture: depthTexture(1.0),
		dissolveSampler: { nearest: true },
		emissiveTexture: depthTexture(1.0),
		normalTexture: depthTexture(1.0),
		metalRoughTexture: depthTexture(1.0),
		occlusionTexture: depthTexture(1.0),
	};
}

function shadowed(
	b: LitBindings, view: CameraView, depth: float32, bias: float32, opacity: float32, kind: float32,
): LitBindings {
	const map: Mat4 = {
		m11: 0.5, m12: 0.0, m13: 0.0, m14: 0.0,
		m21: 0.0, m22: -0.5, m23: 0.0, m24: 0.0,
		m31: 0.0, m32: 0.0, m33: 1.0, m34: 0.0,
		m41: 0.5, m42: 0.5, m43: 0.0, m44: 1.0,
	};
	const both: Mat4 = view.viewProj * map;
	return {
		...b,
		shadowParams: {
			shadowMatrix: mat4x4f(
				vec4f(both.m11, both.m12, both.m13, both.m14),
				vec4f(both.m21, both.m22, both.m23, both.m24),
				vec4f(both.m31, both.m32, both.m33, both.m34),
				vec4f(both.m41, both.m42, both.m43, both.m44),
			),
			shadow: vec4f(bias, opacity, kind, 0.0),
		},
		shadowMap: depthTexture(depth),
	};
}

function depthAt(distance: float32): float32 {
	return 8.0 * (distance - 0.4) / ((8.0 - 0.4) * distance);
}

test "the lookup divides by w and compares the map as SpotShadow's sampleShadow does" {
	const view: CameraView = viewOf(downSpot(true));
	const base: LitBindings = spotLights(downSpot(true));
	const under: Vec3f = vec3f(0.0, 2.0, 0.0);
	const z: float32 = depthAt(2.0);
	assert near(z, 0.8421053);
	assert mapShadowAt(under, shadowed(base, view, 0.5, 0.0, 1.0, 1.0)) == 0.0;
	assert mapShadowAt(under, shadowed(base, view, 0.95, 0.0, 1.0, 1.0)) == 1.0;
	assert mapShadowAt(under, shadowed(base, view, z - 0.001, 0.0, 1.0, 1.0)) == 0.0;
	assert mapShadowAt(under, shadowed(base, view, z - 0.001, 0.01, 1.0, 1.0)) == 1.0;
	assert near(mapShadowAt(under, shadowed(base, view, 0.5, 0.0, 0.25, 1.0)), 0.75);
	const outside: Vec3f = vec3f(5.0, 2.0, 0.0);
	assert mapShadowAt(outside, shadowed(base, view, 0.0, 0.0, 1.0, 1.0)) == 1.0;
	const behind: Vec3f = vec3f(0.0, 6.0, 0.0);
	assert mapShadowAt(behind, shadowed(base, view, 0.0, 0.0, 1.0, 1.0)) == 1.0;
}

test "only the flagged spot slot of a spot frame reads the map, and only in a shadowed program" {
	const view: CameraView = viewOf(downSpot(true));
	const blocked: LitBindings = shadowed(spotLights(downSpot(true)), view, 0.0, 0.0, 1.0, 1.0);
	const under: Vec3f = vec3f(0.0, 2.0, 0.0);
	assert slotShadowAt(under, blocked, { shadowed: true }, 0) == 0.0;
	assert slotShadowAt(under, blocked, { shadowed: false }, 0) == 1.0;
	const sunFrame: LitBindings = shadowed(spotLights(downSpot(true)), view, 0.0, 0.0, 1.0, 0.0);
	assert slotShadowAt(under, sunFrame, { shadowed: true }, 0) == 1.0;
	const unflagged: LitBindings = shadowed(spotLights(downSpot(false)), view, 0.0, 0.0, 1.0, 1.0);
	assert slotShadowAt(under, unflagged, { shadowed: true }, 0) == 1.0;
	const none: Vec4f = vec4f(0.0, 0.0, 0.0, 0.0);
	const point: LitBindings = {
		...blocked,
		lightParams: { ...blocked.lightParams, shapeA: [none, none, none, none] },
	};
	assert slotShadowAt(under, point, { shadowed: true }, 0) == 1.0;
}

test "the sun's lookup is unchanged in a sun frame and steps aside in a spot frame" {
	const identityMap = mat4x4f(
		vec4f(1.0, 0.0, 0.0, 0.0), vec4f(0.0, 1.0, 0.0, 0.0),
		vec4f(0.0, 0.0, 1.0, 0.0), vec4f(0.0, 0.0, 0.0, 1.0),
	);
	const base: LitBindings = spotLights(downSpot(false));
	const sun: LitBindings = {
		...base,
		shadowParams: { shadowMatrix: identityMap, shadow: vec4f(0.0, 1.0, 0.0, 0.0) },
		shadowMap: depthTexture(0.5),
	};
	assert dirShadowAt(vec3f(0.5, 0.5, 0.9), sun) == 0.0;
	assert dirShadowAt(vec3f(0.5, 0.5, 0.3), sun) == 1.0;
	const spot: LitBindings = {
		...sun,
		shadowParams: { shadowMatrix: identityMap, shadow: vec4f(0.0, 1.0, 1.0, 0.0) },
	};
	assert dirShadowAt(vec3f(0.5, 0.5, 0.9), spot) == 1.0;
}

function surface(b: LitBindings, pbr: boolean): Vec3f {
	return litFs({
		worldPosition: vec3f(0.0, 0.0, 0.0),
		worldNormal: vec3f(0.0, 1.0, 0.0),
		baseColor: vec4f(1.0, 1.0, 1.0, 1.0),
		frontFacing: true,
	}, b, { pbr: pbr, shadowed: true }).color.rgb;
}

test "a surface under the shadowing spot is dark where the map blocks it, lit where it does not" {
	const view: CameraView = viewOf(downSpot(true));
	const base: LitBindings = spotLights(downSpot(true));
	const floorZ: float32 = depthAt(4.0);
	const modes: Vec<boolean> = [false, true];
	for (const pbr of modes) {
		const open: Vec3f = surface(shadowed(base, view, 1.0, 0.0, 1.0, 1.0), pbr);
		const blocked: Vec3f = surface(shadowed(base, view, floorZ - 0.05, 0.0, 1.0, 1.0), pbr);
		const sunFrame: Vec3f = surface(shadowed(base, view, floorZ - 0.05, 0.0, 1.0, 0.0), pbr);
		assert open.x > 0.0 && blocked.x == 0.0;
		assert near(sunFrame.x, open.x, 1e-6);
	}
}

function refusalOf(lights: Vec<float32>, map: boolean): RendererError | null {
	let context: DrawContext = DrawContext.withUniformCapacity(
		RENDERER_UNIFORM_LENGTH + DIR_SHADOW_UNIFORM_LENGTH,
	);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	const made: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 64);
	if (!created.ok || !made.ok) { unreachable; }
	let core: Renderer = created.value;
	if (map) { attachShadow(core, made.value); }
	const items: Vec<DrawItem> = [];
	const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	const began: Result<boolean, RendererError> = beginFrame(core, items, camera, lights);
	return began.ok ? null : began.error;
}

test "a frame with two shadowing spot slots is refused before it writes" {
	let lights: Vec<float32> = downSpot(true);
	lights[LIGHT_SHAPE_BASE + 4 + 3] = 1.0;
	lights[LIGHT_SHAPE_BASE + LIGHT_SHAPE_ARRAY_LENGTH + 4 + 2] = 1.0;
	assert shadowedSpotCount(lights) == 2;
	assert refusalOf(lights, true) == RendererError.TooManyShadowedSpots;
	assert refusalOf(lights, false) == RendererError.TooManyShadowedSpots;
}

test "a shadowing spot and a lit sun cannot share the one map" {
	let lights: Vec<float32> = downSpot(true);
	lights[7] = 1.0;
	assert sunIsLit(lights);
	assert refusalOf(lights, true) == RendererError.SpotShadowSharesSunMap;
}

test "a shadowing spot with no range is refused by the frame, not drawn from a broken camera" {
	let lights: Vec<float32> = downSpot(true);
	lights[12 + MAX_POINT_LIGHTS * 4 + 3] = 0.0;
	assert refusalOf(lights, true) == RendererError.BadShadowSpot;
}
