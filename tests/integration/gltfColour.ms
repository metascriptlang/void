import { readFile } from "std/fs";
import { gfxSetup, fbWidth, fbHeight } from "../../src/host/gpu";
import { Vec3, Vec4, vec3, quatBetween } from "../../src/math/math3d";
import { RenderState } from "../../src/gpu/state";
import { beginScreenPass } from "../../src/gpu/target";
import { endPass, commit } from "../../src/gpu/door";
import { DrawContext, DrawItem, closeContext } from "../../src/void3d/draw";
import { GltfData, GltfDiagnostic, loadGlbDetailed, describe } from "../../src/void3d/gltf";
import {
	GltfAssets, GltfSceneError, addGltfAssets, addGltfNodes, closeGltfAssets,
} from "../../src/void3d/gltfScene";
import {
	Scene3D, Transform3D, NodeId3D, NO_NODE_ID, LightKind, LightInstance, LightError,
	addGroup, addLightNode, setLightPower, setAmbient, refresh, collectLights,
	remove, closeScene,
} from "../../src/void3d/scene";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH,
	prepareFrame, drawToScreen, closeForward,
} from "../../src/void3d/forwardRenderer";
import { attachShadow } from "../../src/void3d/renderer";
import {
	DirShadowMap, ShadowError, DIR_SHADOW_UNIFORM_LENGTH, closeDirShadow,
} from "../../src/void3d/dirShadowMap";
import {
	MATERIAL_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureSlotsDiffer,
	voidCaptureWritePng, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/host/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 384;
const HEIGHT: int32 = 288;
const COUNT: int32 = 10;
const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const SCREEN: LowResView = {
	width: WIDTH, height: HEIGHT, scale: 1, offsetX: 0.0, offsetY: 0.0,
};
const FIXTURE: string = "out/tmp/gltfColourRenderFixture/colourAsymmetric.glb";
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + DIR_SHADOW_UNIFORM_LENGTH + COUNT * MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer = makeForward();
let shadow: DirShadowMap = makeShadow();
let scene: Scene3D = Scene3D.create(context);
let model: NodeId3D = NO_NODE_ID;
let sun: NodeId3D = NO_NODE_ID;
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let frameIndex: int32 = 0;
let baseMeshes: int32 = 0;
let baseMaterials: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL gltf colour: ${message}`);
	voidCaptureExit(1);
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, BLACK);
	if (made.ok) { return made.value; }
	unreachable;
}

function makeShadow(): DirShadowMap {
	const made: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 1024);
	if (made.ok) { return made.value; }
	unreachable;
}

function decoded(): GltfData {
	const file = readFile(FIXTURE);
	if (!file.ok) { fail("generated GLB missing"); unreachable; }
	const bytes: Vec<uint8> = [...file.value.asBytes()];
	const loaded: Result<GltfData, GltfDiagnostic> = loadGlbDetailed(bytes, FIXTURE);
	if (loaded.ok) { return loaded.value; }
	fail(loaded.error.describe());
	unreachable;
}

function bind(): void {
	const data: GltfData = decoded();
	const added: Result<GltfAssets, GltfSceneError> = addGltfAssets(context, data, {
		pass: RenderState.defaults(), block: [4.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
	});
	if (!added.ok) { fail(`assets refused: ${added.error.toString()}`); return; }
	model = addGroup(scene, scene.rootId(), Transform3D.identity());
	const bound: Result<int32, GltfSceneError> =
		addGltfNodes(scene, model, data, added.value.bindings);
	if (!bound.ok || bound.value != COUNT) { fail("imported nodes did not bind"); }
	closeGltfAssets(added.value);
	if (context.liveMeshes() != baseMeshes + COUNT
		|| context.liveMaterials() != baseMaterials + COUNT
		|| context.liveTextures() != 1) {
		fail("closing loader holds lost node resources");
	}
}

function unbind(): void {
	if (remove(scene, model) != COUNT + 1) { fail("remove missed imported group or nodes"); }
	model = NO_NODE_ID;
	if (context.liveMeshes() != baseMeshes || context.liveMaterials() != baseMaterials
		|| context.liveTextures() != 0) {
		fail("imported resources survived removal");
	}
}

function init(): void {
	if (voidCaptureBackend() != 1 && voidCaptureBackend() != 5) {
		console.log("SKIP gltf colour: existing oracle requires D3D11 or Metal readback");
		voidCaptureExit(3);
	}
	gfxSetup();
	baseMeshes = context.liveMeshes();
	baseMaterials = context.liveMaterials();
	bind();
	const toLight: Vec3 = vec3(1.0, 0.0, 2.0).normalized();
	const light: LightInstance = {
		kind: LightKind.Directional, color: vec3(1.0, 1.0, 1.0),
		radius: 0.0, power: 0.0, priority: 0,
	};
	sun = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(),
		rotation: quatBetween(vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0) - toLight),
	}, light);
	setAmbient(scene, vec3(1.0, 1.0, 1.0));
}

function viewOf(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 0.0, 4.0), yaw: 0.0, pitch: 0.0,
		nearPlane: 0.1, farPlane: 10.0,
		projection: {
			kind: ProjectionKind.Orthographic, worldPerTexel: 0.025, snap: false,
		},
	};
	const resolved: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (resolved.ok) { return resolved.value; }
	unreachable;
}

function rgbAt(view: CameraView, point: Vec3): int64 {
	const at: Vec3 = view.project(point, SCREEN, true);
	const pixel: int64 = voidCapturePixel(0, at.x as int32, at.y as int32);
	if (pixel < 0) { fail("sample outside capture"); }
	return (pixel >> 8) & 0xFFFFFF;
}

function panelPoint(panel: int32, side: int32): Vec3 {
	const x: float32 = ((panel % 3 - 1) * 3) as float32;
	const y: float32 = (2 - (panel / 3) * 2) as float32;
	return vec3(x + ((side == 0 ? -0.5 : 0.5) as float32), y, 0.0);
}

function expectPanel(view: CameraView, panel: int32, side: int32, want: int64): void {
	const got: int64 = rgbAt(view, panelPoint(panel, side));
	if (got != want) { fail(`panel ${panel} side ${side}: ${got}, wanted ${want}`); }
}

function checkColour(view: CameraView): void {
	expectPanel(view, 0, 0, 0xFF0000);
	expectPanel(view, 0, 1, 0x00FF00);
	expectPanel(view, 1, 0, 0xFF0000);
	expectPanel(view, 1, 1, 0x00FF00);
	for (let side = 0; side < 2; side++) {
		const normalized: int64 = rgbAt(view, panelPoint(2, side));
		const floating: int64 = rgbAt(view, panelPoint(3, side));
		const endpoint: int64 = side == 0 ? 0xFF0000 : 0x00FF00;
		if (normalized != floating || normalized == endpoint || normalized == 0xFFFFFF) {
			fail("BLEND normalized alpha-factor differs from FLOAT half-alpha control");
		}
	}
	expectPanel(view, 4, 0, 0xFF0000);
	expectPanel(view, 4, 1, 0xFFFFFF);
	expectPanel(view, 5, 0, 0xFFFFFF);
	expectPanel(view, 5, 1, 0xFFFFFF);
	expectPanel(view, 6, 0, 0xFFFFFF);
	expectPanel(view, 6, 1, 0xFFFFFF);
	expectPanel(view, 7, 0, 0xFF0000);
	expectPanel(view, 7, 1, 0xFFFFFF);
	expectPanel(view, 8, 0, 0xFFFFFF);
	expectPanel(view, 8, 1, 0x00FF00);
}

function checkShadow(view: CameraView): void {
	const panels: Vec<int32> = [4, 5, 6, 7];
	for (const panel of panels) {
		const center: Vec3 = panelPoint(panel, 0);
		const under: int64 = rgbAt(view, vec3(center.x - 0.5, center.y, -1.0));
		const open: int64 = rgbAt(view, vec3(center.x - 0.5, center.y + 0.8, -1.0));
		const casts: boolean = panel == 4 || panel == 7;
		if ((under != open) != casts) {
			fail(`MASK shadow panel ${panel}: under ${under}, open ${open}, casts ${casts}`);
		}
	}
}

function checkEmpty(): void {
	for (let y = 0; y < HEIGHT; y++) {
		for (let x = 0; x < WIDTH; x++) {
			if (voidCapturePixel(0, x, y) != 0x000000FF) {
				fail("pixel survived imported model removal");
			}
		}
	}
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("framebuffer changed"); }
	if (frameIndex == 5 || frameIndex == 20) { unbind(); }
	if (frameIndex == 10) { bind(); }
	if (frameIndex == 15) {
		attachShadow(forward.core, shadow);
		setAmbient(scene, vec3(0.0, 0.0, 0.0));
		setLightPower(scene, sun, 1.0);
	}
	const expected: int32 = model == NO_NODE_ID ? 0 : COUNT;
	if (refresh(scene, items) != expected) { fail("draw list count changed"); }
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { fail("light collection refused"); }
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	const prepared: Result<int32, ForwardError> =
		prepareFrame(forward, items, cameraValues, lights, WIDTH, HEIGHT);
	if (!prepared.ok || prepared.value != expected) { fail("forward draw refused or lost mesh"); }
	beginScreenPass(BLACK);
	drawToScreen(forward);
	endPass();
	commit();
	if (frameIndex == 1 || frameIndex == 6 || frameIndex == 11
		|| frameIndex == 16 || frameIndex == 21) {
		if (voidCaptureGrab(0) == 0 || voidCaptureGrab(1) == 0) { fail("readback failed"); }
		if (voidCaptureSlotsDiffer() != 0) { fail("same-frame captures differ"); }
		if (frameIndex == 1 || frameIndex == 11) { checkColour(view); }
		if (frameIndex == 6 || frameIndex == 21) { checkEmpty(); }
		if (frameIndex == 16) { checkShadow(view); }
		if (voidCaptureWritePng(0,
			`out/tmp/gltfColourRenderFixture/frame${frameIndex}.png`) == 0) {
			fail("existing PNG capture failed");
		}
		console.log(`gltf colour: frame ${frameIndex} checked`);
	}
	if (frameIndex == 21) {
		closeScene(scene);
		closeForward(forward);
		closeDirShadow(shadow);
		closeContext(context);
		console.log("PASS gltf colour: imported RGBA, alpha products, shadow, remove and rebind");
		voidCaptureExit(0);
	}
	frameIndex = frameIndex + 1;
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
