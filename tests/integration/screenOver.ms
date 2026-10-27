import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { beginScreenPass } from "../../src/gpu/target";
import { endPass, commit } from "../../src/gpu/door";
import { RenderState } from "../../src/gpu/state";
import { Vec4, vec3 } from "../../src/math/math3d";
import {
	Program,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addBox } from "../../src/void3d/meshData";
import { UniformError } from "../../src/void3d/uniformPool";
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
	SceneError,
	LightError,
	LightKind,
	LightInstance,
	addMeshNode,
	addLightNode,
	refresh,
	collectLights,
} from "../../src/void3d/scene";
import { Camera3D, ProjectionKind, CameraView, CameraError } from "../../src/void3d/camera";
import { markChanged } from "../../src/void3d/renderer";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	prepareFrame,
	drawToScreen,
	drawOverScreen,
} from "../../src/void3d/forwardRenderer";
import {
	voidCaptureBackend,
	voidCaptureGrab,
	voidCapturePixel,
	voidCaptureEnvInt,
	voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");

extern function voidRunConfigured(
	w: int32,
	h: int32,
	sampleCount: int32,
	highDpi: int32,
	init: () => void,
	frame: () => void,
): void;

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const SCREEN_CLEAR: Vec4 = { x: 0.05, y: 0.05, z: 0.15, w: 1.0 };
const WORLD_BACKGROUND: Vec4 = { x: 0.1, y: 0.3, z: 0.1, w: 1.0 };
const TRANSPARENT: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
const WORLD_BOX: Rgba = { red: 0.95, green: 0.55, blue: 0.2, alpha: 1.0 };
const OVERLAY_BOX: Rgba = { red: 0.2, green: 0.5, blue: 0.95, alpha: 1.0 };
const WORLD_ON_HEIGHT: float32 = 3.0;
const WORLD_ONLY: int32 = 0;
const OVERLAY_ONLY: int32 = 1;
const COMPOSITE: int32 = 2;

let context: DrawContext = DrawContext.withUniformCapacity(
	2 * (FORWARD_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH),
);
let world: ForwardRenderer = createForward(WORLD_BACKGROUND);
let overlay: ForwardRenderer = createForward(TRANSPARENT);
let worldScene: Scene3D = Scene3D.create(context);
let overlayScene: Scene3D = Scene3D.create(context);
let worldItems: Vec<DrawItem> = [];
let overlayItems: Vec<DrawItem> = [];
let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let worldLights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let overlayLights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;

function createForward(background: Vec4): ForwardRenderer {
	const created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, background);
	if (created.ok) { return created.value; }
	unreachable;
}

function fail(message: string): void {
	console.log(`FAIL screen over: ${message}`);
	voidCaptureExit(1);
}

function litMaterial(): MaterialId {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	const levels: Vec<float32> = [4.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
	const written: Result<int32, UniformError> = writeUniforms(context, reserved.value, levels);
	if (!written.ok) { unreachable; }
	const plain: Material = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
	const added: Result<MaterialId, MaterialError> =
		addMaterial(context, { ...plain, uniforms: reserved.value });
	if (!added.ok) { unreachable; }
	return added.value;
}

function buildScene(
	scene: Scene3D, ref items: Vec<DrawItem>, ref lights: Vec<float32>, x: float32, color: Rgba,
): void {
	let data: MeshData = MeshData.empty();
	const boxed: Result<int32, MeshError> = addBox(data, {
		base: vec3(x, -0.5, 0.0),
		size: vec3(1.0, 1.0, 1.0),
		yaw: 0.6,
		tilt: 0.0,
		color: color,
	});
	if (!boxed.ok) { unreachable; }
	const mesh: Result<MeshId, MeshUploadError> = addMeshData(context, data);
	if (!mesh.ok) { unreachable; }
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, scene.rootId(), Transform3D.identity(), mesh.value, litMaterial());
	if (!placed.ok) { unreachable; }
	const sun: LightInstance = {
		kind: LightKind.Directional,
		color: vec3(1.0, 1.0, 1.0),
		radius: 0.0,
		power: 1.0,
		priority: 0,
	};
	const _lit: NodeId3D = addLightNode(scene, scene.rootId(), Transform3D.identity(), sun);
	const _drawn: int32 = refresh(scene, items);
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { unreachable; }
}

function writeCamera(): void {
	let view: Camera3D = {
		position: vec3(0.0, 0.0, 0.0),
		yaw: 0.0,
		pitch: 0.5,
		orientation: null,
		projection: {
			kind: ProjectionKind.Orthographic,
			worldPerTexel: WORLD_ON_HEIGHT / (HEIGHT as float32),
			snap: false,
		},
		nearPlane: -10.0,
		farPlane: 10.0,
	};
	const resolved: Result<CameraView, CameraError> = view.resolve(WIDTH, HEIGHT);
	if (!resolved.ok) { unreachable; }
	resolved.value.writeCameraBlock(camera);
}

function init(): void {
	gfxSetup();
	buildScene(worldScene, worldItems, worldLights, -0.9, WORLD_BOX);
	buildScene(overlayScene, overlayItems, overlayLights, 0.4, OVERLAY_BOX);
	writeCamera();
}

function prepare(renderer: ForwardRenderer, items: Span<DrawItem>, lights: Vec<float32>): void {
	const prepared: Result<int32, ForwardError> =
		prepareFrame(renderer, items, camera, lights, fbWidth(), fbHeight());
	if (!prepared.ok) { fail(`a 3D frame was refused, ${prepared.error.toString()}`); }
	markChanged(renderer.core);
}

function draw(slot: int32): void {
	const withWorld: boolean = slot != OVERLAY_ONLY;
	const withOverlay: boolean = slot != WORLD_ONLY;
	if (withWorld) { prepare(world, worldItems, worldLights); }
	if (withOverlay) { prepare(overlay, overlayItems, overlayLights); }
	beginScreenPass(SCREEN_CLEAR);
	if (withWorld) { drawToScreen(world); }
	if (withOverlay) {
		if (voidCaptureEnvInt("VOID_SCREEN_OVER_REPLACE", 0) != 0) {
			drawToScreen(overlay);
		} else {
			drawOverScreen(overlay);
		}
	}
	endPass();
	commit();
}

function rgb(pixel: int64): int64 { return pixel >> 8; }

function checkComposite(): void {
	const backdrop: int64 = rgb(voidCapturePixel(OVERLAY_ONLY, 4, 4));
	let underneath: int32 = 0;
	let covered: int32 = 0;
	for (let y = 0; y < HEIGHT; y++) {
		for (let x = 0; x < WIDTH; x++) {
			const alone: int64 = rgb(voidCapturePixel(OVERLAY_ONLY, x, y));
			const want: int64 = alone == backdrop
				? rgb(voidCapturePixel(WORLD_ONLY, x, y))
				: alone;
			if (rgb(voidCapturePixel(COMPOSITE, x, y)) != want) {
				fail(`pixel ${x},${y} is not the overlay over the world`);
				return;
			}
			if (alone == backdrop) { underneath = underneath + 1; } else { covered = covered + 1; }
		}
	}
	if (covered == 0 || underneath == 0) {
		fail(`the overlay covered ${covered} pixels and left ${underneath}`);
		return;
	}
	console.log(`screen over: ${covered} pixels of the overlay, ${underneath} of the world`);
}

function frame(): void {
	const hold: int32 = voidCaptureEnvInt("VOID_SCREEN_OVER_HOLD", 0);
	if (hold > 0) {
		draw(COMPOSITE);
		stage = stage + 1;
		if (stage >= hold) { voidCaptureExit(0); }
		return;
	}
	draw(stage);
	if (voidCaptureGrab(stage) == 0) { fail(`capture slot ${stage} failed`); }
	stage = stage + 1;
	if (stage <= COMPOSITE) { return; }
	checkComposite();
	console.log("PASS screen over: a transparent second preset composites over the first");
	voidCaptureExit(0);
}

if (voidCaptureEnvInt("VOID_SCREEN_OVER_HOLD", 0) == 0 && voidCaptureBackend() == 0) {
	console.log("SKIP screen over: this build has no readback path");
	voidCaptureExit(3);
}
voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
