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
	SHADOW_POINT_BASE,
	SHADOW_POINT_OPACITY,
	SHADOW_POINT_POSITION,
	SHADOW_POINT_FILTER,
	LIGHT_UNIFORM_LENGTH,
	LIGHT_RECORD_COLOR,
	LIGHT_RECORD_LENGTH,
	VERTEX_UNIFORM_LENGTH,
} from "../void3d/gpu3d";
import { CameraView } from "../void3d/camera";
import {
	PointShadowError,
	POINT_SHADOW_NEAR,
	shadowedPointCount,
	firstShadowedPoint,
	pointShadowViews,
} from "../void3d/pointShadow";
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
	attachPointShadow,
} from "../void3d/renderer";
import {
	LitBindings,
	LitKey,
	pointFaceOf,
	pointShadowAt,
	recordShadowAt,
	litTexelOf,
} from "../void3d/shader3d";
import { oneLayer, shadowParamsOf } from "./shadowHelpers";
import { SceneLights, recordsOf, sceneLights } from "./lightHelpers";

const RANGE: float32 = 8.0;
const LIGHT_AT: Vec3 = vec3(1, 2, 3);
const UNIT: Vec3 = vec3(1, 1, 1);
const NONE: Vec4f = vec4f(0.0, 0.0, 0.0, 0.0);
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

function pointOf(shadows: boolean): LightInstance {
	return {
		kind: LightKind.Point, color: vec3(1, 1, 1), radius: RANGE, power: 1, priority: 0,
		shape: {
			angle: 0.0, verticalAngle: 0.0, falloff: 0.0, width: 0.0, height: 0.0, length: 0.0,
			capsuleRadius: 0.0,
		},
		shadows: shadows,
	};
}

function collected(flags: Vec<boolean>): Result<Vec<float32>, LightError> {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	for (const flag of flags) {
		addLightNode(scene, scene.rootId(),
			{ position: LIGHT_AT, rotation: identityQuat(), scale: UNIT }, pointOf(flag));
	}
	let values: Vec<float32> = [];
	for (let i = 0; i < LIGHT_UNIFORM_LENGTH; i++) { values.push(0); }
	const done: Result<int32, LightError> = collectLights(scene, values);
	if (!done.ok) { return Result.err(done.error); }
	return Result.ok(move values);
}

function pointLights(shadows: boolean): Vec<float32> {
	const values: Result<Vec<float32>, LightError> = collected([shadows]);
	if (!values.ok) { unreachable; }
	return values.value;
}

function viewsOf(values: Vec<float32>): Vec<CameraView> {
	const views: Result<Vec<CameraView>, PointShadowError> = pointShadowViews(values, 0);
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
		assert pointFaceOf(vec3f(axis.x, axis.y, axis.z)) == face;
	}
}

test "the shadowing point is the flagged record, and a second one is refused by name" {
	const lit: Vec<float32> = pointLights(true);
	assert shadowedPointCount(lit) == 1 && firstShadowedPoint(lit) == 0;
	const plain: Vec<float32> = pointLights(false);
	assert shadowedPointCount(plain) == 0 && firstShadowedPoint(plain) == -1;
	const two: Result<Vec<float32>, LightError> = collected([true, false, true]);
	assert !two.ok && two.error == LightError.TooManyShadowedPoints;
}

test "a point whose range does not pass zNear is a named error, not a broken camera" {
	let values: Vec<float32> = pointLights(true);
	values[LIGHT_UNIFORM_LENGTH + LIGHT_RECORD_COLOR + 3] = POINT_SHADOW_NEAR;
	const views: Result<Vec<CameraView>, PointShadowError> = pointShadowViews(values, 0);
	assert !views.ok && views.error == PointShadowError.BadRange;
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

function packed(values: Vec<float32>, opacity: float32, pcf: float32): Vec<float32> {
	let context: DrawContext = DrawContext.withUniformCapacity(DIR_SHADOW_UNIFORM_LENGTH);
	const made: Result<DirShadowMap, ShadowError> = DirShadowMap.createPoint(context, 1);
	if (!made.ok) { unreachable; }
	let map: DirShadowMap = made.value;
	if (pcf > 0.0) {
		map.samplingKind = ShadowSamplingKind.Pcf;
		map.pcfScale = pcf;
	}
	let clips: Vec<Mat4> = [];
	for (const view of viewsOf(values)) { clips.push(view.viewProj); }
	map.packPoint(clips, TOP_LEFT_MAP, LIGHT_AT, opacity);
	let out: Vec<float32> = [];
	for (const v of map.shadowValues) { out.push(v); }
	return move out;
}

function pointBindings(
	values: Vec<float32>, opacity: float32, blocked: float32, pcf: float32 = 0.0,
): LitBindings {
	const lights: SceneLights =
		sceneLights(vec4f(0.0, 0.0, 0.0, 1.0), NONE, NONE, recordsOf(values));
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
		shadowParams: shadowParamsOf(packed(values, opacity, pcf)),
		shadowMap: oneLayer(white()),
		shadowSampler: { nearest: true },
		spotShadowMap: oneLayer(white()),
		spotShadowSampler: { nearest: true },
		pointShadowMap: faces(blocked),
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
	assert pointShadowAt(offset + vec3f(2.0, 0.3, -0.2), blocked) == 0.0;
	assert pointShadowAt(offset + vec3f(-2.0, 0.3, -0.2), blocked) == 1.0;
	assert pointShadowAt(offset + vec3f(0.3, 0.2, 2.0), blocked) == 1.0;
	assert pointShadowAt(offset + vec3f(0.3, -2.0, 0.2), blocked) == 1.0;
	assert near(pointShadowAt(offset + vec3f(2.0, 0.3, -0.2), pointBindings(values, 0.25, 0.0)),
		0.75);
	assert pointShadowAt(offset + vec3f(2.0, 0.3, -0.2), pointBindings(values, 1.0, 1.0)) == 1.0;
}

function firstShadowAt(position: Vec3f, b: LitBindings, key: LitKey): float32 {
	return recordShadowAt(position, b, key, litTexelOf(b, 0, 2), litTexelOf(b, 0, 3));
}

test "only the flagged point record reads the point map, and only in a shadowed program" {
	const at: Vec3f = vec3f(LIGHT_AT.x + 2.0, LIGHT_AT.y, LIGHT_AT.z);
	const flagged: LitBindings = pointBindings(pointLights(true), 1.0, 0.0);
	assert firstShadowAt(at, flagged, { shadowed: true }) == 0.0;
	assert firstShadowAt(at, flagged, { shadowed: false }) == 1.0;
	const plain: LitBindings = pointBindings(pointLights(false), 1.0, 0.0);
	assert firstShadowAt(at, plain, { shadowed: true }) == 1.0;
}

function frameOf(lights: Vec<float32>, sun: boolean, point: boolean): RendererError | null {
	let context: DrawContext = DrawContext.withUniformCapacity(
		RENDERER_UNIFORM_LENGTH + 2 * DIR_SHADOW_UNIFORM_LENGTH,
	);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	const sunMap: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 64);
	const pointMap: Result<DirShadowMap, ShadowError> = DirShadowMap.createPoint(context, 64);
	if (!created.ok || !sunMap.ok || !pointMap.ok) { unreachable; }
	let core: Renderer = created.value;
	if (sun) { attachShadow(core, sunMap.value); }
	if (point) { attachPointShadow(core, pointMap.value); }
	const items: Vec<DrawItem> = [];
	const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	const began: Result<boolean, RendererError> = beginFrame(core, items, camera, lights);
	return began.ok ? null : began.error;
}

test "a frame refuses two shadowing points, a point with no range, and a point with no map" {
	let two: Vec<float32> = pointLights(true);
	for (let i = 0; i < LIGHT_RECORD_LENGTH; i++) { two.push(two[LIGHT_UNIFORM_LENGTH + i]); }
	assert frameOf(two, true, true) == RendererError.TooManyShadowedPoints;
	assert frameOf(two, false, false) == RendererError.TooManyShadowedPoints;
	let short: Vec<float32> = pointLights(true);
	short[LIGHT_UNIFORM_LENGTH + LIGHT_RECORD_COLOR + 3] = POINT_SHADOW_NEAR;
	assert frameOf(short, false, true) == RendererError.BadShadowPoint;
	assert frameOf(pointLights(true), true, false) == RendererError.PointShadowUnattached;
	assert frameOf(pointLights(true), false, false) == RendererError.PointShadowUnattached;
}

test "a point map alone owns the frame's block, and beside the sun's it lends its part" {
	let context: DrawContext = DrawContext.withUniformCapacity(
		RENDERER_UNIFORM_LENGTH + 2 * DIR_SHADOW_UNIFORM_LENGTH,
	);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	const sunMap: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 64);
	const pointMap: Result<DirShadowMap, ShadowError> = DirShadowMap.createPoint(context, 64);
	if (!created.ok || !sunMap.ok || !pointMap.ok) { unreachable; }
	let core: Renderer = created.value;
	const sun: DirShadowMap = sunMap.value;
	const point: DirShadowMap = pointMap.value;
	assert point.kind == ShadowKind.Point;
	attachPointShadow(core, point);
	assert core.sceneGlobals.length == 4 && core.sceneGlobals[3] == point.shadowBlock;
	attachShadow(core, sun);
	assert core.sceneGlobals[3] == sun.shadowBlock;
	point.shadowValues[SHADOW_POINT_BASE] = 0.5;
	point.shadowValues[SHADOW_POINT_OPACITY] = 0.25;
	point.shadowValues[SHADOW_POINT_POSITION + 2] = 3.0;
	carryShadows(sun, null, point);
	const at: int32 = sun.shadowBlock.offset;
	assert context.uniforms.values[at + SHADOW_POINT_BASE] == 0.5;
	assert context.uniforms.values[at + SHADOW_POINT_OPACITY] == 0.25;
	assert context.uniforms.values[at + SHADOW_POINT_POSITION + 2] == 3.0;
	carryShadows(sun, null, null);
	assert context.uniforms.values[at + SHADOW_POINT_OPACITY] == 0.0;
	attachShadow(core, null);
	attachPointShadow(core, null);
	assert core.sceneGlobals.length == 3;
}

test "a Pcf point map turns its taps around the receiver's direction and averages their faces" {
	const values: Vec<float32> = pointLights(true);
	const at: Vec3f = vec3f(LIGHT_AT.x + 2.0, LIGHT_AT.y + 0.3, LIGHT_AT.z - 0.2);
	assert pointShadowAt(at, pointBindings(values, 1.0, 0.0)) == 0.0;
	const filtered: float32 = pointShadowAt(at, pointBindings(values, 1.0, 0.0, 0.5));
	assert filtered > 0.0 && filtered < 1.0;
	assert pointShadowAt(at, pointBindings(values, 1.0, 1.0, 0.5)) == 1.0;
	const packedScale: Vec<float32> = packed(values, 1.0, 0.5);
	assert packedScale[SHADOW_POINT_FILTER] == 0.5;
	assert packed(values, 1.0, 0.0)[SHADOW_POINT_FILTER] == 0.0;
}
