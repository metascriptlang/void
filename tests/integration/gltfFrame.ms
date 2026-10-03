import { readFile } from "std/fs";
import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3, eulerQuat, srgbToLinear } from "../../src/math/math3d";
import { RenderState } from "../../src/gpu/state";
import { beginScreenPass } from "../../src/gpu/target";
import {
	endPass,
	commit,
	contextGeneration,
	liveBuffers,
	liveImages,
	liveViews,
} from "../../src/gpu/door";
import { MeshData } from "../../src/void3d/meshData";
import { GpuTexture, TextureId } from "../../src/void3d/texture";
import {
	MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import { DrawContext, DrawItem, HandleError, buryDoomed } from "../../src/void3d/draw";
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
	NodeId3D,
	LightError,
	LightKind,
	LightInstance,
	addGroup,
	addLightNode,
	remove,
	setLocal,
	setAmbient,
	setLightPower,
	refresh,
	collectLights,
	NO_NODE_ID,
} from "../../src/void3d/scene";
import { Camera3D, ProjectionKind, CameraView, CameraError } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	prepareFrame,
	drawToScreen,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	renderFrame as renderPixelArt,
} from "../../src/void3d/pixelArtRenderer";
import {
	voidCaptureBackend,
	voidCaptureGrab,
	voidCapturePixel,
	voidCaptureSlotsDiffer,
	voidCaptureExit,
} from "../capture/capture.h";

let FIXTURE: string = "tests/fixtures/gltf/texturedScene.glb";
let WIDTH: int32 = 320;
let HEIGHT: int32 = 240;
let BACKGROUND: Vec4 = { x: 0.025, y: 0.05, z: 0.1, w: 1.0 };
let RED: uint32 = 0xFF0000;
let GREEN: uint32 = 0x00FF00;
let BLUE: uint32 = 0x0000FF;
let YELLOW: uint32 = 0xFFFF00;
let WHITE: uint32 = 0xFFFFFF;
let MODEL_NODES: int32 = 5;
let HALF: float32 = 0.3;
let SCREEN_MAPPING: LowResView = {
	width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0,
};
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + 5 * MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer = createForward();
let preset: PixelArtRenderer = createPreset();
let scene: Scene3D = Scene3D.create(context);
let items: Vec<DrawItem> = [];
let model: NodeId3D = NO_NODE_ID;
let sun: NodeId3D = NO_NODE_ID;
let lamps: Vec<NodeId3D> = [];
let texture: TextureId = { store: 0, index: 0, generation: 0 };
let cameraBlock: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let pixelArt: boolean = false;
let rebuildAt: int32 = -1;
let viewBefore: uint32 = 0;
let samplerBefore: uint32 = 0;
let meshesBefore: int32 = 0;
let materialsBefore: int32 = 0;
let imagesBefore: int32 = 0;
let viewsBefore: int32 = 0;
let buffersLoaded: int32 = 0;
let imagesLoaded: int32 = 0;
let viewsLoaded: int32 = 0;

function createForward(): ForwardRenderer {
	let created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, BACKGROUND);
	if (created.ok) { return created.value; }
	unreachable;
}

function createPreset(): PixelArtRenderer {
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
	let created: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, settings, look);
	if (created.ok) { return created.value; }
	unreachable;
}

function fail(message: string): void {
	console.log(`FAIL gltf frame: ${message}`);
	voidCaptureExit(1);
}

export function configureGltf(throughPixelArt: boolean, rebuildFrame: int32): void {
	pixelArt = throughPixelArt;
	rebuildAt = rebuildFrame;
}

function decoded(): GltfData {
	let file = readFile(FIXTURE);
	if (!file.ok) {
		fail(`${FIXTURE} could not be read`);
		unreachable;
	}
	const bytes: Vec<uint8> = [...file.value.asBytes()];
	let data: Result<GltfData, GltfError> = loadGlb(bytes);
	if (data.ok) { return data.value; }
	fail(`the fixture was refused: ${data.error.toString()}`);
	unreachable;
}

function setupBlock(): Vec<float32> {
	return [4.0, 0.0, 0.0, 0.0];
}

function checkRollback(data: GltfData): void {
	let small: DrawContext = DrawContext.withUniformCapacity(2 * MATERIAL_UNIFORM_LENGTH);
	let refused: Result<GltfAssets, GltfSceneError> =
		addGltfAssets(small, data, { pass: RenderState.defaults(), block: setupBlock() });
	if (refused.ok || refused.error != GltfSceneError.UniformsFull) {
		fail("five materials in a pool of two were not refused as UniformsFull");
		return;
	}
	if (small.liveTextures() != 0 || small.liveMaterials() != 0 || small.liveMeshes() != 0) {
		fail("a refused load left an asset live");
	}
	let buried: int32 = buryDoomed(small, contextGeneration());
	if (buried == 0 || liveImages() != imagesBefore || liveViews() != viewsBefore) {
		fail(`a refused load left ${liveImages() - imagesBefore} images after ${buried} burials`);
	}
}

function loadModel(data: GltfData): void {
	let assets: Result<GltfAssets, GltfSceneError> =
		addGltfAssets(context, data, { pass: RenderState.defaults(), block: setupBlock() });
	if (!assets.ok) {
		fail(`the driver refused the model: ${assets.error.toString()}`);
		return;
	}
	texture = assets.value.textures[0];
	if (context.liveMaterials() != materialsBefore + 5
		|| context.liveMeshes() != meshesBefore + 5) {
		fail("the model did not make five materials and five meshes");
	}
	if (context.texturePinned(texture) != 2) { fail("two textured materials do not pin it"); }
	model = addGroup(scene, scene.rootId(), Transform3D.identity());
	let added: Result<int32, GltfSceneError> =
		addGltfNodes(scene, model, data, assets.value.bindings);
	if (!added.ok || added.value != MODEL_NODES) {
		fail("the model's five nodes did not enter the scene");
		return;
	}
	closeGltfAssets(assets.value);
	if (context.liveMaterials() != materialsBefore + 5 || !context.hasTexture(texture)) {
		fail("releasing the loader's holds freed what the nodes still draw");
	}
}

export function initGltf(): void {
	if (voidCaptureBackend() != 1) {
		console.log("SKIP gltf frame: this consumer requires D3D11 readback");
		voidCaptureExit(3);
	}
	gfxSetup();
	meshesBefore = context.liveMeshes();
	materialsBefore = context.liveMaterials();
	imagesBefore = liveImages();
	viewsBefore = liveViews();
	let data: GltfData = decoded();
	checkRollback(data);
	loadModel(data);
	let light: LightInstance = {
		kind: LightKind.Directional,
		color: vec3(1.0, 1.0, 1.0),
		radius: 0.0,
		power: 0.0,
		priority: 0,
	};
	let towardCamera: Transform3D = {
		...Transform3D.identity(), rotation: { x: 0.0, y: 1.0, z: 0.0, w: 0.0 },
	};
	sun = addLightNode(scene, scene.rootId(), towardCamera, light);
	let point: LightInstance = { ...light, kind: LightKind.Point, radius: 2.0 };
	let lampXs: Vec<float32> = [0.4, 2.0];
	for (const x of lampXs) {
		lamps.push(addLightNode(
			scene, scene.rootId(), Transform3D.fromTranslation(vec3(x, 0.0, 0.2)), point,
		));
	}
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

function stage(frameIndex: int32): int32 {
	if (frameIndex < 5) { return 0; }
	if (frameIndex < 10) { return 1; }
	if (frameIndex < 15) { return 2; }
	return 3;
}

function pose(frameIndex: int32): void {
	let turn: float32 = stage(frameIndex) == 2 ? 0.6 : 0.0;
	if (stage(frameIndex) < 3) {
		setLocal(scene, model, { ...Transform3D.identity(), rotation: eulerQuat(0.0, turn, 0.0) });
	}
	let lit: boolean = stage(frameIndex) == 1;
	let lamplit: boolean = lit && pixelArt;
	let sunlit: boolean = lit && !pixelArt;
	let ambient: float32 = lamplit ? 0.0 : sunlit ? 0.25 : 1.0;
	setAmbient(scene, vec3(ambient, ambient, ambient));
	setLightPower(scene, sun, sunlit ? 1.0 - srgbToLinear(ambient) : 0.0);
	for (const lamp of lamps) { setLightPower(scene, lamp, lamplit ? 3.0 : 0.0); }
}

function rgbOf(pixel: int64): uint32 {
	return ((pixel >> 8) & 0xFFFFFF) as uint32;
}

function channelOf(rgb: uint32, shift: uint32): int32 {
	return ((rgb >> shift) & 0xFF) as int32;
}

function pixelAt(view: CameraView, point: Vec3): uint32 {
	let at: Vec3 = view.project(point, SCREEN_MAPPING, true);
	return rgbOf(voidCapturePixel(0, at.x as int32, at.y as int32));
}

// The factor quad: COLOR_0 (1, 0.5, 0.5) times baseColorFactor (0.5, 0.5, 1), within one step.
function isFactorColour(got: uint32): boolean {
	let want: Vec<int32> = [188, 137, 188];
	let shifts: Vec<uint32> = [16, 8, 0];
	for (let i = 0; i < 3; i++) {
		let difference: int32 = channelOf(got, shifts[i]) - want[i];
		if (difference < -1 || difference > 1) { return false; }
	}
	return true;
}

function expectAt(view: CameraView, point: Vec3, want: uint32, what: string): void {
	let got: uint32 = pixelAt(view, point);
	if (got != want) { fail(`${what} is ${got}, not ${want}`); }
}

// Face on, at full light: every checked colour is exact. The double-sided quads are seen from
// behind, where the textured one shows its texture mirrored, and the single-sided one is culled.
function checkFaceOn(view: CameraView): void {
	let cube: Vec<Vec3> = [
		vec3((-1.4 - HALF) as float32, HALF, 0.6), vec3((-1.4 + HALF) as float32, HALF, 0.6),
		vec3((-1.4 - HALF) as float32, -HALF, 0.6), vec3((-1.4 + HALF) as float32, -HALF, 0.6),
	];
	let mirrored: Vec<Vec3> = [
		vec3(2.0 + HALF, HALF, -0.6), vec3(2.0 - HALF, HALF, -0.6),
		vec3(2.0 + HALF, -HALF, -0.6), vec3(2.0 - HALF, -HALF, -0.6),
	];
	let texels: Vec<uint32> = [RED, GREEN, BLUE, YELLOW];
	for (let i = 0; i < 4; i++) {
		expectAt(view, cube[i], texels[i], `cube quadrant ${i}`);
		expectAt(view, mirrored[i], texels[i], `the double-sided textured quad's quadrant ${i}`);
	}
	expectAt(view, vec3(0.4, 0.0, -0.6), WHITE, "the double-sided quad's back");
	if (!isFactorColour(pixelAt(view, vec3(-3.2, 0.0, 0.6)))) {
		fail(`the factor quad is ${pixelAt(view, vec3(-3.2, 0.0, 0.6))}, not (188, 137, 188)`);
	}
	let background: uint32 = rgbOf(voidCapturePixel(0, 2, 2));
	expectAt(view, vec3(3.6, 0.0, -0.6), background, "the single-sided quad's culled back");
}

function rampLevelOf(channel: int32): int32 {
	const lit: float64 = srgbToLinear((channel as float32) / 255.0) * 4.0;
	const step: int32 = Math.round(lit) as int32;
	let off: float64 = lit - (step as float64);
	if (off < 0.0) { off = -off; }
	if (off > 0.02) { return -1; }
	return step;
}

// The pixel-art preset steps each lamp to the material's four ramp levels. A back face lit only
// through its reversed normal shows at least two levels; unreversed, it faces away and is black.
function checkStepped(view: CameraView, centreX: float32, textured: boolean): void {
	let left: float32 = textured ? centreX : centreX - 2.0 * HALF;
	let bottom: float32 = textured ? 0.0 : -(2.0 * HALF);
	let topRight: Vec3 = vec3(centreX + 2.0 * HALF, 2.0 * HALF, -0.6);
	let from: Vec3 = view.project(topRight, SCREEN_MAPPING, true);
	let to: Vec3 = view.project(vec3(left, bottom, -0.6), SCREEN_MAPPING, true);
	let x0: int32 = Math.min(from.x as int32, to.x as int32) + 2;
	let x1: int32 = Math.max(from.x as int32, to.x as int32) - 2;
	let levels: Vec<int32> = [0, 0, 0, 0, 0];
	for (let y = (from.y as int32) + 2; y < (to.y as int32) - 2; y++) {
		for (let x = x0; x < x1; x++) {
			let got: uint32 = rgbOf(voidCapturePixel(0, x, y));
			let red: int32 = channelOf(got, 16);
			let others: boolean = textured
				? channelOf(got, 8) == 0 && channelOf(got, 0) == 0
				: channelOf(got, 8) == red && channelOf(got, 0) == red;
			const step: int32 = rampLevelOf(red);
			if (!others || step < 0) {
				fail(`pixel (${x}, ${y}) is ${got}, not a stepped back face`);
				return;
			}
			levels[step > 4 ? 4 : step] = 1;
		}
	}
	let shown: int32 = levels[1] + levels[2] + levels[3] + levels[4];
	if (shown < 2) { fail(`a lamp shows ${shown} lit levels on a back face at x ${centreX}`); }
}

function checkOnlyKnown(): void {
	let background: uint32 = rgbOf(voidCapturePixel(0, 2, 2));
	let known: Vec<uint32> = [background, RED, GREEN, BLUE, YELLOW, WHITE];
	for (let y = 0; y < HEIGHT; y++) {
		for (let x = 0; x < WIDTH; x++) {
			let got: uint32 = rgbOf(voidCapturePixel(0, x, y));
			let found: boolean = isFactorColour(got);
			for (const colour of known) {
				if (got == colour) { found = true; }
			}
			if (!found) {
				fail(`pixel (${x}, ${y}) is ${got}, no colour of the model`);
				return;
			}
		}
	}
}

function checkEmptied(): void {
	let background: uint32 = rgbOf(voidCapturePixel(0, 2, 2));
	for (let y = 0; y < HEIGHT; y++) {
		for (let x = 0; x < WIDTH; x++) {
			if (rgbOf(voidCapturePixel(0, x, y)) != background) {
				fail(`pixel (${x}, ${y}) still draws after the model was removed`);
				return;
			}
		}
	}
	if (context.liveMeshes() != meshesBefore || context.liveMaterials() != materialsBefore
		|| context.liveTextures() != 0) {
		fail("removing the model's nodes did not free its meshes, materials and texture");
	}
	if (buffersLoaded - liveBuffers() != 10 || imagesLoaded - liveImages() != 1
		|| viewsLoaded - liveViews() != 1) {
		fail(`the burial took ${buffersLoaded - liveBuffers()} buffers, `
			+ `${imagesLoaded - liveImages()} images and ${viewsLoaded - liveViews()} views, `
			+ "not the model's 10, 1 and 1");
	}
}

function loseContext(): void {
	viewBefore = context.textures[texture.index].view;
	samplerBefore = context.textures[texture.index].sampler;
	for (let i = 0; i < (context.meshes.length as int32); i++) {
		if (context.meshData[i].vertexCount() > 0) { context.meshes[i].generation = 0; }
	}
	context.textures[texture.index].generation = 0;
	context.samplerGeneration = 0;
	forward.core.generation = 0;
	preset.core.generation = 0;
}

function checkRemade(): void {
	let remade: GpuTexture = context.textures[texture.index];
	if (remade.view == viewBefore || remade.view == 0 || remade.sampler == samplerBefore ||
		remade.sampler == 0 || remade.generation != contextGeneration()) {
		fail(`the new context kept view ${remade.view} or sampler ${remade.sampler}`);
	}
}

function drawn(): int32 {
	if (pixelArt) {
		let frame: Result<int32, PixelArtError> =
			renderPixelArt(preset, items, cameraBlock, lights, SCREEN_MAPPING);
		if (frame.ok) { return frame.value; }
		fail(`the pixel-art preset refused the model: ${frame.error.toString()}`);
		return 0;
	}
	let frame: Result<int32, ForwardError> =
		prepareFrame(forward, items, cameraBlock, lights, WIDTH, HEIGHT);
	if (!frame.ok) {
		fail(`the forward preset refused the model: ${frame.error.toString()}`);
		return 0;
	}
	beginScreenPass(BACKGROUND);
	drawToScreen(forward);
	endPass();
	commit();
	return frame.value;
}

export function frameGltf(frameIndex: int32): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	if (frameIndex == rebuildAt) { loseContext(); }
	if (frameIndex == 15) {
		buffersLoaded = liveBuffers();
		imagesLoaded = liveImages();
		viewsLoaded = liveViews();
		if (remove(scene, model) != MODEL_NODES + 1) { fail("the model's group was not removed"); }
	}
	pose(frameIndex);
	let expected: int32 = stage(frameIndex) == 3 ? 0 : MODEL_NODES;
	if (refresh(scene, items) != expected) { fail(`the scene does not draw ${expected} meshes`); }
	let collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { unreachable; }
	let view: CameraView = viewOf();
	view.writeCameraBlock(cameraBlock);
	if (drawn() != expected) { fail(`the frame did not draw ${expected} meshes`); }
	if (frameIndex == rebuildAt) { checkRemade(); }
	if (frameIndex == 1 || frameIndex == 6 || frameIndex == 11 || frameIndex == 16) {
		if (voidCaptureGrab(0) == 0 || voidCaptureGrab(1) == 0) { fail("D3D11 readback failed"); }
		if (voidCaptureSlotsDiffer() != 0) { fail("two readbacks of the same frame differ"); }
		if (stage(frameIndex) == 0 || (stage(frameIndex) == 1 && !pixelArt)) { checkFaceOn(view); }
		if (stage(frameIndex) == 1 && pixelArt) {
			checkStepped(view, 0.4, false);
			checkStepped(view, 2.0, true);
		}
		if (stage(frameIndex) == 2) { checkOnlyKnown(); }
		if (stage(frameIndex) == 3) { checkEmptied(); }
		console.log(`gltf frame: frame ${frameIndex} checked`);
	}
	if (frameIndex == 16) {
		console.log("PASS gltf frame: texels, factor, both sides, culling, rollback, release");
	}
}
