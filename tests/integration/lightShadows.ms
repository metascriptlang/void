import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, Quat, vec3, axisAngle } from "../../src/math/math3d";
import { Material, MaterialKind, ShadowCasting, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addQuad } from "../../src/void3d/meshData";
import {
	Program, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MeshUploadError, MaterialError,
	addMeshData, addMaterial, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, LightKind, LightInstance, LightError, LightShape,
	addMeshNode, addLightNode, setAmbient, refresh, collectLights,
} from "../../src/void3d/scene";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import {
	attachSpotShadow, attachCubeShadow, setCameraView, setCameraPosition,
} from "../../src/void3d/renderer";
import {
	DirShadowMap, ShadowError, ShadowSamplingKind, DIR_SHADOW_UNIFORM_LENGTH,
} from "../../src/void3d/dirShadowMap";
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

// The light above the caster; a spot draws the spot map, the others the cube map.
enum Case {
	Spot,
	Point,
	Rectangle,
	Capsule,
}

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const WORLD_PER_TEXEL: float32 = 0.02;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const RED: Rgba = { red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const GROUND_HALF: float32 = 3.0;
const CASTER_HALF: float32 = 0.5;
const CASTER_HEIGHT: float32 = 1.0;
// From the light 3 above the ground, the caster's half of 0.5 at height 1 shades a square of
// half 0.75 around the origin.
const LIGHT_HEIGHT: float32 = 3.0;
const SHADOW_SIZE: int32 = 512;
const NORMAL_BIAS: float32 = 50.0;
const RIM: Vec3 = { x: 0.0, y: 0.0, z: 0.65 };
const FRAMES: int32 = 3;
const RIGHT_ANGLE: float32 = 1.5707963268;
const DOWN: Quat = axisAngle(vec3(1.0, 0.0, 0.0), RIGHT_ANGLE);
let lightCase: Case = voidCaptureEnvInt("VOID_LIGHT_SHADOW_CASE", 0) as Case;
let pcf: boolean = voidCaptureEnvInt("VOID_LIGHT_SHADOW_PCF", 0) != 0;
let control: boolean = voidCaptureEnvInt("VOID_LIGHT_SHADOW_CONTROL", 0) != 0;
let biased: boolean = voidCaptureEnvInt("VOID_LIGHT_SHADOW_NORMAL_BIAS", 0) != 0;
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + 2 * DIR_SHADOW_UNIFORM_LENGTH + 2 * MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let spotMap: DirShadowMap = makeMap(true);
let cubeMap: DirShadowMap = makeMap(false);
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;

function fail(message: string): void {
	const mode: string = (pcf ? " pcf" : "") + (control ? " control" : "") +
		(biased ? " normal bias" : "");
	console.log(`FAIL light shadow: ${lightCase.toString()}${mode} stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, GREY);
	if (made.ok) { return made.value; }
	unreachable;
}

function makeMap(spot: boolean): DirShadowMap {
	const made: Result<DirShadowMap, ShadowError> = spot ?
		DirShadowMap.createSpot(context, SHADOW_SIZE) :
		DirShadowMap.createCube(context, SHADOW_SIZE);
	if (made.ok) { return made.value; }
	unreachable;
}

function material(): MaterialId {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	const values: Vec<float32> = [4.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	const base: Material = Material.ofKind(Program.Lit, MaterialKind.Opaque)
		.withShadows(ShadowCasting.On, true);
	const added: Result<MaterialId, MaterialError> =
		addMaterial(context, { ...base, uniforms: reserved.value });
	if (added.ok) { return added.value; }
	fail(`a material was refused: ${added.error.toString()}`);
	unreachable;
}

function horizontal(half: float32, y: float32, color: Rgba, made: MaterialId): void {
	let mesh: MeshData = MeshData.empty();
	const built: Result<int32, MeshError> = addQuad(
		mesh, vec3(-half, y, half), vec3(half, y, half), vec3(half, y, -half),
		vec3(-half, y, -half), vec3(0.0, 1.0, 0.0), color,
	);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (!uploaded.ok) { unreachable; }
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, scene.rootId(), Transform3D.identity(), uploaded.value, made);
	if (!placed.ok) { unreachable; }
}

function kindOf(): LightKind {
	return match (lightCase) {
		Case.Spot => LightKind.Spot,
		Case.Point => LightKind.Point,
		Case.Rectangle => LightKind.Rectangle,
		Case.Capsule => LightKind.Capsule,
	};
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	const made: MaterialId = material();
	horizontal(GROUND_HALF, 0.0, WHITE, made);
	horizontal(CASTER_HALF, CASTER_HEIGHT, RED, made);
	const shape: LightShape = {
		angle: RIGHT_ANGLE, verticalAngle: RIGHT_ANGLE, falloff: 0.0, width: 0.5, height: 0.5,
		length: 0.5, capsuleRadius: 0.1,
	};
	const light: LightInstance = {
		kind: kindOf(), color: vec3(1.0, 1.0, 1.0), radius: 8.0, power: 1.0, priority: 0,
		shape: shape, shadows: !control,
	};
	const _light: NodeId3D = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(), position: vec3(0.0, LIGHT_HEIGHT, 0.0), rotation: DOWN,
	}, light);
	setAmbient(scene, vec3(0.3, 0.3, 0.3));
	const sampling: ShadowSamplingKind = pcf ? ShadowSamplingKind.Pcf : ShadowSamplingKind.None;
	spotMap.samplingKind = sampling;
	cubeMap.samplingKind = sampling;
	if (biased) {
		spotMap.normalBias = NORMAL_BIAS;
		cubeMap.normalBias = NORMAL_BIAS;
	}
	attachSpotShadow(forward.core, spotMap);
	attachCubeShadow(forward.core, cubeMap);
}

function viewOf(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 4.0, 4.0), yaw: 0.0, pitch: 0.785398,
		nearPlane: 0.1, farPlane: 20.0,
		projection: {
			kind: ProjectionKind.Orthographic, worldPerTexel: WORLD_PER_TEXEL, snap: false,
		},
	};
	const view: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	unreachable;
}

function greenAt(view: CameraView, point: Vec3): int64 {
	const at: Vec3 = view.project(point, SCREEN, true);
	return (voidCapturePixel(0, at.x as int32, at.y as int32) >> 16) & 0xFF;
}

// The ground straight under the light is nearer it than the open ground, so it is the brighter
// one unless the caster shades it.
function check(view: CameraView): void {
	const under: int64 = greenAt(view, vec3(0.0, 0.0, 0.0));
	const edge: int64 = greenAt(view, vec3(0.0, 0.0, 0.6));
	const open: int64 = greenAt(view, vec3(1.5, 0.0, 0.0));
	const top: int64 = greenAt(view, vec3(0.0, CASTER_HEIGHT, 0.0));
	const rim: int64 = greenAt(view, RIM);
	console.log(`light shadow: under ${under}, edge ${edge}, rim ${rim}, open ${open}, ` +
		`caster top ${top}`);
	if (top > 60) { fail(`the caster drew green ${top}, not red`); }
	if (control) {
		if (under < open) { fail(`unshadowed, the ground under the light drew ${under}`); }
		return;
	}
	if (under + 30 > open) { fail(`no shadow under the caster: ${under} against ${open}`); }
	if (biased) {
		if (rim + 30 <= open) { fail(`the normal bias left the rim shadowed: ${rim}`); }
		return;
	}
	if (edge + 30 > open) { fail(`no shadow inside the footprint's edge: ${edge}`); }
	if (rim + 30 > open) { fail(`no shadow at the rim: ${rim}`); }
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	if (refresh(scene, items) != 2) { fail("the scene lost its meshes"); }
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { fail(`the lights were refused: ${collected.error.toString()}`); }
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	setCameraView(forward.core, view);
	setCameraPosition(forward.core, vec3(0.0, 4.0, 4.0));
	const drawn: Result<int32, ForwardError> =
		renderForward(forward, items, cameraValues, lights, WIDTH, HEIGHT);
	if (!drawn.ok) { fail(`forward refused: ${drawn.error.toString()}`); }
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	check(view);
	stage = stage + 1;
	if (stage < FRAMES) { return; }
	console.log(`PASS light shadow: ${lightCase.toString()}`);
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
