import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { FilterMode, Wrap } from "../../src/gpu/state";
import { Mat4, Vec3, Vec4, Quat, vec3, axisAngle } from "../../src/math/math3d";
import { Material, MaterialKind, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addQuad } from "../../src/void3d/meshData";
import { TextureData, TextureId, TextureUploadError } from "../../src/void3d/texture";
import {
	Program, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MeshUploadError, MaterialError,
	addMeshData, addMaterial, addTexture, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, LightKind, LightInstance, LightError, LightShape,
	addMeshNode, addLightNode, setAmbient, setLightCookie, refresh, collectLights,
} from "../../src/void3d/scene";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import { spotShadowView, SpotShadowError } from "../../src/void3d/spotShadow";
import { setCameraView, setCameraPosition, cookieMapOf } from "../../src/void3d/renderer";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH, renderFrame as renderForward,
} from "../../src/void3d/forwardRenderer";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureEnvInt, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

// A spot 3 above white ground, pointing down with a 90-degree cone, through a 2x2 cookie. The
// control draws the same spot without one.
const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const WORLD_PER_TEXEL: float32 = 0.04;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const GROUND_HALF: float32 = 4.0;
const LIGHT_HEIGHT: float32 = 3.0;
const FRAMES: int32 = 3;
const RIGHT_ANGLE: float32 = 1.5707963268;
const DOWN: Quat = axisAngle(vec3(1.0, 0.0, 0.0), RIGHT_ANGLE);
// Red, green, blue, white, row by row from the image's top, 0xAABBGGRR.
const COOKIE_TEXELS: Vec<uint32> = [0xFF0000FF, 0xFF00FF00, 0xFFFF0000, 0xFFFFFFFF];
// Each sample sits in one quadrant of the window; the corner sits in the pyramid outside the
// cone, 3.68 from the axis where the cone reaches 3; the far point sits outside the window.
const SAMPLES: Vec<Vec3> = [
	{ x: -1.5, y: 0.0, z: -1.5 }, { x: 1.5, y: 0.0, z: -1.5 },
	{ x: -1.5, y: 0.0, z: 1.5 }, { x: 1.5, y: 0.0, z: 1.5 },
];
const CORNER: Vec3 = { x: 2.6, y: 0.0, z: 2.6 };
const OUTSIDE: Vec3 = { x: 3.6, y: 0.0, z: 0.0 };
let control: boolean = voidCaptureEnvInt("VOID_SPOT_COOKIE_CONTROL", 0) != 0;
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;

function fail(message: string): void {
	const mode: string = control ? " control" : "";
	console.log(`FAIL spot cookie${mode} stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, GREY);
	if (made.ok) { return made.value; }
	unreachable;
}

function material(): MaterialId {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	const values: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	const base: Material = Material.ofKind(Program.Lit, MaterialKind.Opaque);
	const added: Result<MaterialId, MaterialError> =
		addMaterial(context, { ...base, uniforms: reserved.value });
	if (added.ok) { return added.value; }
	fail(`the material was refused: ${added.error.toString()}`);
	unreachable;
}

function ground(made: MaterialId): void {
	let mesh: MeshData = MeshData.empty();
	const built: Result<int32, MeshError> = addQuad(
		mesh, vec3(-GROUND_HALF, 0.0, GROUND_HALF), vec3(GROUND_HALF, 0.0, GROUND_HALF),
		vec3(GROUND_HALF, 0.0, -GROUND_HALF), vec3(-GROUND_HALF, 0.0, -GROUND_HALF),
		vec3(0.0, 1.0, 0.0), WHITE,
	);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (!uploaded.ok) { unreachable; }
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, scene.rootId(), Transform3D.identity(), uploaded.value, made);
	if (!placed.ok) { unreachable; }
}

function cookie(): TextureId {
	const data: TextureData = {
		pixels: COOKIE_TEXELS, width: 2, height: 2, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (uploaded.ok) { return uploaded.value; }
	fail(`the cookie was refused: ${uploaded.error.toString()}`);
	unreachable;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	ground(material());
	const shape: LightShape = {
		angle: RIGHT_ANGLE, verticalAngle: RIGHT_ANGLE, falloff: 0.0, width: 0.5, height: 0.5,
		length: 0.5, capsuleRadius: 0.1,
	};
	const light: LightInstance = {
		kind: LightKind.Spot, color: vec3(1.0, 1.0, 1.0), radius: 8.0, power: 2.0, priority: 0,
		shape: shape, shadows: false,
	};
	const spot: NodeId3D = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(), position: vec3(0.0, LIGHT_HEIGHT, 0.0), rotation: DOWN,
	}, light);
	if (!control) { setLightCookie(scene, spot, cookie()); }
	setAmbient(scene, vec3(0.0, 0.0, 0.0));
}

function viewOf(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 6.0, 6.0), yaw: 0.0, pitch: 0.785398,
		nearPlane: 0.1, farPlane: 30.0,
		projection: {
			kind: ProjectionKind.Orthographic, worldPerTexel: WORLD_PER_TEXEL, snap: false,
		},
	};
	const view: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	unreachable;
}

function pixelAt(view: CameraView, point: Vec3): int64 {
	const at: Vec3 = view.project(point, SCREEN, true);
	return voidCapturePixel(0, at.x as int32, at.y as int32);
}

function channels(pixel: int64): string {
	return `${(pixel >> 24) & 0xFF},${(pixel >> 16) & 0xFF},${(pixel >> 8) & 0xFF}`;
}

// The texel the CPU map sends `point` to, by the same uv the shader takes.
function texelAt(map: Mat4, point: Vec3): int32 {
	const x: float32 = point.x * map.m11 + point.y * map.m21 + point.z * map.m31 + map.m41;
	const y: float32 = point.x * map.m12 + point.y * map.m22 + point.z * map.m32 + map.m42;
	const w: float32 = point.x * map.m14 + point.y * map.m24 + point.z * map.m34 + map.m44;
	const column: int32 = x / w < 0.5 ? 0 : 1;
	const row: int32 = y / w < 0.5 ? 0 : 1;
	return row * 2 + column;
}

// Red, green or blue drawn alone, or all three for white, each lit above the ambient.
function shows(pixel: int64, texel: int32): boolean {
	const red: int64 = (pixel >> 24) & 0xFF;
	const green: int64 = (pixel >> 16) & 0xFF;
	const blue: int64 = (pixel >> 8) & 0xFF;
	const lit: int64 = 60;
	const dark: int64 = 30;
	return match (texel) {
		0 => red > lit && green < dark && blue < dark,
		1 => green > lit && red < dark && blue < dark,
		2 => blue > lit && red < dark && green < dark,
		_ => red > lit && green > lit && blue > lit,
	};
}

function brightness(pixel: int64): int64 {
	return ((pixel >> 24) & 0xFF) + ((pixel >> 16) & 0xFF) + ((pixel >> 8) & 0xFF);
}

function check(view: CameraView): void {
	const spot: Result<CameraView, SpotShadowError> = spotShadowView(lights, 0);
	if (!spot.ok) {
		fail(`the spot has no light camera: ${spot.error.toString()}`);
		return;
	}
	const map: Mat4 = cookieMapOf(spot.value);
	let seen: int32 = 0;
	for (const sample of SAMPLES) {
		const pixel: int64 = pixelAt(view, sample);
		const texel: int32 = texelAt(map, sample);
		const at: string = `(${sample.x}, ${sample.z})`;
		console.log(`spot cookie: ${at} texel ${texel} drew ${channels(pixel)}`);
		if (control) {
			if (!shows(pixel, 3)) { fail(`without a cookie ${at} is not white`); }
		} else if (!shows(pixel, texel)) {
			fail(`${at} did not draw texel ${texel}`);
		}
		seen = seen | (1 << texel);
	}
	if (seen != 15) { fail(`the samples reach texels ${seen}, not all four`); }
	const corner: int64 = pixelAt(view, CORNER);
	const outside: int64 = pixelAt(view, OUTSIDE);
	console.log(`spot cookie: corner ${channels(corner)}, outside ${channels(outside)}`);
	if (control) {
		if (brightness(corner) > brightness(outside) + 30) {
			fail("without a cookie the cone lit the corner past it");
		}
	} else {
		if (!shows(corner, texelAt(map, CORNER))) { fail("the cookie left the corner dark"); }
		if (brightness(outside) > 30) { fail("the cookie lit past its window"); }
	}
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	if (refresh(scene, items) != 1) { fail("the scene lost its mesh"); }
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { fail(`the lights were refused: ${collected.error.toString()}`); }
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	setCameraView(forward.core, view);
	setCameraPosition(forward.core, vec3(0.0, 6.0, 6.0));
	const drawn: Result<int32, ForwardError> =
		renderForward(forward, items, cameraValues, lights, WIDTH, HEIGHT);
	if (!drawn.ok) { fail(`forward refused: ${drawn.error.toString()}`); }
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	check(view);
	stage = stage + 1;
	if (stage < FRAMES) { return; }
	console.log(`PASS spot cookie${control ? " control" : ""}`);
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
