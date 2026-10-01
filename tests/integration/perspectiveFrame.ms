import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3 } from "../../src/math/math3d";
import { RenderState } from "../../src/gpu/state";
import { beginScreenPass } from "../../src/gpu/target";
import { endPass, commit } from "../../src/gpu/door";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addBox } from "../../src/void3d/meshData";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Program,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext,
	DrawItem,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	addMeshData,
	addMaterial,
	reserveUniforms,
	writeUniforms,
} from "../../src/void3d/draw";
import {
	Transform3D,
	Scene3D,
	NodeId3D,
	NodeFlag,
	SceneError,
	LightError,
	LightKind,
	LightInstance,
	addMeshNode,
	addLightNode,
	setLocal,
	setPickable,
	setAmbient,
	refresh,
	collectLights,
} from "../../src/void3d/scene";
import { Camera3D, ProjectionKind, CameraView, CameraError } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import { PickHit, PickError, pickNearest } from "../../src/void3d/pick";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	prepareFrame,
	drawToScreen,
} from "../../src/void3d/forwardRenderer";
import {
	voidCaptureBackend,
	voidCaptureGrab,
	voidCapturePixel,
	voidCaptureSlotsDiffer,
	voidCaptureEnvInt,
	voidCaptureExit,
} from "../capture/capture.h";

let WIDTH: int32 = 320;
let HEIGHT: int32 = 240;
let BACKGROUND: Vec4 = { x: 0.025, y: 0.05, z: 0.1, w: 1.0 };
let BOX_COLOR: Rgba = { red: 0.9, green: 0.45, blue: 0.15, alpha: 1.0 };
let SCREEN_MAPPING: LowResView = {
	width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0,
};
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer = createForward();
let scene: Scene3D = Scene3D.create();
let items: Vec<DrawItem> = [];
let nodes: Vec<NodeId3D> = [];
let positions: Vec<Vec3> = [
	vec3(0.0, 0.0, -9.0), vec3(0.0, 0.0, -6.0),
	vec3(-2.0, 1.0, -6.0), vec3(2.0, -1.0, -6.0),
	vec3(20.0, 0.0, -9.0), vec3(20.0, 0.0, -6.0),
	vec3(18.0, 1.0, -6.0), vec3(22.0, -1.0, -6.0),
];
let cameraBlock: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);

function createForward(): ForwardRenderer {
	let created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, BACKGROUND);
	if (created.ok) { return created.value; }
	unreachable;
}

function fail(message: string): void {
	console.log(`FAIL perspective frame: ${message}`);
	voidCaptureExit(1);
}

function litMaterial(): MaterialId {
	let reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	let levels: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	let written: Result<int32, UniformError> = writeUniforms(context, reserved.value, levels);
	if (!written.ok) { unreachable; }
	let plain: Material = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
	let added: Result<MaterialId, MaterialError> =
		addMaterial(context, { ...plain, uniforms: reserved.value });
	if (!added.ok) { unreachable; }
	return added.value;
}

export function initPerspective(): void {
	if (voidCaptureBackend() != 1) {
		console.log("SKIP perspective frame: this consumer requires D3D11 readback");
		voidCaptureExit(3);
	}
	gfxSetup();
	let data: MeshData = MeshData.empty();
	let boxed: Result<int32, MeshError> = addBox(data, {
		base: vec3(0.0, -0.5, 0.0),
		size: vec3(1.0, 1.0, 1.0),
		yaw: 0.0,
		tilt: 0.0,
		color: BOX_COLOR,
	});
	if (!boxed.ok) { unreachable; }
	let mesh: Result<MeshId, MeshUploadError> = addMeshData(context, data);
	if (!mesh.ok) { unreachable; }
	let material: MaterialId = litMaterial();
	for (let position of positions) {
		let placed: Result<NodeId3D, SceneError> = addMeshNode(
			scene, context, scene.rootId(), Transform3D.fromTranslation(position),
			mesh.value, material,
		);
		if (!placed.ok) { unreachable; }
		nodes.push(placed.value);
		setPickable(scene, placed.value, true);
	}
	setAmbient(scene, vec3(0.125, 0.125, 0.125));
	let sun: LightInstance = {
		kind: LightKind.Directional,
		color: vec3(1.0, 1.0, 1.0),
		radius: 0.0,
		power: 0.75,
		priority: 0,
	};
	let direction: Transform3D = {
		...Transform3D.identity(), rotation: { x: 0.0, y: 1.0, z: 0.0, w: 0.0 },
	};
	let _sun: NodeId3D = addLightNode(scene, scene.rootId(), direction, sun);
	let count: int32 = refresh(scene, items);
	if (count != 8 || scene.structureChanged) {
		fail("the initial CPU draw list does not retain all eight boxes");
	}
	let collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { unreachable; }
}

function viewAt(x: float32): CameraView {
	if (voidCaptureEnvInt("VOID_PERSPECTIVE_SHIFT_CONTROL", 0) != 0) { x = 200.0; }
	let camera: Camera3D = {
		position: vec3(x, 0.0, 0.0),
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

function checkPick(view: CameraView, sample: Vec3, expected: NodeId3D): int32 {
	let pixel: Vec3 = view.project(sample, SCREEN_MAPPING, true);
	if (pixel.x < 0.0 || pixel.x >= (WIDTH as float32) ||
		pixel.y < 0.0 || pixel.y >= (HEIGHT as float32) || pixel.z <= 0.0 || pixel.z >= 1.0) {
		fail("the perspective pick sample is not inside the view");
	}
	let hit: Result<PickHit, PickError> = pickNearest(
		scene, context.meshData, context.materials,
		view.rayFromScreen(pixel.x, pixel.y, SCREEN_MAPPING, true),
	);
	if (!hit.ok) {
		fail("the perspective screen ray did not hit its projected box");
		unreachable;
	}
	if (hit.value.owner != expected || hit.value.mesh != expected) {
		fail(`the perspective ray picked node ${hit.value.mesh.index}, expected ${expected.index}`);
	}
	return hit.value.mesh.index;
}

function channel(pixel: int64, shift: int64): int32 {
	return ((pixel >> shift) & 255) as int32;
}

function closeChannel(got: int32, wanted: float32): boolean {
	let difference: float32 = (got as float32) - wanted;
	return difference >= -3.0 && difference <= 3.0;
}

function checkLitPixel(view: CameraView, position: Vec3): void {
	let sample: Vec3 = view.project(position, SCREEN_MAPPING, true);
	let pixel: int64 = voidCapturePixel(0, sample.x as int32, sample.y as int32);
	let brightness: float32 = (0.125 + 0.75) * 255.0;
	if (!closeChannel(channel(pixel, 24), BOX_COLOR.red * brightness) ||
		!closeChannel(channel(pixel, 16), BOX_COLOR.green * brightness) ||
		!closeChannel(channel(pixel, 8), BOX_COLOR.blue * brightness)) {
		fail("the projected box is not the visible orange directional-lit front face");
	}
}

function checkBackground(): void {
	let pixel: int64 = voidCapturePixel(0, 4, 4);
	if (!closeChannel(channel(pixel, 24), BACKGROUND.x * 255.0) ||
		!closeChannel(channel(pixel, 16), BACKGROUND.y * 255.0) ||
		!closeChannel(channel(pixel, 8), BACKGROUND.z * 255.0)) {
		fail("the empty corner does not contain the scene background");
	}
}

export function framePerspective(frameIndex: int32): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) {
		fail("the fixed-size consumer framebuffer changed");
	}
	if (scene.structureChanged) { fail("the retained scene structure changed between views"); }
	if (frameIndex == 10) {
		setLocal(scene, nodes[1], Transform3D.fromTranslation(vec3(20.0, -2.0, -6.0)));
	}
	if (frameIndex == 15) {
		setLocal(scene, nodes[1], Transform3D.fromTranslation(positions[1]));
	}
	let count: int32 = refresh(scene, items);
	if (count != 8 || scene.structureChanged) {
		fail("a view filtered the retained eight-item CPU draw list");
	}
	let shifted: boolean = frameIndex >= 5 && frameIndex < 15;
	let moved: boolean = frameIndex >= 10 && frameIndex < 15;
	let view: CameraView = viewAt(shifted ? 20.0 : 0.0);
	view.writeCameraBlock(cameraBlock);
	let prepared: Result<int32, ForwardError> =
		prepareFrame(forward, context, items, cameraBlock, lights, WIDTH, HEIGHT);
	if (!prepared.ok) {
		fail(`prepareFrame refused the perspective camera: ${prepared.error.toString()}`);
		return;
	}
	let expected: int32 = moved ? 5 : 4;
	let culled: int32 = 8 - expected;
	if (forward.core.opaque.count != expected || forward.core.culledCount != culled) {
		fail(
			`culling count at frame ${frameIndex}: opaque=${forward.core.opaque.count} ` +
			`culled=${forward.core.culledCount}, expected opaque=${expected} culled=${culled}`,
		);
	}
	if (prepared.value != expected) {
		fail("prepareFrame reported input length rather than the frustum-filtered count");
	}
	for (let node of nodes) {
		if (scene.nodes[node.index].flags.has(NodeFlag.Culled)) {
			fail("per-view culling changed a retained scene flag");
		}
	}
	let farBox: int32 = shifted ? 4 : 0;
	let nearBox: int32 = shifted ? 5 : 1;
	let sideBox: int32 = shifted ? 6 : 2;
	let nearest: int32 = checkPick(view, positions[farBox], nodes[nearBox]);
	let offcenter: int32 = checkPick(view, positions[sideBox], nodes[sideBox]);
	if (moved) { let _moved: int32 = checkPick(view, vec3(20.0, -2.0, -6.0), nodes[1]); }
	beginScreenPass(BACKGROUND);
	drawToScreen(forward, context);
	endPass();
	commit();
	if (frameIndex == 1 || frameIndex == 6 || frameIndex == 11 || frameIndex == 16) {
		if (voidCaptureGrab(0) == 0 || voidCaptureGrab(1) == 0) {
			fail("D3D11 readback failed");
		}
		if (voidCaptureSlotsDiffer() != 0) { fail("two readbacks of the same frame differ"); }
		checkBackground();
		checkLitPixel(view, positions[nearBox]);
		checkLitPixel(view, positions[sideBox]);
		if (moved) { checkLitPixel(view, vec3(20.0, -2.0, -6.0)); }
		console.log(
			`perspective frame: frame ${frameIndex} opaque=${forward.core.opaque.count} ` +
			`culled=${forward.core.culledCount} nearest=${nearest} offcenter=${offcenter}`,
		);
	}
	if (frameIndex == 16) {
		console.log(
			"PASS perspective frame: retained views, culling, " +
			"nearest and off-center picks, lit pixels",
		);
	}
}
