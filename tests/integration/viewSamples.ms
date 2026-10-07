import {
	embedRegister, viewCreate, viewFrame, viewSwapChain, setViewSampleCount,
	fbWidth, fbHeight, gfxSetup, ViewId,
} from "../../src/sokol/gpu";
import { setup2d, begin2d, fillQuad } from "../../src/void2d/draw";
import { currentContext } from "../../src/void2d/displayList";
import { vec2, rgba } from "../../src/void2d/types";
import { Vec4, vec3 } from "../../src/math/math3d";
import {
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
	Program,
} from "../../src/void3d/gpu3d";
import { endPass, commit, environmentSampleCount } from "../../src/gpu/door";
import { RenderState, BlendMode } from "../../src/gpu/state";
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
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	prepareFrame,
	drawToScreen,
} from "../../src/void3d/forwardRenderer";
import {
	voidCaptureGrabSwapChain,
	voidCapturePixel,
	voidCaptureEnvInt,
	voidCaptureExit,
} from "../capture/capture.h";

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const PRESENTED_BUFFER: int32 = 1;
const SCREEN_CLEAR: Vec4 = { x: 0.05, y: 0.05, z: 0.15, w: 1.0 };
const BOX_COLOR: Rgba = { red: 0.95, green: 0.55, blue: 0.2, alpha: 1.0 };
const WORLD_ON_HEIGHT: float32 = 3.0;
const QUAD_LEFT: int32 = 0;
const QUAD_TOP: int32 = 0;
const QUAD_RIGHT: int32 = 90;
const QUAD_BOTTOM: int32 = 90;
const RESOLVED_LOW: int32 = 40;
const RESOLVED_HIGH: int32 = 215;
const RESOLVED_ENOUGH: int32 = 40;

let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer = createForward();
let scene: Scene3D = Scene3D.create(context);
let items: Vec<DrawItem> = [];
let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let failures: int32 = 0;

function createForward(): ForwardRenderer {
	const created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, { x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	if (created.ok) { return created.value; }
	unreachable;
}

function check(ok: boolean, what: string): void {
	if (ok) { return; }
	console.log(`FAIL view samples: ${what}`);
	failures = failures + 1;
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

function initView(): void {
	gfxSetup();
	setup2d();
	buildScene();
}

function frameView(): void {
	const prepared: Result<int32, ForwardError> =
		prepareFrame(forward, items, camera, lights, fbWidth(), fbHeight());
	if (!prepared.ok) {
		check(false, `the 3D frame was refused, ${prepared.error.toString()}`);
		return;
	}
	begin2d(fbWidth() as float32, fbHeight() as float32, 1.0);
	fillQuad(
		vec2(45.0, 5.0), vec2(85.0, 45.0), vec2(45.0, 85.0), vec2(5.0, 45.0),
		rgba(1.0, 1.0, 1.0, 1.0), BlendMode.Alpha,
	);
	const overlay = currentContext();
	overlay.prepare();
	beginScreenPass(SCREEN_CLEAR);
	drawToScreen(forward);
	overlay.drawScreen();
	endPass();
	commit();
}

function redOf(x: int32, y: int32): int32 {
	return ((voidCapturePixel(0, x, y) >> (24 as int64)) & (255 as int64)) as int32;
}

function resolvedEdgePixels(): int32 {
	let between: int32 = 0;
	for (let y: int32 = QUAD_TOP; y < QUAD_BOTTOM; y++) {
		for (let x: int32 = QUAD_LEFT; x < QUAD_RIGHT; x++) {
			const red: int32 = redOf(x, y);
			if (red > RESOLVED_LOW && red < RESOLVED_HIGH) { between = between + 1; }
		}
	}
	return between;
}

function run(samples: int32, late: boolean): int32 {
	if (!late) { setViewSampleCount(samples); }
	embedRegister(initView, frameView);
	const view: ViewId = viewCreate(0 as int64, WIDTH, HEIGHT, 1.0);
	if (late) { setViewSampleCount(samples); }
	check(environmentSampleCount() == samples,
		`the device's pipelines use ${environmentSampleCount()} samples, asked ${samples}`);
	check(viewFrame(view), "viewFrame returned false");
	const grabbed: int32 = voidCaptureGrabSwapChain(0, viewSwapChain(view), PRESENTED_BUFFER);
	check(grabbed != 0, "readback failed");
	check(redOf(WIDTH / 2, HEIGHT / 2) != redOf(WIDTH - 4, 4), "the 3D box is missing");
	check(redOf(45, 45) > RESOLVED_HIGH, "the 2D quad is missing");
	const between: int32 = resolvedEdgePixels();
	if (samples == 1) {
		check(between == 0, `${between} edge pixels are partly covered with one sample`);
	} else {
		check(between >= RESOLVED_ENOUGH,
			`only ${between} edge pixels are partly covered with ${samples} samples`);
	}
	if (failures == 0) {
		console.log(`PASS view samples: ${samples} per pixel, void3d and void2d in one pass,`
			+ ` ${between} resolved edge pixels`);
	}
	return failures == 0 ? 0 : 1;
}

voidCaptureExit(run(
	voidCaptureEnvInt("VOID_VIEW_SAMPLES", 4),
	voidCaptureEnvInt("VOID_VIEW_SAMPLES_LATE", 0) != 0,
));
