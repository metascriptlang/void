import {
	Vec3, Quat, Mat4, vec3, axisAngle, identity, identityQuat, translation,
} from "../math/math3d";
import { Texture2d, Vec3f, Vec4f, Mat4x4f, mat4x4f, vec3f, vec4f } from "../shader/std";
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
	SHADOW_CASCADE_FAR,
	SHADOW_CASCADE_INFO,
	SHADOW_CASCADE_FILTER,
	SHADOW_CASCADE_NORMAL_BIAS,
	SHADOW_SPOT_BIAS,
	SHADOW_SPOT_OPACITY,
	SHADOW_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
	LIGHT_RECORD_COLOR,
	LIGHT_RECORD_SHAPE,
	LIGHT_SPOT_CASTER,
	LIGHT_CUBE_CASTER,
	VERTEX_UNIFORM_LENGTH,
} from "../void3d/gpu3d";
import { CameraView } from "../void3d/camera";
import {
	SpotShadowError,
	spotCaster,
	spotShadowView,
} from "../void3d/spotShadow";
import {
	DirShadowMap,
	ShadowError,
	DIR_SHADOW_UNIFORM_LENGTH,
	ShadowKind,
	ShadowSamplingKind,
	SunLayers,
	carryShadows,
} from "../void3d/dirShadowMap";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	beginFrame,
	attachShadow,
	attachSpotShadow,
} from "../void3d/renderer";
import {
	LitBindings,
	dirShadowAt,
	litFs,
	spotShadowAt,
	recordShadowAt,
	litTexelOf,
	LitKey,
} from "../void3d/shader3d";
import { CascadeError, MAX_CASCADES } from "../void3d/cascades";
import { oneLayer, shadowParamsOf } from "./shadowHelpers";
import { SceneLights, recordsOf, sceneLights, withTexel } from "./lightHelpers";

const NO_SHAPE: LightShape = {
	angle: 0.0, verticalAngle: 0.0, falloff: 0.0, width: 0.0, height: 0.0, length: 0.0,
	capsuleRadius: 0.0,
};
const RIGHT_ANGLE: float32 = 1.5707963268;
const SHAPE: int32 = LIGHT_UNIFORM_LENGTH + LIGHT_RECORD_SHAPE;
const CONE: int32 = SHAPE + 4;
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
	assert near(values[SHAPE + 1], -1.0);
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

function casterOf(values: Vec<float32>): int32 {
	const caster: Result<int32, SpotShadowError> = spotCaster(values);
	if (!caster.ok) { unreachable; }
	return caster.value;
}

test "the light block's header names the casting spot, with its full angle beside the cone" {
	const lit: Vec<float32> = downSpot(true);
	assert lit[LIGHT_SPOT_CASTER] == 1.0 && casterOf(lit) == 0;
	assert near(lit[CONE + 3], RIGHT_ANGLE);
	const plain: Vec<float32> = downSpot(false);
	assert plain[LIGHT_SPOT_CASTER] == 0.0 && casterOf(plain) == -1;
}

test "a header that names no spot record of the block is a named error" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	place(scene, otherOf(LightKind.Rectangle, false), vec3(0, 3, 0), axisAngle(vec3(0, 1, 0), 0.7));
	let values = block();
	assert errorOf(collectLights(scene, values)) === null;
	const named: float32[] = [1.0, 2.0, 0.5, -1.0, NaN as float32];
	for (const v of named) {
		values[LIGHT_SPOT_CASTER] = v;
		const caster: Result<int32, SpotShadowError> = spotCaster(values);
		assert !caster.ok && caster.error == SpotShadowError.BadCaster;
	}
}

test "a spot slot that cannot make a camera is a named error, not a guess" {
	let values: Vec<float32> = downSpot(true);
	values[LIGHT_UNIFORM_LENGTH + LIGHT_RECORD_COLOR + 3] = 0.0;
	const view: Result<CameraView, SpotShadowError> = spotShadowView(values, 0);
	assert !view.ok && view.error == SpotShadowError.BadSpot;
}

test "two shadowing spots, or a shadowed sun, are refused by name" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	place(scene, spotOf(8, false), vec3(1, 4, 0), DOWN);
	place(scene, spotOf(8, true), vec3(0, 4, 0), DOWN);
	place(scene, otherOf(LightKind.Capsule, true), vec3(0, 3, 0), identityQuat());
	let values = block();
	assert errorOf(collectLights(scene, values)) === null;
	assert values[LIGHT_SPOT_CASTER] == 2.0 && values[LIGHT_CUBE_CASTER] == 3.0;
	place(scene, spotOf(8, true), vec3(2, 4, 0), DOWN);
	assert errorOf(collectLights(scene, values)) == LightError.TooManyShadowedSpots;
	const other = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(other);
	place(other, otherOf(LightKind.Directional, true), vec3(0, 3, 0), identityQuat());
	let again = block();
	assert errorOf(collectLights(other, again)) == LightError.UnshadowableLight;
}

function depthTexture(depth: float32): Texture2d {
	return { width: 1, height: 1, texels: [depth, depth, depth, depth] };
}

const NO_MAP: Mat4x4f = mat4x4f(
	vec4f(0.0, 0.0, 0.0, 0.0), vec4f(0.0, 0.0, 0.0, 0.0),
	vec4f(0.0, 0.0, 0.0, 0.0), vec4f(0.0, 0.0, 0.0, 0.0),
);
const NONE: Vec4f = vec4f(0.0, 0.0, 0.0, 0.0);

function spotLights(values: Vec<float32>): LitBindings {
	const lights: SceneLights = sceneLights(vec4f(0.0, 0.0, 0.0, values[LIGHT_SPOT_CASTER]), NONE,
		vec4f(0.0, 0.0, 0.0, values[LIGHT_CUBE_CASTER]), recordsOf(values));
	return {
		pbrMaterialParams: {
			material: vec4f(0.0, 0.0, 0.0, 0.5),
			materialColor: vec4f(1.0, 1.0, 1.0, 1.0),
			pbr: vec4f(0.0, 0.7, 1.0, 0.0),
		},
		materialParams: {
			material: vec4f(0.0, 0.0, 0.0, 0.5),
			materialColor: vec4f(1.0, 1.0, 1.0, 1.0),
		},
		lightParams: lights.lightParams,
		lightRecords: lights.lightRecords,
		clusterRecords: lights.clusterRecords,
		clusterIndices: lights.clusterIndices,
		clusterSampler: lights.clusterSampler,
		frameParams: {
			frame: vec4f(0.0, 1.0, 0.0, 0.0),
			cameraPosition: vec4f(0.0, 5.0, 1.0, 1.0),
		},
		shadowParams: {
			cascadeMatrices: [NO_MAP, NO_MAP, NO_MAP, NO_MAP], cascadeFar: NONE,
			cascadeInfo: NONE, cascadeView: NONE, cascadeFilter: NONE, spotMatrix: NO_MAP,
			spotShadow: NONE,
			cubeMatrices: [NO_MAP, NO_MAP, NO_MAP, NO_MAP, NO_MAP, NO_MAP], cubeShadow: NONE,
			cubeLight: NONE,
		},
		shadowMap: oneLayer(depthTexture(1.0)),
		shadowSampler: { nearest: true },
		spotShadowMap: oneLayer(depthTexture(1.0)),
		spotShadowSampler: { nearest: true },
		cubeShadowMap: oneLayer(depthTexture(1.0)),
		baseTexture: depthTexture(1.0),
		baseSampler: { nearest: true },
		backTexture: depthTexture(1.0),
		dissolveTexture: depthTexture(1.0),
		dissolveSampler: { nearest: true },
		emissiveTexture: depthTexture(1.0),
		normalTexture: depthTexture(1.0),
		metalRoughTexture: depthTexture(1.0),
		occlusionTexture: depthTexture(1.0),
		envDiffuse: { size: 0, texels: [] }, envSpecular: { size: 0, texels: [] },
	};
}

function spotMapOf(view: CameraView): Mat4x4f {
	const map: Mat4 = {
		m11: 0.5, m12: 0.0, m13: 0.0, m14: 0.0,
		m21: 0.0, m22: -0.5, m23: 0.0, m24: 0.0,
		m31: 0.0, m32: 0.0, m33: 1.0, m34: 0.0,
		m41: 0.5, m42: 0.5, m43: 0.0, m44: 1.0,
	};
	const both: Mat4 = view.viewProj * map;
	return mat4x4f(
		vec4f(both.m11, both.m12, both.m13, both.m14),
		vec4f(both.m21, both.m22, both.m23, both.m24),
		vec4f(both.m31, both.m32, both.m33, both.m34),
		vec4f(both.m41, both.m42, both.m43, both.m44),
	);
}

function spotMapped(
	b: LitBindings, view: CameraView, depth: float32, bias: float32, opacity: float32,
): LitBindings {
	return {
		...b,
		shadowParams: {
			...b.shadowParams, spotMatrix: spotMapOf(view), spotShadow: vec4f(bias, opacity, 1.0, 0.0),
		},
		spotShadowMap: oneLayer(depthTexture(depth)),
	};
}

const SUN_MAP: Mat4x4f = mat4x4f(
	vec4f(1.0, 0.0, 0.0, 0.0), vec4f(0.0, 1.0, 0.0, 0.0),
	vec4f(0.0, 0.0, 1.0, 0.0), vec4f(0.5, 0.5, 0.9, 1.0),
);

function sunMapped(b: LitBindings, depth: float32, opacity: float32): LitBindings {
	return {
		...b,
		shadowParams: {
			...b.shadowParams,
			cascadeMatrices: [SUN_MAP, SUN_MAP, SUN_MAP, SUN_MAP],
			cascadeFar: vec4f(3.0e38, 0.0, 0.0, 0.0),
			cascadeInfo: vec4f(1.0, 0.0, 0.0, opacity),
			cascadeView: vec4f(0.0, 0.0, 1.0, 1.0),
		},
		shadowMap: oneLayer(depthTexture(depth)),
	};
}

const UP: Vec3f = vec3f(0.0, 1.0, 0.0);

function depthAt(distance: float32): float32 {
	return 8.0 * (distance - 0.4) / ((8.0 - 0.4) * distance);
}

test "the lookup divides by w and compares the map as SpotShadow's sampleShadow does" {
	const view: CameraView = viewOf(downSpot(true));
	const base: LitBindings = spotLights(downSpot(true));
	const under: Vec3f = vec3f(0.0, 2.0, 0.0);
	const z: float32 = depthAt(2.0);
	assert near(z, 0.8421053);
	assert spotShadowAt(under, UP, spotMapped(base, view, 0.5, 0.0, 1.0)) == 0.0;
	assert spotShadowAt(under, UP, spotMapped(base, view, 0.95, 0.0, 1.0)) == 1.0;
	assert spotShadowAt(under, UP, spotMapped(base, view, z - 0.001, 0.0, 1.0)) == 0.0;
	assert spotShadowAt(under, UP, spotMapped(base, view, z - 0.001, 0.01, 1.0)) == 1.0;
	assert near(spotShadowAt(under, UP, spotMapped(base, view, 0.5, 0.0, 0.25)), 0.75);
	const outside: Vec3f = vec3f(5.0, 2.0, 0.0);
	assert spotShadowAt(outside, UP, spotMapped(base, view, 0.0, 0.0, 1.0)) == 1.0;
	const behind: Vec3f = vec3f(0.0, 6.0, 0.0);
	assert spotShadowAt(behind, UP, spotMapped(base, view, 0.0, 0.0, 1.0)) == 1.0;
}

test "a block half nobody wrote shades nothing, whatever its map holds" {
	const base: LitBindings = spotLights(downSpot(true));
	const empty: LitBindings = {
		...base, shadowMap: oneLayer(depthTexture(0.0)),
		spotShadowMap: oneLayer(depthTexture(0.0)),
	};
	assert dirShadowAt(vec3f(0.0, 0.0, 0.0), UP, empty) == 1.0;
	assert spotShadowAt(vec3f(0.0, 0.0, 0.0), UP, empty) == 1.0;
}

function firstShadowAt(position: Vec3f, b: LitBindings, key: LitKey): float32 {
	return recordShadowAt(position, UP, b, key, 0);
}

test "only the record the header names reads the spot map, and only in a shadowed program" {
	const view: CameraView = viewOf(downSpot(true));
	const blocked: LitBindings = spotMapped(spotLights(downSpot(true)), view, 0.0, 0.0, 1.0);
	const under: Vec3f = vec3f(0.0, 2.0, 0.0);
	assert firstShadowAt(under, blocked, { shadowed: true }) == 0.0;
	assert firstShadowAt(under, blocked, { shadowed: false }) == 1.0;
	const unflagged: LitBindings = spotMapped(spotLights(downSpot(false)), view, 0.0, 0.0, 1.0);
	assert firstShadowAt(under, unflagged, { shadowed: true }) == 1.0;
	assert recordShadowAt(under, UP, blocked, { shadowed: true }, 1) == 1.0;
	const cube: LitBindings = {
		...blocked,
		lightParams: {
			...blocked.lightParams,
			ambient: vec4f(0.0, 0.0, 0.0, 0.0),
			dirColor: vec4f(0.0, 0.0, 0.0, 1.0),
		},
	};
	assert firstShadowAt(under, cube, { shadowed: true }) == 1.0;
}

test "the sun and the spot read their own blocks and maps, each ignoring the other's" {
	const view: CameraView = viewOf(downSpot(true));
	const at: Vec3f = vec3f(0.0, 0.0, 0.0);
	const base: LitBindings = spotLights(downSpot(true));
	const bothOpen: LitBindings = spotMapped(sunMapped(base, 1.0, 1.0), view, 1.0, 0.0, 1.0);
	assert dirShadowAt(at, UP, bothOpen) == 1.0 && spotShadowAt(at, UP, bothOpen) == 1.0;
	const sunBlocked: LitBindings = spotMapped(sunMapped(base, 0.5, 1.0), view, 1.0, 0.0, 1.0);
	assert dirShadowAt(at, UP, sunBlocked) == 0.0 && spotShadowAt(at, UP, sunBlocked) == 1.0;
	const spotBlocked: LitBindings = spotMapped(sunMapped(base, 1.0, 1.0), view, 0.5, 0.0, 1.0);
	assert dirShadowAt(at, UP, spotBlocked) == 1.0 && spotShadowAt(at, UP, spotBlocked) == 0.0;
	const sunOnly: LitBindings = sunMapped(base, 0.5, 0.5);
	assert near(dirShadowAt(at, UP, sunOnly), 0.5) && spotShadowAt(at, UP, sunOnly) == 1.0;
	const spotOnly: LitBindings = spotMapped(base, view, 0.5, 0.0, 0.25);
	assert dirShadowAt(at, UP, spotOnly) == 1.0 && near(spotShadowAt(at, UP, spotOnly), 0.75);
}

function surface(b: LitBindings, pbr: boolean): Vec3f {
	return litFs({
		worldPosition: vec3f(0.0, 0.0, 0.0),
		worldNormal: vec3f(0.0, 1.0, 0.0),
		baseColor: vec4f(1.0, 1.0, 1.0, 1.0),
		frontFacing: true,
	}, b, { pbr: pbr, shadowed: true }).color.rgb;
}

function withSun(b: LitBindings): LitBindings {
	return {
		...b,
		lightParams: {
			...b.lightParams, dirLight: vec4f(0.0, 1.0, 0.0, 1.0), dirColor: vec4f(1.0, 1.0, 1.0, 0.0),
		},
	};
}

function withoutSun(b: LitBindings): LitBindings {
	return { ...b, lightParams: { ...b.lightParams, dirColor: NONE } };
}

function withoutSpot(b: LitBindings): LitBindings {
	return { ...b, lightRecords: withTexel(b.lightRecords, 0, 1, NONE) };
}

test "a surface is dark where its own light's map blocks it, in both shading paths" {
	const view: CameraView = viewOf(downSpot(true));
	const floorZ: float32 = depthAt(4.0);
	const lit: LitBindings = withSun(spotLights(downSpot(true)));
	const modes: Vec<boolean> = [false, true];
	for (const pbr of modes) {
		const open: Vec3f = surface(spotMapped(sunMapped(lit, 1.0, 1.0), view, 1.0, 0.0, 1.0), pbr);
		const sunOut: Vec3f = surface(spotMapped(sunMapped(lit, 0.5, 1.0), view, 1.0, 0.0, 1.0), pbr);
		const spotOut: Vec3f =
			surface(spotMapped(sunMapped(lit, 1.0, 1.0), view, floorZ - 0.05, 0.0, 1.0), pbr);
		const bothOut: Vec3f =
			surface(spotMapped(sunMapped(lit, 0.5, 1.0), view, floorZ - 0.05, 0.0, 1.0), pbr);
		const spotAlone: Vec3f = surface(withoutSun(spotMapped(lit, view, 1.0, 0.0, 1.0)), pbr);
		const sunAlone: Vec3f = surface(withoutSpot(sunMapped(lit, 1.0, 1.0)), pbr);
		assert open.x > 0.0 && bothOut.x == 0.0;
		assert sunOut.x > 0.0 && sunOut.x < open.x;
		assert spotOut.x > 0.0 && spotOut.x < open.x;
		assert near(sunOut.x, spotAlone.x, 1e-5);
		assert near(spotOut.x, sunAlone.x, 1e-5);
	}
}

function refusalOf(lights: Vec<float32>, sun: boolean, spot: boolean): RendererError | null {
	let context: DrawContext = DrawContext.withUniformCapacity(
		RENDERER_UNIFORM_LENGTH + 2 * DIR_SHADOW_UNIFORM_LENGTH,
	);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	const sunMap: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 64);
	const spotMap: Result<DirShadowMap, ShadowError> = DirShadowMap.createSpot(context, 64);
	if (!created.ok || !sunMap.ok || !spotMap.ok) { unreachable; }
	let core: Renderer = created.value;
	if (sun) { attachShadow(core, sunMap.value); }
	if (spot) { attachSpotShadow(core, spotMap.value); }
	const items: Vec<DrawItem> = [];
	const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	const began: Result<boolean, RendererError> = beginFrame(core, items, camera, lights);
	return began.ok ? null : began.error;
}

test "a frame whose header names no spot record is refused before it writes" {
	let lights: Vec<float32> = downSpot(true);
	lights[LIGHT_SPOT_CASTER] = 2.0;
	assert refusalOf(lights, true, true) == RendererError.BadShadowSpot;
	assert refusalOf(lights, false, true) == RendererError.BadShadowSpot;
	assert refusalOf(lights, false, false) == RendererError.BadShadowSpot;
}

test "a shadowing spot with no range is refused by the frame, not drawn from a broken camera" {
	let lights: Vec<float32> = downSpot(true);
	lights[LIGHT_UNIFORM_LENGTH + LIGHT_RECORD_COLOR + 3] = 0.0;
	assert refusalOf(lights, true, true) == RendererError.BadShadowSpot;
}

test "a shadowing spot with no spot map attached is refused, not drawn unshadowed" {
	assert refusalOf(downSpot(true), true, false) == RendererError.SpotShadowUnattached;
	assert refusalOf(downSpot(true), false, false) == RendererError.SpotShadowUnattached;
}

test "the sun's map and the spot's are made apart, and a frame applies the sun's block with the spot's half" {
	let context: DrawContext = DrawContext.withUniformCapacity(
		RENDERER_UNIFORM_LENGTH + 2 * DIR_SHADOW_UNIFORM_LENGTH,
	);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	const sunMap: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 64);
	const spotMap: Result<DirShadowMap, ShadowError> = DirShadowMap.createSpot(context, 64);
	if (!created.ok || !sunMap.ok || !spotMap.ok) { unreachable; }
	let core: Renderer = created.value;
	const sun: DirShadowMap = sunMap.value;
	const spot: DirShadowMap = spotMap.value;
	assert sun.kind == ShadowKind.Sun && spot.kind == ShadowKind.Spot;
	assert sun.shadowBlock.length == SHADOW_UNIFORM_LENGTH;
	attachSpotShadow(core, spot);
	assert core.sceneGlobals.length == 4 && core.sceneGlobals[3] == spot.shadowBlock;
	attachShadow(core, sun);
	assert core.sceneGlobals.length == 4 && core.sceneGlobals[3] == sun.shadowBlock;
	sun.shadowValues[SHADOW_CASCADE_INFO + 2] = 0.125;
	spot.shadowValues[SHADOW_SPOT_BIAS] = 0.25;
	spot.shadowValues[SHADOW_SPOT_OPACITY] = 0.5;
	carryShadows(sun, spot, null);
	const at: int32 = sun.shadowBlock.offset;
	assert context.uniforms.values[at + SHADOW_CASCADE_INFO + 2] == 0.125;
	assert context.uniforms.values[at + SHADOW_SPOT_BIAS] == 0.25;
	assert context.uniforms.values[at + SHADOW_SPOT_OPACITY] == 0.5;
	attachSpotShadow(core, null);
	carryShadows(sun, null, null);
	assert context.uniforms.values[at + SHADOW_CASCADE_INFO + 2] == 0.125;
	assert context.uniforms.values[at + SHADOW_SPOT_BIAS] == 0.0;
	assert context.uniforms.values[at + SHADOW_SPOT_OPACITY] == 0.0;
	attachShadow(core, null);
	assert core.sceneGlobals.length == 3;
}

function sunCascades(first: float32, second: float32): LitBindings {
	let context: DrawContext = DrawContext.withUniformCapacity(DIR_SHADOW_UNIFORM_LENGTH);
	const made: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 1);
	if (!made.ok) { unreachable; }
	let sun: DirShadowMap = made.value;
	const set: Result<int32, CascadeError> =
		sun.setCascades({ bounds: [10.0, 20.0], overlap: 0.2, minimumDistance: 0.1 });
	if (!set.ok || set.value != 2) { unreachable; }
	const flat: Mat4 = { ...translation(0.5, 0.5, 0.9), m11: 0.0, m22: 0.0, m33: 0.0 };
	sun.packSun({ clips: [identity(), identity()], far: [10.0, 20.0] }, flat, vec3(0.0, 0.0, 1.0));
	return {
		...spotLights(downSpot(true)),
		shadowParams: shadowParamsOf(sun.shadowValues),
		shadowMap: {
			width: 1, height: 1, layers: 2, texels: [first, 0.0, 0.0, 1.0, second, 0.0, 0.0, 1.0],
		},
	};
}

function sunAt(depth: float32, b: LitBindings): float32 {
	return dirShadowAt(vec3f(0.0, 5.0, 1.0 + depth), UP, b);
}

test "a packed two-cascade sun reads each depth's layer, blends the overlap, and lights past it" {
	assert MAX_CASCADES * 16 == SHADOW_CASCADE_FAR;
	const nearBlocked: LitBindings = sunCascades(0.5, 1.0);
	assert sunAt(5.0, nearBlocked) == 0.0 && near(sunAt(9.0, nearBlocked), 0.5);
	assert sunAt(15.0, nearBlocked) == 1.0 && sunAt(25.0, nearBlocked) == 1.0;
	const farBlocked: LitBindings = sunCascades(1.0, 0.5);
	assert sunAt(5.0, farBlocked) == 1.0 && near(sunAt(9.0, farBlocked), 0.5);
	assert sunAt(15.0, farBlocked) == 0.0 && sunAt(25.0, farBlocked) == 1.0;
}

test "a sun refuses a cascade config whose bounds do not rise, keeping the one it had" {
	let context: DrawContext = DrawContext.withUniformCapacity(DIR_SHADOW_UNIFORM_LENGTH);
	const made: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 1);
	if (!made.ok) { unreachable; }
	let sun: DirShadowMap = made.value;
	const falling: Result<int32, CascadeError> =
		sun.setCascades({ bounds: [20.0, 10.0], overlap: 0.2, minimumDistance: 0.1 });
	assert !falling.ok && falling.error == CascadeError.Bounds && sun.cascades === null;
}

// An 8x8 spot map shadowed left of its middle column and open right of it.
function spotSplit(b: LitBindings, view: CameraView, pcf: float32): LitBindings {
	let texels: float32[] = [];
	for (let y = 0; y < 8; y++) {
		for (let x = 0; x < 8; x++) {
			const depth: float32 = x < 4 ? 0.0 : 1.0;
			const texel: float32[] = [depth, 0.0, 0.0, 1.0];
			for (const v of texel) { texels.push(v); }
		}
	}
	return {
		...b,
		shadowParams: {
			...b.shadowParams, spotMatrix: spotMapOf(view), spotShadow: vec4f(0.0, 1.0, 8.0, pcf),
		},
		spotShadowMap: { width: 8, height: 8, layers: 1, texels: texels },
	};
}

test "a Pcf spot map softens the edge over its Poisson taps and leaves the far sides whole" {
	const view: CameraView = viewOf(downSpot(true));
	const base: LitBindings = spotLights(downSpot(true));
	const middle: Vec3f = vec3f(0.0, 2.0, 0.0);
	assert spotShadowAt(middle, UP, spotSplit(base, view, 0.0)) == 1.0;
	const soft: float32 = spotShadowAt(middle, UP, spotSplit(base, view, 2.0));
	assert soft > 0.0 && soft < 1.0;
	const left: float32 = spotShadowAt(vec3f(-1.4, 2.0, 0.0), UP, spotSplit(base, view, 2.0));
	const right: float32 = spotShadowAt(vec3f(1.4, 2.0, 0.0), UP, spotSplit(base, view, 2.0));
	assert Math.min(left, right) == 0.0 && Math.max(left, right) == 1.0;
}

function spotReceiving(b: LitBindings, view: CameraView, normalBias: float32): LitBindings {
	return {
		...b,
		shadowParams: {
			...b.shadowParams,
			spotReceiver: vec4f(normalBias, view.eye.x, view.eye.y, view.eye.z),
		},
	};
}

test "the spot's normal bias moves the receiver along its normal, scaled by its distance" {
	const view: CameraView = viewOf(downSpot(true));
	const split: LitBindings = spotSplit(spotLights(downSpot(true)), view, 0.0);
	const left: Vec3f = vec3f(-1.4, 2.0, 0.0);
	const right: Vec3f = vec3f(1.0, 0.0, 0.0);
	const unbiased: float32 = spotShadowAt(left, right, split);
	const across: float32 = spotShadowAt(vec3f(1.4, 2.0, 0.0), right, split);
	assert unbiased != across;
	assert spotShadowAt(left, right, spotReceiving(split, view, 0.0)) == unbiased;
	assert spotShadowAt(left, right, spotReceiving(split, view, 1.15)) == across;
	assert spotShadowAt(left, -right, spotReceiving(split, view, 0.2)) == unbiased;
}

test "a map packs its PCF scale only when it samples with Pcf" {
	let context: DrawContext = DrawContext.withUniformCapacity(DIR_SHADOW_UNIFORM_LENGTH);
	const made: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 1);
	if (!made.ok) { unreachable; }
	let sun: DirShadowMap = made.value;
	const layers: SunLayers = { clips: [identity()], far: [10.0] };
	sun.packSun(layers, identity(), vec3(0.0, 0.0, 1.0));
	assert sun.shadowValues[SHADOW_CASCADE_FILTER] == 0.0;
	sun.samplingKind = ShadowSamplingKind.Pcf;
	sun.pcfScale = 1.5;
	sun.packSun(layers, identity(), vec3(0.0, 0.0, 1.0));
	assert sun.shadowValues[SHADOW_CASCADE_FILTER] == 1.5;
}

// An 8x8 sun map shadowed left of its middle column and open right of it, `perWorld` of the
// map's width to a world unit.
function sunSplit(b: LitBindings, perWorld: float32, normalBias: float32): LitBindings {
	let texels: float32[] = [];
	for (let y = 0; y < 8; y++) {
		for (let x = 0; x < 8; x++) {
			const texel: float32[] = [x < 4 ? 0.0 : 1.0, 0.0, 0.0, 1.0];
			for (const v of texel) { texels.push(v); }
		}
	}
	const map: Mat4x4f = mat4x4f(
		vec4f(perWorld, 0.0, 0.0, 0.0), vec4f(0.0, perWorld, 0.0, 0.0),
		vec4f(0.0, 0.0, 0.0, 0.0), vec4f(0.5, 0.5, 0.9, 1.0),
	);
	return {
		...b,
		shadowParams: {
			...b.shadowParams,
			cascadeMatrices: [map, map, map, map],
			cascadeFar: vec4f(3.0e38, 0.0, 0.0, 0.0),
			cascadeInfo: vec4f(1.0, 0.0, 0.0, 1.0),
			cascadeView: vec4f(0.0, 0.0, 1.0, 8.0),
			cascadeFilter: vec4f(0.0, normalBias, 0.0, 0.0),
		},
		shadowMap: { width: 8, height: 8, layers: 1, texels: texels },
	};
}

test "the sun's normal bias moves the receiver along its normal by texels of the cascade" {
	const base: LitBindings = spotLights(downSpot(true));
	const right: Vec3f = vec3f(1.0, 0.0, 0.0);
	assert dirShadowAt(vec3f(-0.5, 0.0, 0.0), right, sunSplit(base, 0.125, 0.0)) == 0.0;
	assert dirShadowAt(vec3f(-0.5, 0.0, 0.0), right, sunSplit(base, 0.125, 1.0)) == 1.0;
	assert dirShadowAt(vec3f(0.5, 0.0, 0.0), -right, sunSplit(base, 0.125, 1.0)) == 0.0;
	assert dirShadowAt(vec3f(-1.5, 0.0, 0.0), right, sunSplit(base, 0.0625, 0.5)) == 0.0;
	assert dirShadowAt(vec3f(-1.5, 0.0, 0.0), right, sunSplit(base, 0.0625, 1.0)) == 1.0;
}

test "a sun packs its normal bias times the root of two, zero unless set as Heaps has none" {
	let context: DrawContext = DrawContext.withUniformCapacity(DIR_SHADOW_UNIFORM_LENGTH);
	const made: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 1);
	if (!made.ok) { unreachable; }
	let sun: DirShadowMap = made.value;
	assert sun.normalBias == 0.0;
	sun.normalBias = 1.5;
	sun.packSun({ clips: [identity()], far: [10.0] }, identity(), vec3(0.0, 0.0, 1.0));
	assert near(sun.shadowValues[SHADOW_CASCADE_NORMAL_BIAS], (1.5 * Math.SQRT2) as float32);
	assert near(shadowParamsOf(sun.shadowValues).cascadeFilter.y, (1.5 * Math.SQRT2) as float32);
}
