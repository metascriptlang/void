import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, Mat4, vec3, eulerQuat } from "../../src/math/math3d";
import { RenderState } from "../../src/gpu/state";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addBox } from "../../src/void3d/meshData";
import {
	Program, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MaterialError, MeshUploadError,
	addMeshData, addMaterial, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, LightError, NO_NODE_ID,
	addGroup, addMeshNode, addCameraNode, setCameraOf, setActiveCamera, cameraOf,
	setLocal, setAmbient, refresh, collectLights, remove,
} from "../../src/void3d/scene";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH, renderFrame as renderForward,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer, PixelArtSettings, PixelArtLook, PixelArtError, PIXEL_ART_UNIFORM_LENGTH,
	renderFrame as renderPixelArt,
} from "../../src/void3d/pixelArtRenderer";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureSlotsDiffer,
	voidCaptureEnvInt, voidCaptureExit,
} from "../capture/capture.h";

let WIDTH: int32 = 320;
let HEIGHT: int32 = 240;
let BACKGROUND: Vec4 = { x: 0.04, y: 0.08, z: 0.12, w: 1.0 };
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let preset: PixelArtRenderer = makePreset();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let firstFrame: Vec<int64> = new Array(WIDTH * HEIGHT);
let SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
let parent: NodeId3D = NO_NODE_ID;
let cameraNode: NodeId3D = NO_NODE_ID;
let pixelArt: boolean = false;
let matched: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL camera rig: ${message}`);
	voidCaptureExit(1);
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, BACKGROUND);
	if (made.ok) { return made.value; }
	unreachable;
}

function makePreset(): PixelArtRenderer {
	const settings: PixelArtSettings = {
		...PixelArtSettings.full(), lowResShortSide: HEIGHT, margin: 0, postPass: false,
	};
	const look: PixelArtLook = {
		background: BACKGROUND,
		outline: {
			depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35,
		},
		fog: { start: 1.0, end: 1.0, strength: 0.0, color: BACKGROUND }, saturation: 0.0,
	};
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, settings, look);
	if (made.ok) { return made.value; }
	unreachable;
}

export function configureCameraRig(throughPixelArt: boolean): void {
	pixelArt = throughPixelArt;
}

function request(snap: boolean): Camera3D {
	return {
		position: vec3(0.0, 0.0, 5.0), yaw: 0.0, pitch: 0.0,
		nearPlane: 0.1, farPlane: 30.0,
		projection: { kind: ProjectionKind.Orthographic, worldPerTexel: 0.02, snap: snap },
	};
}

function resolved(camera: Camera3D): CameraView {
	const view: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	fail(`camera refused: ${view.error.toString()}`);
	unreachable;
}

function boundCamera(): NodeId3D {
	return addCameraNode(scene, parent, Transform3D.identity(), request(false));
}

export function initCameraRig(): void {
	if (voidCaptureBackend() != 1) {
		console.log("SKIP camera rig: this consumer requires D3D11 readback");
		voidCaptureExit(3);
	}
	gfxSetup();
	const block: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!block.ok) { unreachable; }
	const parameters: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	if (!writeUniforms(context, block.value, parameters).ok) { unreachable; }
	const material: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque), uniforms: block.value,
	});
	if (!material.ok) { unreachable; }
	const colours: Vec<Rgba> = [
		{ red: 0.9, green: 0.3, blue: 0.15, alpha: 1.0 },
		{ red: 0.1, green: 0.8, blue: 0.4, alpha: 1.0 },
	];
	for (let i = 0; i < 2; i++) {
		let data: MeshData = MeshData.empty();
		const box: Result<int32, MeshError> = addBox(data, {
			base: vec3((i as float32) * 1.5 - 1.0, -0.5, 0.0),
			size: vec3(0.8, 1.0, 0.8), yaw: 0.0, tilt: 0.0, color: colours[i],
		});
		if (!box.ok) { unreachable; }
		const mesh: Result<MeshId, MeshUploadError> = addMeshData(context, data);
		if (!mesh.ok) { unreachable; }
		const placed: Result<NodeId3D, SceneError> = addMeshNode(
			scene, scene.rootId(), Transform3D.identity(), mesh.value, material.value,
		);
		if (!placed.ok) { unreachable; }
	}
	parent = addGroup(scene, scene.rootId(), Transform3D.fromTranslation(vec3(0.0, 0.0, 5.0)));
	cameraNode = boundCamera();
	setAmbient(scene, vec3(1.0, 1.0, 1.0));
}

function place(pair: int32): Transform3D {
	const turn: float32 = pair == 0 || pair == 5 ? 0.0 : 0.45;
	const pan: Vec3 = pair == 3 || pair >= 6 ? vec3(0.313, 0.277, 5.0) : vec3(0.0, 0.0, 5.0);
	return {
		...Transform3D.fromTranslation(pan), rotation: eulerQuat(0.0, 0.0, turn),
		scale: pair == 2 || pair == 7 ? vec3(2.0, 4.0, 8.0) : vec3(1.0, 1.0, 1.0),
	};
}

function viewAt(frameIndex: int32): CameraView {
	const pair: int32 = Math.min(frameIndex / 2, 7) as int32;
	const pose: Transform3D = place(pair);
	const snap: boolean = pair == 3 || pair >= 6;
	const template: Camera3D = request(snap);
	if (frameIndex == 10) {
		const _removed: int32 = remove(scene, cameraNode);
		const stale: Result<Camera3D, CameraError> = cameraOf(scene, template);
		if (stale.ok || stale.error != CameraError.StaleCameraNode) {
			fail("removing the active camera did not report its stale handle");
		}
		setActiveCamera(scene, null);
	}
	if (frameIndex == 12) { cameraNode = boundCamera(); }
	setLocal(scene, parent, pose);
	if (pair == 0 || pair == 5) { setActiveCamera(scene, null); }
	else {
		setCameraOf(scene, cameraNode, template);
		setActiveCamera(scene, cameraNode);
	}
	if (frameIndex % 2 == 0) {
		const camera: Result<Camera3D, CameraError> = cameraOf(scene, template);
		if (camera.ok) { return resolved(camera.value); }
		fail("the registered camera did not resolve");
		unreachable;
	}
	if (pair == 0 || pair == 5) { return resolved(template); }
	const expected: Mat4 = {
		...pose.toMatrix(),
	};
	let unscaled: Transform3D = { ...pose, scale: vec3(1.0, 1.0, 1.0) };
	const world: Mat4 = pair == 2 || pair == 7 ? unscaled.toMatrix() : expected;
	const made: Result<Camera3D, CameraError> = Camera3D.fromWorld(world, template);
	if (!made.ok) { fail("the hand-built world camera was refused"); unreachable; }
	let camera: Camera3D = made.value;
	if (voidCaptureEnvInt("VOID_CAMERA_RIG_ROLL_CONTROL", 0) != 0) {
		camera = { ...template, position: pose.position };
	}
	return resolved(camera);
}

export function frameCameraRig(frameIndex: int32): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	const view: CameraView = viewAt(frameIndex);
	if (refresh(scene, items) != 2) { fail("camera groups changed the drawable count"); }
	const gathered: Result<int32, LightError> = collectLights(scene, lights);
	if (!gathered.ok) { unreachable; }
	view.writeCameraBlock(cameraValues);
	if (pixelArt) {
		const rendered: Result<int32, PixelArtError> =
			renderPixelArt(preset, items, cameraValues, lights, SCREEN);
		if (!rendered.ok) { fail("the pixel-art rig frame was refused"); }
	} else {
		const rendered: Result<int32, ForwardError> =
			renderForward(forward, items, cameraValues, lights, WIDTH, HEIGHT);
		if (!rendered.ok) { fail("the forward rig frame was refused"); }
	}
	if (voidCaptureGrab(0) == 0 || voidCaptureGrab(1) == 0) { fail("readback failed"); }
	if (voidCaptureSlotsDiffer() != 0) { fail("two readbacks of one frame differ"); }
	for (let y = 0; y < HEIGHT; y++) {
		for (let x = 0; x < WIDTH; x++) {
			const offset: int32 = y * WIDTH + x;
			const pixel: int64 = voidCapturePixel(0, x, y);
			if (frameIndex % 2 == 0) { firstFrame[offset] = pixel; }
			else if (firstFrame[offset] != pixel) {
				fail(`rig/manual pixels differ at frame ${frameIndex}, (${x},${y})`);
			}
		}
	}
	if (frameIndex % 2 != 0) {
		matched = matched + 1;
		console.log(`camera rig: pair ${matched} matched RGBA`);
	}
	if (frameIndex == 16) {
		if (matched != 8) { fail("not every rig/manual pose pair was compared"); }
		console.log(
			"PASS camera rig: parent roll, scale excluded, snapped roll, inactive and stale camera",
		);
	}
}
