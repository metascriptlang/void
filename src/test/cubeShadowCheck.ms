import { Vec3, Mat4, vec3, identityQuat } from "../math/math3d";
import { Texture2d, Texture2dArray, Vec3f, Vec4f, vec3f, vec4f } from "../shader/std";
import {
	Scene3D,
	LightKind,
	LightInstance,
	LightError,
	addLightNode,
	collectLights,
	closeScene,
} from "../void3d/scene";
import { DrawContext, DrawItem } from "../void3d/draw";
import {
	SHADOW_CUBE_BASE,
	SHADOW_CUBE_OPACITY,
	SHADOW_CUBE_POSITION,
	SHADOW_CUBE_FILTER,
	SHADOW_CUBE_NORMAL_BIAS,
	LIGHT_UNIFORM_LENGTH,
	LIGHT_RECORD_COLOR,
	LIGHT_SPOT_CASTER,
	LIGHT_CUBE_CASTER,
	VERTEX_UNIFORM_LENGTH,
} from "../void3d/gpu3d";
import { CameraView } from "../void3d/camera";
import {
	CubeShadowError,
	POINT_SHADOW_NEAR,
	RECTANGLE_SHADOW_NEAR,
	cubeCaster,
	cubeNear,
	cubeShadowViews,
} from "../void3d/cubeShadow";
import {
	DirShadowMap,
	ShadowError,
	ShadowKind,
	ShadowSamplingKind,
	DIR_SHADOW_UNIFORM_LENGTH,
	carryShadows,
} from "../void3d/dirShadowMap";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	beginFrame,
	attachShadow,
	attachCubeShadow,
} from "../void3d/renderer";
import {
	LitBindings,
	LitKey,
	cubeFaceOf,
	cubeShadowAt,
	recordShadowAt,
} from "../void3d/shader3d";
import { oneLayer, shadowParamsOf } from "./shadowHelpers";
import { SceneLights, recordsOf, sceneLights } from "./lightHelpers";

const RANGE: float32 = 8.0;
const LIGHT_AT: Vec3 = vec3(1, 2, 3);
const UNIT: Vec3 = vec3(1, 1, 1);
const NONE: Vec4f = vec4f(0.0, 0.0, 0.0, 0.0);
const UP: Vec3f = vec3f(0.0, 1.0, 0.0);
const AXES: Vec<Vec3> = [
	vec3(1, 0, 0), vec3(-1, 0, 0), vec3(0, 1, 0), vec3(0, -1, 0), vec3(0, 0, 1), vec3(0, 0, -1),
];
// D3D11 and Metal's map: rows from the top, depth stored as is.
const TOP_LEFT_MAP: Mat4 = {
	m11: 0.5, m12: 0.0, m13: 0.0, m14: 0.0,
	m21: 0.0, m22: -0.5, m23: 0.0, m24: 0.0,
	m31: 0.0, m32: 0.0, m33: 1.0, m34: 0.0,
	m41: 0.5, m42: 0.5, m43: 0.0, m44: 1.0,
};

function near(a: float32, b: float32, tolerance: float32 = 1e-4): boolean {
	return Math.abs(a - b) <= tolerance;
}

function lightOf(kind: LightKind, shadows: boolean): LightInstance {
	return {
		kind: kind, color: vec3(1, 1, 1), radius: RANGE, power: 1, priority: 0,
		shape: {
			angle: 1.0, verticalAngle: 1.0, falloff: 0.0, width: 1.0, height: 1.0, length: 1.0,
			capsuleRadius: 0.2,
		},
		shadows: shadows,
	};
}

function collected(lights: Vec<LightInstance>): Result<Vec<float32>, LightError> {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	for (const light of lights) {
		addLightNode(scene, scene.rootId(),
			{ position: LIGHT_AT, rotation: identityQuat(), scale: UNIT }, light);
	}
	let values: Vec<float32> = [];
	for (let i = 0; i < LIGHT_UNIFORM_LENGTH; i++) { values.push(0); }
	const done: Result<int32, LightError> = collectLights(scene, values);
	if (!done.ok) { return Result.err(done.error); }
	return Result.ok(move values);
}

function lightsOf(kind: LightKind, shadows: boolean): Vec<float32> {
	const values: Result<Vec<float32>, LightError> = collected([lightOf(kind, shadows)]);
	if (!values.ok) { unreachable; }
	return values.value;
}

function pointLights(shadows: boolean): Vec<float32> {
	return lightsOf(LightKind.Point, shadows);
}

function casterOf(values: Vec<float32>): int32 {
	const caster: Result<int32, CubeShadowError> = cubeCaster(values);
	if (!caster.ok) { unreachable; }
	return caster.value;
}

function viewsOf(values: Vec<float32>): Vec<CameraView> {
	const views: Result<Vec<CameraView>, CubeShadowError> = cubeShadowViews(values, 0);
	if (!views.ok) { unreachable; }
	return views.value;
}

function ndcOf(m: Mat4, p: Vec3): Vec3 {
	const w: float32 = p.x * m.m14 + p.y * m.m24 + p.z * m.m34 + m.m44;
	return vec3(
		(p.x * m.m11 + p.y * m.m21 + p.z * m.m31 + m.m41) / w,
		(p.x * m.m12 + p.y * m.m22 + p.z * m.m32 + m.m42) / w,
		(p.x * m.m13 + p.y * m.m23 + p.z * m.m33 + m.m43) / w,
	);
}

test "a shadowing point's six faces look down the axes from zNear to the range" {
	const views: Vec<CameraView> = viewsOf(pointLights(true));
	assert views.length == 6;
	for (let face = 0; face < 6; face++) {
		const axis: Vec3 = AXES[face];
		const m: Mat4 = views[face].viewProj;
		const nearest: Vec3 = ndcOf(m, LIGHT_AT + axis.scaled(POINT_SHADOW_NEAR));
		assert near(nearest.x, 0.0) && near(nearest.y, 0.0) && near(nearest.z, 0.0, 1e-3);
		assert near(ndcOf(m, LIGHT_AT + axis.scaled(RANGE)).z, 1.0, 1e-5);
		assert cubeFaceOf(vec3f(axis.x, axis.y, axis.z)) == face;
	}
}

test "the light block's header names the cube caster, and a second one is refused by name" {
	const lit: Vec<float32> = pointLights(true);
	assert lit[LIGHT_CUBE_CASTER] == 1.0 && casterOf(lit) == 0;
	const plain: Vec<float32> = pointLights(false);
	assert plain[LIGHT_CUBE_CASTER] == 0.0 && casterOf(plain) == -1;
	const second: Result<Vec<float32>, LightError> =
		collected([lightOf(LightKind.Point, false), lightOf(LightKind.Capsule, true)]);
	assert second.ok && second.value[LIGHT_CUBE_CASTER] == 2.0 && casterOf(second.value) == 1;
	const kinds: Vec<LightKind> = [LightKind.Point, LightKind.Rectangle, LightKind.Capsule];
	for (const kind of kinds) {
		const two: Result<Vec<float32>, LightError> =
			collected([lightOf(LightKind.Point, true), lightOf(kind, true)]);
		assert !two.ok && two.error == LightError.TooManyCubeCasters;
	}
}

test "a rectangle's faces start at RectangleShadowMap's 0.01 and a capsule's at its zNear" {
	const rectangle: Vec<CameraView> = viewsOf(lightsOf(LightKind.Rectangle, true));
	const capsule: Vec<CameraView> = viewsOf(lightsOf(LightKind.Capsule, true));
	for (let face = 0; face < 6; face++) {
		const axis: Vec3 = AXES[face];
		const r: Mat4 = rectangle[face].viewProj;
		assert near(ndcOf(r, LIGHT_AT + axis.scaled(RECTANGLE_SHADOW_NEAR)).z, 0.0, 1e-3);
		assert near(ndcOf(r, LIGHT_AT + axis.scaled(RANGE)).z, 1.0, 1e-5);
		const c: Mat4 = capsule[face].viewProj;
		assert near(ndcOf(c, LIGHT_AT + axis.scaled(POINT_SHADOW_NEAR)).z, 0.0, 1e-3);
		assert near(ndcOf(c, LIGHT_AT + axis.scaled(RANGE)).z, 1.0, 1e-5);
	}
}

test "a header that names no point, rectangle or capsule record is a named error" {
	let values: Vec<float32> = lightsOf(LightKind.Spot, false);
	const named: float32[] = [1.0, 2.0, 0.5, -1.0, NaN as float32];
	for (const v of named) {
		values[LIGHT_CUBE_CASTER] = v;
		const caster: Result<int32, CubeShadowError> = cubeCaster(values);
		assert !caster.ok && caster.error == CubeShadowError.BadCaster;
	}
}

test "a point whose range does not pass zNear is a named error, not a broken camera" {
	let values: Vec<float32> = pointLights(true);
	values[LIGHT_UNIFORM_LENGTH + LIGHT_RECORD_COLOR + 3] = POINT_SHADOW_NEAR;
	const views: Result<Vec<CameraView>, CubeShadowError> = cubeShadowViews(values, 0);
	assert !views.ok && views.error == CubeShadowError.BadRange;
}

function white(): Texture2d {
	return { width: 1, height: 1, texels: [1.0, 1.0, 1.0, 1.0] };
}

// One texel per face, the +X face's at `blocked` and the others at the far plane.
function faces(blocked: float32): Texture2dArray {
	let texels: float32[] = [blocked, 0.0, 0.0, 1.0];
	for (let face = 1; face < 6; face++) {
		const far: float32[] = [1.0, 0.0, 0.0, 1.0];
		for (const v of far) { texels.push(v); }
	}
	return { width: 1, height: 1, layers: 6, texels: texels };
}

function packed(
	values: Vec<float32>, opacity: float32, pcf: float32, normalBias: float32 = 0.0,
): Vec<float32> {
	let context: DrawContext = DrawContext.withUniformCapacity(DIR_SHADOW_UNIFORM_LENGTH);
	const made: Result<DirShadowMap, ShadowError> = DirShadowMap.createCube(context, 1);
	if (!made.ok) { unreachable; }
	let map: DirShadowMap = made.value;
	map.normalBias = normalBias;
	if (pcf > 0.0) {
		map.samplingKind = ShadowSamplingKind.Pcf;
		map.pcfScale = pcf;
	}
	let clips: Vec<Mat4> = [];
	for (const view of viewsOf(values)) { clips.push(view.viewProj); }
	map.packCube(clips, TOP_LEFT_MAP, LIGHT_AT, opacity, cubeNear(values, 0), RANGE);
	let out: Vec<float32> = [];
	for (const v of map.shadowValues) { out.push(v); }
	return move out;
}

function pointBindings(
	values: Vec<float32>, opacity: float32, blocked: float32, pcf: float32 = 0.0,
	normalBias: float32 = 0.0,
): LitBindings {
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
		shadowParams: shadowParamsOf(packed(values, opacity, pcf, normalBias)),
		shadowMap: oneLayer(white()),
		shadowSampler: { nearest: true },
		spotShadowMap: oneLayer(white()),
		spotShadowSampler: { nearest: true },
		cubeShadowMap: faces(blocked),
		baseTexture: white(),
		baseSampler: { nearest: true },
		backTexture: white(),
		dissolveTexture: white(),
		dissolveSampler: { nearest: true },
		emissiveTexture: white(),
		normalTexture: white(),
		metalRoughTexture: white(),
		occlusionTexture: white(),
		envDiffuse: { size: 0, texels: [] }, envSpecular: { size: 0, texels: [] },
	};
}

test "the lookup reads the layer of the face the receiver lies on, through the packed block" {
	const values: Vec<float32> = pointLights(true);
	const blocked: LitBindings = pointBindings(values, 1.0, 0.0);
	const offset: Vec3f = vec3f(LIGHT_AT.x, LIGHT_AT.y, LIGHT_AT.z);
	assert cubeShadowAt(offset + vec3f(2.0, 0.3, -0.2), UP, blocked) == 0.0;
	assert cubeShadowAt(offset + vec3f(-2.0, 0.3, -0.2), UP, blocked) == 1.0;
	assert cubeShadowAt(offset + vec3f(0.3, 0.2, 2.0), UP, blocked) == 1.0;
	assert cubeShadowAt(offset + vec3f(0.3, -2.0, 0.2), UP, blocked) == 1.0;
	assert near(cubeShadowAt(offset + vec3f(2.0, 0.3, -0.2), UP, pointBindings(values, 0.25, 0.0)),
		0.75);
	assert cubeShadowAt(offset + vec3f(2.0, 0.3, -0.2), UP, pointBindings(values, 1.0, 1.0)) == 1.0;
}

const RECEIVER: Vec3f = vec3f(2.0, 0.3, -0.2);
const RECEIVER_DISTANCE: float32 = Math.sqrt(4.0 + 0.09 + 0.04) as float32;

// The receiver's light behind a caster `radial` from the light on its ray, which the +X face
// stores at the depth of the ray's x.
function litBehind(radial: float32): float32 {
	const values: Vec<float32> = pointLights(true);
	const x: float32 = radial * RECEIVER.x / RECEIVER_DISTANCE;
	const depth: float32 = ndcOf(viewsOf(values)[0].viewProj, LIGHT_AT + vec3(x, 0, 0)).z;
	const at: Vec3f = vec3f(LIGHT_AT.x, LIGHT_AT.y, LIGHT_AT.z) + RECEIVER;
	return cubeShadowAt(at, UP, pointBindings(values, 1.0, depth));
}

test "the cube compares world distances, its 0.01 bias in world units, as CubeShadowMap does" {
	assert litBehind(1.0) == 0.0;
	assert litBehind(RECEIVER_DISTANCE - 0.02) == 0.0;
	assert litBehind(RECEIVER_DISTANCE - 0.005) == 1.0;
	assert litBehind(RECEIVER_DISTANCE) == 1.0;
}

// The receiver's light behind a caster 0.02 nearer the light on its ray, its normal facing the
// light or away from it, under Bevy's point normal bias.
function litFacing(toward: boolean, normalBias: float32): float32 {
	const values: Vec<float32> = pointLights(true);
	const radial: float32 = RECEIVER_DISTANCE - 0.02;
	const x: float32 = radial * RECEIVER.x / RECEIVER_DISTANCE;
	const depth: float32 = ndcOf(viewsOf(values)[0].viewProj, LIGHT_AT + vec3(x, 0, 0)).z;
	const at: Vec3f = vec3f(LIGHT_AT.x, LIGHT_AT.y, LIGHT_AT.z) + RECEIVER;
	const normal: Vec3f = RECEIVER * ((toward ? -1.0 : 1.0) / RECEIVER_DISTANCE);
	return cubeShadowAt(at, normal, pointBindings(values, 1.0, depth, 0.0, normalBias));
}

test "the point's normal bias moves the receiver along its normal, scaled by its distance" {
	assert litFacing(true, 0.0) == 0.0 && litFacing(false, 0.0) == 0.0;
	assert litFacing(true, 0.02) == 1.0 && litFacing(false, 0.02) == 0.0;
	const packedBias: float32 = packed(pointLights(true), 1.0, 0.0, 0.02)[SHADOW_CUBE_NORMAL_BIAS];
	assert near(packedBias, (0.02 * 2.0 * Math.SQRT2) as float32);
}

function firstShadowAt(position: Vec3f, b: LitBindings, key: LitKey): float32 {
	return recordShadowAt(position, UP, b, key, 0);
}

test "only the record the header names reads the cube map, and only in a shadowed program" {
	const at: Vec3f = vec3f(LIGHT_AT.x + 2.0, LIGHT_AT.y, LIGHT_AT.z);
	const flagged: LitBindings = pointBindings(pointLights(true), 1.0, 0.0);
	assert firstShadowAt(at, flagged, { shadowed: true }) == 0.0;
	assert firstShadowAt(at, flagged, { shadowed: false }) == 1.0;
	assert recordShadowAt(at, UP, flagged, { shadowed: true }, 1) == 1.0;
	const plain: LitBindings = pointBindings(pointLights(false), 1.0, 0.0);
	assert firstShadowAt(at, plain, { shadowed: true }) == 1.0;
	const kinds: Vec<LightKind> = [LightKind.Rectangle, LightKind.Capsule];
	for (const kind of kinds) {
		const shaped: LitBindings = pointBindings(lightsOf(kind, true), 1.0, 0.0);
		assert firstShadowAt(at, shaped, { shadowed: true }) == 0.0;
	}
}

function frameOf(lights: Vec<float32>, sun: boolean, point: boolean): RendererError | null {
	let context: DrawContext = DrawContext.withUniformCapacity(
		RENDERER_UNIFORM_LENGTH + 2 * DIR_SHADOW_UNIFORM_LENGTH,
	);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	const sunMap: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 64);
	const cubeMap: Result<DirShadowMap, ShadowError> = DirShadowMap.createCube(context, 64);
	if (!created.ok || !sunMap.ok || !cubeMap.ok) { unreachable; }
	let core: Renderer = created.value;
	if (sun) { attachShadow(core, sunMap.value); }
	if (point) { attachCubeShadow(core, cubeMap.value); }
	const items: Vec<DrawItem> = [];
	const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	const began: Result<boolean, RendererError> = beginFrame(core, items, camera, lights);
	return began.ok ? null : began.error;
}

test "a frame refuses a bad cube caster, a caster with no range, and a caster with no map" {
	let bad: Vec<float32> = pointLights(true);
	bad[LIGHT_CUBE_CASTER] = 2.0;
	assert frameOf(bad, true, true) == RendererError.BadCubeShadow;
	assert frameOf(bad, false, false) == RendererError.BadCubeShadow;
	assert frameOf(lightsOf(LightKind.Rectangle, true), false, false) ==
		RendererError.CubeShadowUnattached;
	let short: Vec<float32> = pointLights(true);
	short[LIGHT_UNIFORM_LENGTH + LIGHT_RECORD_COLOR + 3] = POINT_SHADOW_NEAR;
	assert frameOf(short, false, true) == RendererError.BadCubeShadow;
	assert frameOf(pointLights(true), true, false) == RendererError.CubeShadowUnattached;
	assert frameOf(pointLights(true), false, false) == RendererError.CubeShadowUnattached;
}

test "a point map alone owns the frame's block, and beside the sun's it lends its part" {
	let context: DrawContext = DrawContext.withUniformCapacity(
		RENDERER_UNIFORM_LENGTH + 2 * DIR_SHADOW_UNIFORM_LENGTH,
	);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	const sunMap: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 64);
	const cubeMap: Result<DirShadowMap, ShadowError> = DirShadowMap.createCube(context, 64);
	if (!created.ok || !sunMap.ok || !cubeMap.ok) { unreachable; }
	let core: Renderer = created.value;
	const sun: DirShadowMap = sunMap.value;
	const point: DirShadowMap = cubeMap.value;
	assert point.kind == ShadowKind.Cube;
	attachCubeShadow(core, point);
	assert core.sceneGlobals.length == 4 && core.sceneGlobals[3] == point.shadowBlock;
	attachShadow(core, sun);
	assert core.sceneGlobals[3] == sun.shadowBlock;
	point.shadowValues[SHADOW_CUBE_BASE] = 0.5;
	point.shadowValues[SHADOW_CUBE_OPACITY] = 0.25;
	point.shadowValues[SHADOW_CUBE_POSITION + 2] = 3.0;
	carryShadows(sun, null, point);
	const at: int32 = sun.shadowBlock.offset;
	assert context.uniforms.values[at + SHADOW_CUBE_BASE] == 0.5;
	assert context.uniforms.values[at + SHADOW_CUBE_OPACITY] == 0.25;
	assert context.uniforms.values[at + SHADOW_CUBE_POSITION + 2] == 3.0;
	carryShadows(sun, null, null);
	assert context.uniforms.values[at + SHADOW_CUBE_OPACITY] == 0.0;
	attachShadow(core, null);
	attachCubeShadow(core, null);
	assert core.sceneGlobals.length == 3;
}

test "a Pcf point map turns its taps around the receiver's direction and averages their faces" {
	const values: Vec<float32> = pointLights(true);
	const at: Vec3f = vec3f(LIGHT_AT.x + 2.0, LIGHT_AT.y + 0.3, LIGHT_AT.z - 0.2);
	assert cubeShadowAt(at, UP, pointBindings(values, 1.0, 0.0)) == 0.0;
	const filtered: float32 = cubeShadowAt(at, UP, pointBindings(values, 1.0, 0.0, 0.5));
	assert filtered > 0.0 && filtered < 1.0;
	assert cubeShadowAt(at, UP, pointBindings(values, 1.0, 1.0, 0.5)) == 1.0;
	const packedScale: Vec<float32> = packed(values, 1.0, 0.5);
	assert packedScale[SHADOW_CUBE_FILTER] == 0.5;
	assert packed(values, 1.0, 0.0)[SHADOW_CUBE_FILTER] == 0.0;
}
