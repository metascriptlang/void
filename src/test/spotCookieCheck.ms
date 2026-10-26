import { Vec3, Quat, Mat4, vec3, axisAngle } from "../math/math3d";
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
	setLightCookie,
	closeScene,
} from "../void3d/scene";
import { DrawContext, DrawItem } from "../void3d/draw";
import { TextureId, NO_TEXTURE } from "../void3d/texture";
import {
	LIGHT_COOKIE,
	LIGHT_UNIFORM_LENGTH,
	LIGHT_RECORD_SHAPE,
	VERTEX_UNIFORM_LENGTH,
} from "../void3d/gpu3d";
import { CameraView } from "../void3d/camera";
import { spotShadowView, SpotShadowError } from "../void3d/spotShadow";
import { ClusterLight } from "../void3d/clusters";
import { clusterLightsOf } from "../void3d/clusterFrame";
import {
	Renderer, RendererError, RENDERER_UNIFORM_LENGTH, beginFrame, cookieMapOf,
} from "../void3d/renderer";
import { LitBindings, cookieAt, recordCookieAt, litFs } from "../void3d/shader3d";
import { oneLayer } from "./shadowHelpers";
import { SceneLights, recordsOf, sceneLights } from "./lightHelpers";

const NO_SHAPE: LightShape = {
	angle: 0.0, verticalAngle: 0.0, falloff: 0.0, width: 0.0, height: 0.0, length: 0.0,
	capsuleRadius: 0.0,
};
const RIGHT_ANGLE: float32 = 1.5707963268;
const UNIT: Vec3 = vec3(1, 1, 1);
const DOWN: Quat = axisAngle(vec3(1, 0, 0), RIGHT_ANGLE);
const COOKIE: TextureId = { store: 3, index: 5, generation: 7 };
const NONE: Vec4f = vec4f(0.0, 0.0, 0.0, 0.0);

function near(a: float32, b: float32, tolerance: float32 = 1e-4): boolean {
	return Math.abs(a - b) <= tolerance;
}

function lightOf(kind: LightKind, cookie: TextureId): LightInstance {
	return {
		kind: kind, color: vec3(1, 1, 1), radius: 8, power: 1, priority: 0,
		shape: { ...NO_SHAPE, angle: RIGHT_ANGLE }, cookie: cookie,
	};
}

function place(scene: Scene3D, light: LightInstance, position: Vec3): NodeId3D {
	return addLightNode(scene, scene.rootId(),
		{ position: position, rotation: DOWN, scale: UNIT }, light);
}

function errorOf(result: Result<int32, LightError>): LightError | null {
	return result.ok ? null : result.error;
}

// A plain spot, then a spot four above the origin pointing down whose cookie is `cookie`.
function cookieSpots(cookie: TextureId): Vec<float32> {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	place(scene, lightOf(LightKind.Spot, NO_TEXTURE), vec3(6, 4, 0));
	place(scene, lightOf(LightKind.Spot, cookie), vec3(0, 4, 0));
	let values: Vec<float32> = [];
	if (errorOf(collectLights(scene, values)) !== null) { unreachable; }
	return move values;
}

test "the light block names the cookie spot and its texture, and leaves them zero without one" {
	const lit: Vec<float32> = cookieSpots(COOKIE);
	assert lit[LIGHT_COOKIE] == 2.0;
	assert lit[LIGHT_COOKIE + 1] == 3.0 && lit[LIGHT_COOKIE + 2] == 5.0 &&
		lit[LIGHT_COOKIE + 3] == 7.0;
	const plain: Vec<float32> = cookieSpots(NO_TEXTURE);
	for (let i = 0; i < 4; i++) { assert plain[LIGHT_COOKIE + i] == 0.0; }
}

test "a cookie off a spot, a second cookie spot and an id past float are refused by name" {
	const kinds: Vec<LightKind> = [LightKind.Directional, LightKind.Point];
	for (const kind of kinds) {
		const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
		defer closeScene(scene);
		const id: NodeId3D = place(scene, lightOf(kind, NO_TEXTURE), vec3(0, 4, 0));
		let values: Vec<float32> = [];
		assert errorOf(collectLights(scene, values)) === null;
		setLightCookie(scene, id, COOKIE);
		assert errorOf(collectLights(scene, values)) == LightError.UncookableLight;
		setLightCookie(scene, id, NO_TEXTURE);
		assert errorOf(collectLights(scene, values)) === null;
	}
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	const first: NodeId3D = place(scene, lightOf(LightKind.Spot, COOKIE), vec3(0, 4, 0));
	const second: NodeId3D = place(scene, lightOf(LightKind.Spot, NO_TEXTURE), vec3(2, 4, 0));
	let values: Vec<float32> = [];
	assert errorOf(collectLights(scene, values)) === null;
	setLightCookie(scene, second, COOKIE);
	assert errorOf(collectLights(scene, values)) == LightError.TooManyCookieSpots;
	setLightCookie(scene, second, NO_TEXTURE);
	setLightCookie(scene, first, { store: 3, index: 5, generation: 16777217 });
	assert errorOf(collectLights(scene, values)) == LightError.CookieIdPastFloat;
	setLightCookie(scene, first, { store: 3, index: 5, generation: 16777216 });
	assert errorOf(collectLights(scene, values)) === null;
}

test "the cookie spot clusters by the cone through its pyramid's corners, the others by their own" {
	const values: Vec<float32> = cookieSpots(COOKIE);
	const lights: Vec<ClusterLight> = clusterLightsOf(values, 2);
	const half: float32 = RIGHT_ANGLE * 0.5;
	assert near(lights[0].outerHalfAngle, half);
	const corner: float32 = Math.atan(Math.SQRT2 * Math.tan(half as float64)) as float32;
	assert near(lights[1].outerHalfAngle, corner) && lights[1].outerHalfAngle > half;
	const plain: Vec<ClusterLight> = clusterLightsOf(cookieSpots(NO_TEXTURE), 2);
	assert near(plain[1].outerHalfAngle, half);
}

function asMat4x4f(m: Mat4): Mat4x4f {
	return mat4x4f(
		vec4f(m.m11, m.m12, m.m13, m.m14), vec4f(m.m21, m.m22, m.m23, m.m24),
		vec4f(m.m31, m.m32, m.m33, m.m34), vec4f(m.m41, m.m42, m.m43, m.m44),
	);
}

function cookieView(values: Vec<float32>): CameraView {
	const view: Result<CameraView, SpotShadowError> = spotShadowView(values, 1);
	if (!view.ok) { unreachable; }
	return view.value;
}

function uvOf(m: Mat4, p: Vec3): Vec3 {
	const x: float32 = p.x * m.m11 + p.y * m.m21 + p.z * m.m31 + m.m41;
	const y: float32 = p.x * m.m12 + p.y * m.m22 + p.z * m.m32 + m.m42;
	const w: float32 = p.x * m.m14 + p.y * m.m24 + p.z * m.m34 + m.m44;
	return vec3(x / w, y / w, w);
}

test "the cookie map takes the spot's axis to the middle and its pyramid's edges to the borders" {
	const values: Vec<float32> = cookieSpots(COOKIE);
	const map: Mat4 = cookieMapOf(cookieView(values));
	const middle: Vec3 = uvOf(map, vec3(0, 0, 0));
	assert near(middle.x, 0.5) && near(middle.y, 0.5) && middle.z > 0.0;
	const xEdge: Vec3 = uvOf(map, vec3(4, 0, 0));
	const zEdge: Vec3 = uvOf(map, vec3(0, 0, 4));
	const xBorder: boolean = near(xEdge.x, 0.0) || near(xEdge.x, 1.0) ||
		near(xEdge.y, 0.0) || near(xEdge.y, 1.0);
	const zBorder: boolean = near(zEdge.x, 0.0) || near(zEdge.x, 1.0) ||
		near(zEdge.y, 0.0) || near(zEdge.y, 1.0);
	assert xBorder && zBorder;
}

// Red, green at half alpha, blue, then white at no alpha, row by row from the top.
function quadrants(): Texture2d {
	return {
		width: 2, height: 2,
		texels: [1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.5, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0],
	};
}

function flat(r: float32, g: float32, b: float32, a: float32): Texture2d {
	return { width: 1, height: 1, texels: [r, g, b, a] };
}

function cookieLights(values: Vec<float32>, cookie: Texture2d): LitBindings {
	const lights: SceneLights = sceneLights(NONE, NONE, NONE, recordsOf(values));
	const map: Mat4 = cookieMapOf(cookieView(values));
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
		lightParams: {
			...lights.lightParams,
			cookie: vec4f(values[LIGHT_COOKIE], 0.0, 0.0, 0.0),
			cookieMatrix: asMat4x4f(map),
		},
		lightRecords: lights.lightRecords,
		clusterRecords: lights.clusterRecords,
		clusterIndices: lights.clusterIndices,
		clusterSampler: lights.clusterSampler,
		frameParams: {
			frame: vec4f(0.0, 1.0, 0.0, 0.0),
			cameraPosition: vec4f(0.0, 5.0, 1.0, 1.0),
		},
		shadowMap: oneLayer(flat(1.0, 1.0, 1.0, 1.0)),
		shadowSampler: { nearest: true },
		spotShadowMap: oneLayer(flat(1.0, 1.0, 1.0, 1.0)),
		spotShadowSampler: { nearest: true },
		cubeShadowMap: oneLayer(flat(1.0, 1.0, 1.0, 1.0)),
		baseTexture: flat(1.0, 1.0, 1.0, 1.0),
		baseSampler: { nearest: true },
		backTexture: flat(1.0, 1.0, 1.0, 1.0),
		dissolveTexture: flat(1.0, 1.0, 1.0, 1.0),
		emissiveTexture: flat(1.0, 1.0, 1.0, 1.0),
		normalTexture: flat(1.0, 1.0, 1.0, 1.0),
		metalRoughTexture: flat(1.0, 1.0, 1.0, 1.0),
		occlusionTexture: flat(1.0, 1.0, 1.0, 1.0),
		cookieTexture: cookie,
		cookieSampler: { nearest: true },
		envDiffuse: { size: 0, texels: [] }, envSpecular: { size: 0, texels: [] },
	};
}

function texelOf(texture: Texture2d, uv: Vec3): Vec3f {
	const x: int32 = uv.x < 0.5 ? 0 : 1;
	const y: int32 = uv.y < 0.5 ? 0 : 1;
	const at: int32 = (y * 2 + x) * 4;
	const a: float32 = texture.texels[at + 3];
	return vec3f(texture.texels[at] * a, texture.texels[at + 1] * a, texture.texels[at + 2] * a);
}

function same(a: Vec3f, b: Vec3f): boolean {
	return near(a.x, b.x) && near(a.y, b.y) && near(a.z, b.z);
}

test "the cookie gives its texel's colour times alpha, and nothing past its map or behind it" {
	const values: Vec<float32> = cookieSpots(COOKIE);
	const b: LitBindings = cookieLights(values, quadrants());
	const map: Mat4 = cookieMapOf(cookieView(values));
	const points: Vec<Vec3> = [vec3(1, 0, 1), vec3(-1, 0, 1), vec3(1, 0, -1), vec3(-1, 0, -1)];
	let seen: int32 = 0;
	for (const p of points) {
		const got: Vec3f = cookieAt(vec3f(p.x, p.y, p.z), b);
		assert same(got, texelOf(quadrants(), uvOf(map, p)));
		if (got.x > 0.5) { seen = seen | 1; }
		if (got.y > 0.25 && got.y < 0.75) { seen = seen | 2; }
		if (got.z > 0.5) { seen = seen | 4; }
		if (got.x == 0.0 && got.y == 0.0 && got.z == 0.0) { seen = seen | 8; }
	}
	assert seen == 15;
	assert same(cookieAt(vec3f(5.0, 0.0, 0.0), b), vec3f(0.0, 0.0, 0.0));
	assert same(cookieAt(vec3f(0.5, 6.0, 0.5), b), vec3f(0.0, 0.0, 0.0));
}

test "only the record the light block names reads the cookie" {
	const values: Vec<float32> = cookieSpots(COOKIE);
	const b: LitBindings = cookieLights(values, flat(1.0, 0.0, 0.0, 1.0));
	const p: Vec3f = vec3f(0.5, 0.0, 0.5);
	const named: Vec4f = recordCookieAt(p, b, 1);
	assert named.w == 1.0 && named.x == 1.0 && named.y == 0.0;
	const other: Vec4f = recordCookieAt(p, b, 0);
	assert other.w == 0.0 && other.x == 1.0 && other.y == 1.0 && other.z == 1.0;
}

function surface(b: LitBindings, at: Vec3f, pbr: boolean): Vec3f {
	return litFs({
		worldPosition: at,
		worldNormal: vec3f(0.0, 1.0, 0.0),
		baseColor: vec4f(1.0, 1.0, 1.0, 1.0),
		frontFacing: true,
	}, b, { pbr: pbr, shadowed: false }).color.rgb;
}

test "a cookie spot tints by its cookie and lights its pyramid's corners past the cone" {
	const values: Vec<float32> = cookieSpots(COOKIE);
	const red: LitBindings = cookieLights(values, flat(1.0, 0.0, 0.0, 1.0));
	const clear: LitBindings = cookieLights(values, flat(1.0, 1.0, 1.0, 0.0));
	const plain: LitBindings = { ...red, lightParams: { ...red.lightParams, cookie: NONE } };
	const inside: Vec3f = vec3f(0.5, 0.0, 0.5);
	const corner: Vec3f = vec3f(3.2, 0.0, 3.2);
	const modes: Vec<boolean> = [false, true];
	for (const pbr of modes) {
		const tinted: Vec3f = surface(red, inside, pbr);
		assert tinted.x > 0.0 && tinted.y == 0.0 && tinted.z == 0.0;
		const none: Vec3f = surface(clear, inside, pbr);
		assert none.x == 0.0 && none.y == 0.0 && none.z == 0.0;
		assert surface(red, corner, pbr).x > 0.0;
		assert surface(plain, corner, pbr).x == 0.0;
		const cone: Vec3f = surface(plain, inside, pbr);
		assert cone.y > 0.0;
	}
}

function refusalOf(lights: Vec<float32>): RendererError | null {
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	if (!created.ok) { unreachable; }
	let core: Renderer = created.value;
	const items: Vec<DrawItem> = [];
	const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	const began: Result<boolean, RendererError> = beginFrame(core, items, camera, lights);
	return began.ok ? null : began.error;
}

test "a frame whose cookie names no spot record or no live texture is refused before it writes" {
	assert refusalOf(cookieSpots(COOKIE)) == RendererError.StaleCookie;
	let past: Vec<float32> = cookieSpots(COOKIE);
	past[LIGHT_COOKIE] = 3.0;
	assert refusalOf(past) == RendererError.BadCookieSpot;
	let point: Vec<float32> = cookieSpots(COOKIE);
	point[LIGHT_UNIFORM_LENGTH + LIGHT_RECORD_SHAPE + 3] = 0.0;
	point[LIGHT_COOKIE] = 1.0;
	assert refusalOf(point) == RendererError.BadCookieSpot;
}
