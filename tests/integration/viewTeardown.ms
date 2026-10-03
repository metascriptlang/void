import { readFile } from "std/fs";
import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3 } from "../../src/math/math3d";
import { RenderState } from "../../src/gpu/state";
import { beginScreenPass } from "../../src/gpu/target";
import {
	endPass,
	commit,
	contextGeneration,
	liveBuffers,
	liveImages,
	liveViews,
	liveSamplers,
	liveShaders,
	livePipelines,
} from "../../src/gpu/door";
import {
	MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import { UniformPool } from "../../src/void3d/uniformPool";
import { DrawContext, DrawItem, closeContext } from "../../src/void3d/draw";
import { GltfData, GltfError, loadGlb } from "../../src/void3d/gltf";
import {
	GltfAssets,
	GltfSceneError,
	addGltfAssets,
	addGltfNodes,
	closeGltfAssets,
} from "../../src/void3d/gltfScene";
import {
	Transform3D,
	Scene3D,
	LightError,
	addGroup,
	closeScene,
	setAmbient,
	refresh,
	collectLights,
} from "../../src/void3d/scene";
import { Camera3D, ProjectionKind, CameraView, CameraError } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import { upload } from "../../src/void3d/palette";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	prepareFrame as prepareForward,
	drawToScreen as forwardToScreen,
	closeForward,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	prepareFrame as preparePixelArt,
	drawToScreen as pixelArtToScreen,
	closePixelArt,
} from "../../src/void3d/pixelArtRenderer";
import {
	voidCaptureBackend,
	voidCaptureGrab,
	voidCapturePixel,
	voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

let FIXTURE: string = "tests/fixtures/gltf/texturedScene.glb";
let WIDTH: int32 = 320;
let HEIGHT: int32 = 240;
let CYCLES: int32 = 6;
let FRAMES_PER_CYCLE: int32 = 3;
let MODEL_NODES: int32 = 5;
let HALF: float32 = 0.3;
let BACKGROUND: Vec4 = { x: 0.025, y: 0.05, z: 0.1, w: 1.0 };
let SURVIVOR_GREEN: Vec4 = { x: 0.0, y: 1.0, z: 0.0, w: 1.0 };
let RED: uint32 = 0xFF0000;
let GREEN: uint32 = 0x00FF00;
let BLUE: uint32 = 0x0000FF;
let YELLOW: uint32 = 0xFFFF00;
let SCREEN_MAPPING: LowResView = {
	width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0,
};
let COUNTERS: Vec<string> = ["buffers", "images", "views", "samplers", "shaders", "pipelines"];

let failures: int32 = 0;
let data: GltfData = decoded();
let cameraBlock: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let noLights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let noItems: Vec<DrawItem> = [];
let items: Vec<DrawItem> = [];
let survivorContext: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
let survivor: ForwardRenderer = forwardOf(survivorContext, SURVIVOR_GREEN);
let viewContext: DrawContext =
	DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH);
let viewScene: Scene3D = Scene3D.create(viewContext);
let viewForward: ForwardRenderer = forwardOf(viewContext, BACKGROUND);
let viewPixelArt: PixelArtRenderer = pixelArtOf(viewContext);
let warm: Vec<int32> = [];
let frames: int32 = 0;

function check(name: string, value: boolean): void {
	if (!value) {
		failures = failures + 1;
		console.log(`FAIL view teardown: ${name}`);
	}
}

function decoded(): GltfData {
	let file = readFile(FIXTURE);
	if (!file.ok) {
		console.log(`UNEXPECTED view teardown: ${FIXTURE} could not be read`);
		unreachable;
	}
	let loaded: Result<GltfData, GltfError> = loadGlb(file.value.asBytes());
	if (loaded.ok) { return loaded.value; }
	console.log(`UNEXPECTED view teardown: the fixture was refused: ${loaded.error.toString()}`);
	unreachable;
}

function forwardOf(context: DrawContext, background: Vec4): ForwardRenderer {
	let made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, background);
	if (made.ok) { return made.value; }
	console.log("UNEXPECTED view teardown: the forward preset was refused");
	unreachable;
}

function pixelArtOf(context: DrawContext): PixelArtRenderer {
	let settings: PixelArtSettings = { ...PixelArtSettings.full(), postPass: false };
	let look: PixelArtLook = {
		background: BACKGROUND,
		outline: {
			depthThreshold: 0.006,
			normalThreshold: 0.6,
			depthShade: 0.55,
			normalShade: 1.35,
		},
		fog: { start: 1.0, end: 1.0, strength: 0.0, color: BACKGROUND },
		saturation: 0.0,
	};
	let made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, settings, look);
	if (made.ok) { return made.value; }
	console.log("UNEXPECTED view teardown: the pixel-art preset was refused");
	unreachable;
}

function counters(): Vec<int32> {
	return [
		liveBuffers(),
		liveImages(),
		liveViews(),
		liveSamplers(),
		liveShaders(),
		livePipelines(),
	];
}

function openView(): void {
	viewContext = DrawContext.withUniformCapacity(
		FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + 5 * MATERIAL_UNIFORM_LENGTH,
	);
	viewScene = Scene3D.create(viewContext);
	viewForward = forwardOf(viewContext, BACKGROUND);
	viewPixelArt = pixelArtOf(viewContext);
	upload(viewPixelArt.palette);
	let setup: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	let assets: Result<GltfAssets, GltfSceneError> =
		addGltfAssets(viewContext, data, { pass: RenderState.defaults(), block: setup });
	if (!assets.ok) {
		console.log(`UNEXPECTED view teardown: the model was refused: ${assets.error.toString()}`);
		unreachable;
	}
	let model = addGroup(viewScene, viewScene.rootId(), Transform3D.identity());
	let added: Result<int32, GltfSceneError> =
		addGltfNodes(viewScene, model, data, assets.value.bindings);
	check("the model's nodes enter the view's scene", added.ok && added.value == MODEL_NODES);
	closeGltfAssets(assets.value);
	check("the loader gives its holds back", assets.value.isClosed());
	setAmbient(viewScene, vec3(1.0, 1.0, 1.0));
}

function closeView(): void {
	let alias: ForwardRenderer = viewForward;
	closeForward(alias);
	closePixelArt(viewPixelArt);
	closeScene(viewScene);
	check("the view's owners are closed",
		viewForward.isClosed() && viewPixelArt.isClosed() && viewScene.isClosed());
	check("the view's context holds nothing once its owners are closed",
		viewContext.liveMeshes() == 0 && viewContext.liveMaterials() == 0 &&
		viewContext.liveTextures() == 0 && viewContext.uniforms.liveRanges() == 0);
	closeContext(viewContext);
	check("the view's context is closed", viewContext.isClosed());
	check("the survivor holds what it held",
		survivorContext.liveMeshes() == 1 && survivorContext.liveMaterials() == 1 &&
		!survivor.isClosed());
}

function viewOf(): CameraView {
	let camera: Camera3D = {
		position: vec3(0.2, 0.0, 7.0),
		yaw: 0.0,
		pitch: 0.0,
		nearPlane: 0.5,
		farPlane: 30.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 1.0471975512 },
	};
	let resolved: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (resolved.ok) { return resolved.value; }
	unreachable;
}

function rgbOf(pixel: int64): uint32 {
	return ((pixel >> 8) & 0xFFFFFF) as uint32;
}

function pixelAt(view: CameraView, point: Vec3): uint32 {
	let at: Vec3 = view.project(point, SCREEN_MAPPING, true);
	return rgbOf(voidCapturePixel(0, at.x as int32, at.y as int32));
}

function checkModel(view: CameraView, preset: string): void {
	if (voidCaptureGrab(0) == 0) {
		check(`the ${preset} frame reads back`, false);
		return;
	}
	let quadrants: Vec<Vec3> = [
		vec3(-1.4 - HALF, HALF, 0.6), vec3(-1.4 + HALF, HALF, 0.6),
		vec3(-1.4 - HALF, -HALF, 0.6), vec3(-1.4 + HALF, -HALF, 0.6),
	];
	let texels: Vec<uint32> = [RED, GREEN, BLUE, YELLOW];
	for (let i = 0; i < 4; i++) {
		let got: uint32 = pixelAt(view, quadrants[i]);
		check(`the ${preset} view's cube quadrant ${i} is ${got}, not ${texels[i]}`,
			got == texels[i]);
	}
}

function checkSurvivor(): void {
	if (voidCaptureGrab(0) == 0) {
		check("the survivor's frame reads back", false);
		return;
	}
	let pixel: uint32 = rgbOf(voidCapturePixel(0, WIDTH / 2, HEIGHT / 2));
	check(`the survivor's frame is ${pixel}, not its own green`, pixel == GREEN);
}

function prepareSurvivor(): void {
	let drawn: Result<int32, ForwardError> = prepareForward(
		survivor, noItems, cameraBlock, noLights, WIDTH, HEIGHT,
	);
	check("the survivor prepares its frame", drawn.ok);
}

function viewFrame(view: CameraView, throughPixelArt: boolean): void {
	check("the view's scene draws the model", refresh(viewScene, items) == MODEL_NODES);
	let collected: Result<int32, LightError> = collectLights(viewScene, lights);
	if (!collected.ok) { unreachable; }
	if (throughPixelArt) {
		let drawn: Result<int32, PixelArtError> = preparePixelArt(
			viewPixelArt, items, cameraBlock, lights, SCREEN_MAPPING,
		);
		check("the pixel-art view prepares its frame", drawn.ok);
	} else {
		let drawn: Result<int32, ForwardError> = prepareForward(
			viewForward, items, cameraBlock, lights, WIDTH, HEIGHT,
		);
		check("the forward view prepares its frame", drawn.ok);
	}
	beginScreenPass(BACKGROUND);
	forwardToScreen(survivor);
	if (throughPixelArt) {
		pixelArtToScreen(viewPixelArt);
	} else {
		forwardToScreen(viewForward);
	}
	endPass();
	commit();
}

function survivorFrame(): void {
	beginScreenPass(BACKGROUND);
	forwardToScreen(survivor);
	endPass();
	commit();
}

function compareWarm(cycle: int32): void {
	let now: Vec<int32> = counters();
	if (cycle == 0) {
		warm = now;
		return;
	}
	for (let i = 0; i < (COUNTERS.length as int32); i++) {
		check(`after cycle ${cycle}, ${COUNTERS[i]} are ${now[i]}, warm ${warm[i]}`,
			now[i] == warm[i]);
	}
}

function report(): void {
	let now: Vec<int32> = counters();
	for (let i = 0; i < (COUNTERS.length as int32); i++) {
		console.log(`growth.${COUNTERS[i]}=${now[i] - warm[i]}`);
	}
	if (failures == 0) {
		console.log(
			`PASS view teardown: ${CYCLES} views made, drawn by both presets and closed beside ` +
			`a surviving context; the GPU back at the first's counts after each of the other ` +
			`${CYCLES - 1}`,
		);
		voidCaptureExit(0);
	}
	voidCaptureExit(1);
}

function init(): void {
	if (voidCaptureBackend() != 1) {
		console.log("SKIP view teardown: this consumer requires D3D11 readback");
		voidCaptureExit(3);
	}
	gfxSetup();
	closeView();
	for (let i = 0; i < LIGHT_UNIFORM_LENGTH; i++) { noLights[i] = 0.0; }
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { check("the framebuffer size", false); }
	let cycle: int32 = frames / FRAMES_PER_CYCLE;
	let step: int32 = frames % FRAMES_PER_CYCLE;
	let view: CameraView = viewOf();
	view.writeCameraBlock(cameraBlock);
	if (step == 0) { openView(); }
	if (step == 2) { closeView(); }
	prepareSurvivor();
	if (step == 2) {
		survivorFrame();
		checkSurvivor();
		compareWarm(cycle);
	} else {
		viewFrame(view, step == 1);
		checkModel(view, step == 1 ? "pixel-art" : "forward");
	}
	frames = frames + 1;
	if (frames == CYCLES * FRAMES_PER_CYCLE) { report(); }
}

if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
