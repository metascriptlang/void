import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3 } from "../../src/math/math3d";
import { FilterMode, Wrap } from "../../src/gpu/state";
import { Material, MaterialKind, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addTexturedQuad } from "../../src/void3d/meshData";
import { TextureData, TextureId, TextureUploadError } from "../../src/void3d/texture";
import {
	Program, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MeshUploadError, MaterialError,
	addMeshData, addMaterial, addTexture, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, LightError, addMeshNode, refresh, collectLights,
} from "../../src/void3d/scene";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH, renderFrame as renderForward,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer, PixelArtError, PixelArtSettings, PixelArtLook, PIXEL_ART_UNIFORM_LENGTH,
	renderFrame as renderPixelArt,
} from "../../src/void3d/pixelArtRenderer";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureEnvInt, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const HALF: float32 = 0.6;
const WORLD_PER_TEXEL: float32 = 0.02;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const RED: Vec4 = { x: 1.0, y: 0.0, z: 0.0, w: 1.0 };
const GREEN: Vec4 = { x: 0.0, y: 1.0, z: 0.0, w: 1.0 };
const HALF_RED: Vec4 = { x: 1.0, y: 0.0, z: 0.0, w: 0.5 };
const HALF_GREEN: Vec4 = { x: 0.0, y: 1.0, z: 0.0, w: 0.5 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const OPAQUE_X: float32 = -1.0;
const ALPHA_X: float32 = 1.0;
const FRAMES: int32 = 3;
let pixelArt: boolean = voidCaptureEnvInt("VOID_SORT_LAYER_PIXEL_ART", 0) != 0;
let control: boolean = voidCaptureEnvInt("VOID_SORT_LAYER_CONTROL", 0) != 0;
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + 4 * UNLIT_MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let preset: PixelArtRenderer = makePreset();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;

function fail(message: string): void {
	const preset: string = pixelArt ? "pixel-art" : "forward";
	console.log(`FAIL sort layer: ${preset} stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, GREY);
	if (made.ok) { return made.value; }
	unreachable;
}

function makePreset(): PixelArtRenderer {
	const settings: PixelArtSettings = {
		...PixelArtSettings.full(), lowResShortSide: HEIGHT, postPass: false,
	};
	const look: PixelArtLook = {
		background: GREY,
		outline: {
			depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35,
		},
		fog: { start: 1.0, end: 1.0, strength: 0.0, color: GREY },
		saturation: 0.0,
	};
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, settings, look);
	if (made.ok) { return made.value; }
	unreachable;
}

function white(): TextureId {
	const data: TextureData = {
		pixels: [0xFFFFFFFF], width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

// Alpha here leaves depth unwritten, through the material's own pass, so a later layer can
// draw over a nearer quad.
function material(kind: MaterialKind, color: Vec4, layer: int32, image: TextureId): MaterialId {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	const values: Vec<float32> = [0.0, 0.0, 0.0, 0.0, color.x, color.y, color.z, color.w];
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	const base: Material = Material.ofKind(Program.UnlitTextured, kind);
	const pass = kind == MaterialKind.Alpha ?
		base.pass.withDepth(false, base.pass.depthTest) :
		base.pass;
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...base, pass: pass, texture: image, uniforms: reserved.value,
		layer: control ? 0 : layer,
	});
	if (added.ok) { return added.value; }
	fail(`a material was refused: ${added.error.toString()}`);
	unreachable;
}

function quad(x: float32, z: float32, made: MaterialId): void {
	let mesh: MeshData = MeshData.withUvs();
	const built: Result<int32, MeshError> = addTexturedQuad(
		mesh, vec3(-HALF, -HALF, 0.0), vec3(HALF, -HALF, 0.0),
		vec3(HALF, HALF, 0.0), vec3(-HALF, HALF, 0.0), vec3(0.0, 0.0, 1.0), WHITE,
	);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (!uploaded.ok) { unreachable; }
	const at: Transform3D = Transform3D.fromTranslation(vec3(x, 0.0, z));
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, scene.rootId(), at, uploaded.value, made);
	if (!placed.ok) { unreachable; }
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	const image: TextureId = white();
	quad(OPAQUE_X, 0.0, material(MaterialKind.Opaque, RED, 0, image));
	quad(OPAQUE_X, 0.0, material(MaterialKind.Opaque, GREEN, -1, image));
	quad(ALPHA_X, 0.0, material(MaterialKind.Alpha, HALF_RED, 0, image));
	quad(ALPHA_X, -0.5, material(MaterialKind.Alpha, HALF_GREEN, 1, image));
}

function viewOf(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 0.0, 4.0), yaw: 0.0, pitch: 0.0,
		nearPlane: 0.1, farPlane: 10.0,
		projection: {
			kind: ProjectionKind.Orthographic, worldPerTexel: WORLD_PER_TEXEL, snap: false,
		},
	};
	const view: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	unreachable;
}

function pixelAt(view: CameraView, x: float32): int64 {
	const at: Vec3 = view.project(vec3(x, 0.0, 0.0), SCREEN, true);
	return voidCapturePixel(0, at.x as int32, at.y as int32);
}

function red(pixel: int64): int64 { return (pixel >> 24) & 255; }
function green(pixel: int64): int64 { return (pixel >> 16) & 255; }

// Lower layers first: the green opaque quad (layer -1) draws first and keeps the equal depth;
// the far green alpha quad (layer 1) draws last, over the near red one.
function check(view: CameraView): void {
	const opaque: int64 = pixelAt(view, OPAQUE_X);
	const alpha: int64 = pixelAt(view, ALPHA_X);
	console.log(`sort layer: opaque ${opaque}, alpha ${alpha}`);
	let failures: string = "";
	if (green(opaque) != 255 || red(opaque) != 0) {
		failures = failures + ` the layer -1 opaque quad did not draw first: ${opaque};`;
	}
	if (green(alpha) <= red(alpha)) {
		failures = failures + ` the far layer 1 alpha quad did not draw last: ${alpha};`;
	}
	if (failures.length > 0) { fail(failures); }
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	if (refresh(scene, items) != 4) { fail("the scene does not draw its four quads"); }
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { unreachable; }
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	if (pixelArt) {
		const drawn: Result<int32, PixelArtError> =
			renderPixelArt(preset, items, cameraValues, lights, SCREEN);
		if (!drawn.ok) { fail(`pixel-art refused: ${drawn.error.toString()}`); }
	} else {
		const drawn: Result<int32, ForwardError> =
			renderForward(forward, items, cameraValues, lights, WIDTH, HEIGHT);
		if (!drawn.ok) { fail(`forward refused: ${drawn.error.toString()}`); }
	}
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	check(view);
	stage = stage + 1;
	if (stage < FRAMES) { return; }
	console.log("PASS sort layer: lower layers draw first in the opaque and alpha lists");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
