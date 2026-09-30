import {
	registrationPreload,
	foreignProgram,
	foreignLayout,
	drawForeign,
} from "./gpuRegistrationFixture";
import { PipelineCache, pipelineFor } from "../../src/gpu/pipeline";
import { SWAPCHAIN_LAYOUT } from "../../src/gpu/target";
import { screenState } from "../../src/void3d/screenFx";
import { openScreen } from "../../src/void3d/renderer";
import { gfxSetup, fbWidth, fbHeight, commit } from "../../src/sokol/gpu";
import {
	setup2d,
	begin2d,
	fillQuad,
	drawCallCount,
} from "../../src/void2d/draw";
import { currentContext } from "../../src/void2d/displayList";
import { BlendMode, vec2, rgba } from "../../src/void2d/types";
import { Vec4, vec3 } from "../../src/math/math3d";
import {
	Program,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import { endPass } from "../../src/gpu/door";
import { RenderState } from "../../src/gpu/state";
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
import { beginScreenPass } from "../../src/gpu/target";
import { markChanged } from "../../src/void3d/renderer";
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
	voidCaptureUniform,
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
const BOX_COLOR: Rgba = { red: 0.95, green: 0.55, blue: 0.2, alpha: 1.0 };
const WORLD_ON_HEIGHT: float32 = 3.0;
const QUAD_ALPHA: float32 = 0.5;
const QUAD_RED: float32 = 0.15;
const QUAD_GREEN: float32 = 0.72;
const QUAD_BLUE: float32 = 0.92;
const QUAD_LEFT: float32 = 100.0;
const QUAD_TOP: float32 = 60.0;
const QUAD_RIGHT: float32 = 190.0;
const QUAD_BOTTOM: float32 = 140.0;
const WITH_QUAD: int32 = 0;
const WITHOUT_QUAD: int32 = 1;

let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer = createForward();
let scene: Scene3D = Scene3D.create();
let items: Vec<DrawItem> = [];
let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;
let foreignCache: PipelineCache = PipelineCache.empty();

function createForward(): ForwardRenderer {
	const created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, { x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	if (created.ok) { return created.value; }
	unreachable;
}

function fail(message: string): void {
	console.log(`FAIL mixed frame: ${message}`);
	voidCaptureExit(1);
}

function litMaterial(): MaterialId {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	const levels: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	const written: Result<int32, UniformError> = writeUniforms(context, reserved.value, levels);
	if (!written.ok) { unreachable; }
	const plain: Material = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
	const added: Result<MaterialId, MaterialError> =
		addMaterial(context, { ...plain, uniforms: reserved.value });
	if (!added.ok) { unreachable; }
	return added.value;
}

function buildScene(): void {
	let data: MeshData = MeshData.empty();
	const boxed: Result<int32, MeshError> = addBox(data, {
		base: vec3(0.0, -0.5, 0.0),
		size: vec3(1.2, 1.0, 1.2),
		yaw: 0.6,
		tilt: 0.0,
		color: BOX_COLOR,
	});
	if (!boxed.ok) { unreachable; }
	const mesh: Result<MeshId, MeshUploadError> = addMeshData(context, data);
	if (!mesh.ok) { unreachable; }
	const material: MaterialId = litMaterial();
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, context, scene.rootId(), Transform3D.identity(), mesh.value, material);
	if (!placed.ok) { unreachable; }
	const sun: LightInstance = {
		kind: LightKind.Directional,
		color: vec3(1.0, 1.0, 1.0),
		radius: 0.0,
		power: 1.0,
		priority: 0,
	};
	const lit: NodeId3D =
		addLightNode(scene, scene.rootId(), Transform3D.identity(), sun);
	const _drawn: int32 = refresh(scene, items);
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { unreachable; }
	let view: Camera3D = {
		position: vec3(0.0, 0.0, 0.0),
		yaw: 0.5,
		pitch: 0.5,
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

function initMixed(): void {
	gfxSetup();
	setup2d();
	buildScene();
	if (voidCaptureEnvInt("VOID_GPU_REGISTRATION", 0) != 0) {
		let program: int32 = foreignProgram();
		let layout: int32 = foreignLayout();
		let before: boolean = voidCaptureEnvInt("VOID_GPU_REGISTRATION", 0) == 2;
		if ((registrationPreload >= 0) != before) {
			fail("the registration preload ran in the wrong order");
		}
		if ((before && (program != 4 || layout != 2)) ||
			(!before && (program != 15 || layout != 7))) {
			fail("the foreign consumer did not reach the expected registry boundary");
		}
	}
}

function drawMixed(withQuad: boolean): void {
	const prepared: Result<int32, ForwardError> =
		prepareFrame(forward, context, items, camera, lights, fbWidth(), fbHeight());
	if (!prepared.ok) {
		fail(`the 3D frame was refused, ${prepared.error.toString()}`);
		return;
	}
	if (voidCaptureEnvInt("VOID_MIXED_PREPARE_TWICE", 0) != 0) {
		const _again: Result<int32, ForwardError> =
			prepareFrame(forward, context, items, camera, lights, fbWidth(), fbHeight());
	}
	markChanged(forward.core);
	const swapped: boolean = voidCaptureEnvInt("VOID_MIXED_3D_OVER_2D", 0) != 0;
	begin2d(fbWidth() as float32, fbHeight() as float32, 1.0);
	if (withQuad) {
		fillQuad(
			vec2(QUAD_LEFT, QUAD_TOP), vec2(QUAD_RIGHT, QUAD_TOP),
			vec2(QUAD_RIGHT, QUAD_BOTTOM), vec2(QUAD_LEFT, QUAD_BOTTOM),
			rgba(QUAD_RED, QUAD_GREEN, QUAD_BLUE, QUAD_ALPHA), BlendMode.Alpha,
		);
	}
	const overlay = currentContext();
	overlay.prepare();
	beginScreenPass(SCREEN_CLEAR);
	if (!swapped) {
		if (voidCaptureEnvInt("VOID_GPU_REGISTRATION", 0) != 0 && stage == 1) {
			openScreen(forward.core);
			let pipeline: uint32 = pipelineFor(
				foreignCache, foreignProgram(), foreignLayout(), false,
				screenState(), SWAPCHAIN_LAYOUT,
			);
			let reused: uint32 = pipelineFor(
				foreignCache, foreignProgram(), foreignLayout(), false,
				screenState(), SWAPCHAIN_LAYOUT,
			);
			if (pipeline != reused) { fail("the door did not reuse the foreign pipeline"); }
			drawForeign(pipeline, forward.colorTarget.texture, forward.sampler.handle);
		} else {
			drawToScreen(forward, context);
		}
	}
	overlay.drawScreen();
	if (swapped) { drawToScreen(forward, context); }
	endPass();
	commit();
	if (!forward.core.needsFrame()) {
		fail("a change marked between prepareFrame and drawToScreen was lost");
	}
}

function drawAcrossCommit(): void {
	if (stage == 0) {
		const prepared: Result<int32, ForwardError> =
			prepareFrame(forward, context, items, camera, lights, fbWidth(), fbHeight());
		if (!prepared.ok) {
			fail(`the 3D frame was refused, ${prepared.error.toString()}`);
			return;
		}
		beginScreenPass(SCREEN_CLEAR);
		endPass();
		commit();
		stage = 1;
		return;
	}
	beginScreenPass(SCREEN_CLEAR);
	drawToScreen(forward, context);
	endPass();
	commit();
	fail("drawToScreen drew a frame prepared before the last commit");
}

function grab(slot: int32): void {
	if (voidCaptureGrab(slot) == 0) {
		fail(`capture slot ${slot} failed`);
	}
}

function channel(pixel: int64, shift: int64): int32 {
	return ((pixel >> shift) & 255) as int32;
}

function near(got: int32, want: float32): boolean {
	const difference: float32 = (got as float32) - want;
	return difference <= 1.0 && difference >= -1.0;
}

function premultipliedOver(over: int64, under: int64): boolean {
	const keep: float32 = 1.0 - QUAD_ALPHA;
	const red: float32 = QUAD_RED * QUAD_ALPHA * 255.0 + (channel(under, 24) as float32) * keep;
	const green: float32 = QUAD_GREEN * QUAD_ALPHA * 255.0 + (channel(under, 16) as float32) * keep;
	const blue: float32 = QUAD_BLUE * QUAD_ALPHA * 255.0 + (channel(under, 8) as float32) * keep;
	return near(channel(over, 24), red) && near(channel(over, 16), green)
		&& near(channel(over, 8), blue);
}

function inQuad(x: int32, y: int32): boolean {
	const fx: float32 = x as float32;
	const fy: float32 = y as float32;
	return fx >= QUAD_LEFT && fx < QUAD_RIGHT && fy >= QUAD_TOP && fy < QUAD_BOTTOM;
}

function checkComposition(): void {
	const background: int64 = voidCapturePixel(WITHOUT_QUAD, 4, 4);
	const boxCentre: int64 = voidCapturePixel(WITHOUT_QUAD, WIDTH / 2, HEIGHT / 2);
	if (boxCentre == background) {
		fail("the 3D pass left nothing at the centre of the frame");
		return;
	}
	let outside: int32 = 0;
	let blended: int32 = 0;
	let wrong: int32 = 0;
	for (let y = 0; y < HEIGHT; y++) {
		for (let x = 0; x < WIDTH; x++) {
			const over: int64 = voidCapturePixel(WITH_QUAD, x, y);
			const under: int64 = voidCapturePixel(WITHOUT_QUAD, x, y);
			if (!inQuad(x, y)) {
				if (over != under) { outside = outside + 1; }
			} else if (premultipliedOver(over, under)) {
				blended = blended + 1;
			} else {
				wrong = wrong + 1;
			}
		}
	}
	if (outside != 0) {
		fail(`${outside} pixels outside the quad differ from the frame drawn without it`);
		return;
	}
	if (wrong != 0) {
		fail(`${wrong} pixels inside the quad are not the quad blended over the 3D frame`);
		return;
	}
	console.log(`mixed frame: ${blended} pixels of the quad blended over the 3D frame`);
}

function frame(): void {
	if (voidCaptureEnvInt("VOID_MIXED_SCREEN_NEXT_FRAME", 0) != 0) {
		drawAcrossCommit();
		return;
	}
	const withQuad: boolean = stage != 2;
	drawMixed(withQuad);
	const draws: int32 = withQuad ? 1 : 0;
	if (drawCallCount() != draws) {
		fail(`void2d draw counter is ${drawCallCount()} in frame ${stage}, expected ${draws}`);
	}
	grab(stage == 2 ? WITHOUT_QUAD : stage);
	stage = stage + 1;
	if (stage == 2) {
		if (voidCaptureUniform(0) != 0 || voidCaptureUniform(1) != 0) {
			fail("a composed frame is uniform");
		}
		const differ: int32 = voidCaptureSlotsDiffer();
		if (differ != 0) {
			fail(`the two fixed-state frames differ in ${differ} pixels`);
		}
		return;
	}
	if (stage < 3) { return; }
	checkComposition();
	console.log("PASS mixed frame: forward preset + void2d, one screen pass, one commit");
	voidCaptureExit(0);
}

function start(): void {
	if (voidCaptureBackend() == 0) {
		console.log("SKIP mixed frame: this build has no readback path");
		voidCaptureExit(3);
	}
	voidRunConfigured(WIDTH, HEIGHT, 1, 0, initMixed, frame);
}

start();
