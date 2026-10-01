import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec4, vec3 } from "../../src/math/math3d";
import { RenderState, BlendMode } from "../../src/gpu/state";
import { SWAPCHAIN_LAYOUT, beginScreenPass } from "../../src/gpu/target";
import {
	endPass,
	commit,
	contextGeneration,
	liveShaders,
	livePipelines,
	liveBuffers,
	liveImages,
	liveViews,
	liveSamplers,
} from "../../src/gpu/door";
import {
	PipelineCache,
	PipelineKey,
	releasePipelines,
	closePipelines,
} from "../../src/gpu/pipeline";
import {
	Program,
	VertexLayout,
	vertexLayoutOf,
	pipelineFor,
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
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addBox } from "../../src/void3d/meshData";
import { UniformError } from "../../src/void3d/uniformPool";
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
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	prepareFrame,
	drawToScreen,
} from "../../src/void3d/forwardRenderer";
import { Camera3D, ProjectionKind, CameraView, CameraError } from "../../src/void3d/camera";
import {
	voidCaptureBackend,
	voidCaptureGrab,
	voidCapturePixel,
	voidCaptureSlotsDiffer,
	voidCaptureUniform,
	voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

struct Counts {
	shaders: int32;
	pipelines: int32;
	buffers: int32;
	images: int32;
	views: int32;
	samplers: int32;
}

struct PipelineSpec {
	program: Program;
	indexed: boolean;
	mode: BlendMode;
}

struct PassHolder {
	pipelines: PipelineCache;
}

const WIDTH: int32 = 160;
const HEIGHT: int32 = 120;
const SCREEN_CLEAR: Vec4 = { x: 0.05, y: 0.05, z: 0.15, w: 1.0 };
const BOX_COLOR: Rgba = { red: 0.95, green: 0.55, blue: 0.2, alpha: 1.0 };
const FIRST: int32 = 0;
const LATER: int32 = 1;

let contextA: DrawContext = DrawContext.withUniformCapacity(MATERIAL_UNIFORM_LENGTH);
let held: PassHolder = { pipelines: PipelineCache.empty() };
let contextB: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer = createForward();
let scene: Scene3D = Scene3D.create();
let items: Vec<DrawItem> = [];
let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;
let failures: int32 = 0;
let baseline: Counts = zeroCounts();
let steady: Counts = zeroCounts();
let shadersOfA: int32 = 0;
let pipelinesOfA: int32 = 0;
let rebuilt: Vec<uint32> = [];

function zeroCounts(): Counts {
	return { shaders: 0, pipelines: 0, buffers: 0, images: 0, views: 0, samplers: 0 };
}

function counts(): Counts {
	return {
		shaders: liveShaders(),
		pipelines: livePipelines(),
		buffers: liveBuffers(),
		images: liveImages(),
		views: liveViews(),
		samplers: liveSamplers(),
	};
}

function describe(c: Counts): string {
	return `shaders ${c.shaders} pipelines ${c.pipelines} buffers ${c.buffers} ` +
		`images ${c.images} views ${c.views} samplers ${c.samplers}`;
}

function specs(): Vec<PipelineSpec> {
	return [
		{ program: Program.Copy, indexed: false, mode: BlendMode.None },
		{ program: Program.Copy, indexed: false, mode: BlendMode.Alpha },
		{ program: Program.Copy, indexed: false, mode: BlendMode.Add },
		{ program: Program.Lit, indexed: true, mode: BlendMode.None },
	];
}

function pipelineOf(cache: PipelineCache, spec: PipelineSpec): uint32 {
	const layout: VertexLayout = vertexLayoutOf(spec.program);
	const state: RenderState = RenderState.defaults().withBlendMode(spec.mode);
	return pipelineFor(cache, spec.program, layout, spec.indexed, state, SWAPCHAIN_LAYOUT);
}

function shadersHeld(cache: PipelineCache): int32 {
	let count: int32 = 0;
	for (let i = 0; i < (cache.shaders.length as int32); i++) {
		if (cache.shaders[i] != 0) { count = count + 1; }
	}
	return count;
}

function pipelinesHeld(cache: PipelineCache): int32 {
	let count: int32 = 0;
	for (let i = 0; i < (cache.entries.length as int32); i++) {
		if (cache.entries[i].pipeline != 0) { count = count + 1; }
	}
	return count;
}

function createForward(): ForwardRenderer {
	const created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(contextB, { x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	if (created.ok) { return created.value; }
	unreachable;
}

function stop(message: string): void {
	console.log(`FAIL pipeline cache owner: ${message}`);
	voidCaptureExit(1);
}

function check(axis: string, ok: boolean, detail: string): void {
	if (ok) {
		console.log(`PASS pipeline cache owner ${axis}`);
		return;
	}
	failures = failures + 1;
	console.log(`FAIL pipeline cache owner ${axis}: ${detail}`);
}

function litMaterial(): MaterialId {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(contextB, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	const levels: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	const written: Result<int32, UniformError> = writeUniforms(contextB, reserved.value, levels);
	if (!written.ok) { unreachable; }
	const plain: Material = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
	const added: Result<MaterialId, MaterialError> =
		addMaterial(contextB, { ...plain, uniforms: reserved.value });
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
	const mesh: Result<MeshId, MeshUploadError> = addMeshData(contextB, data);
	if (!mesh.ok) { unreachable; }
	const material: MaterialId = litMaterial();
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, contextB, scene.rootId(), Transform3D.identity(), mesh.value, material);
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
			worldPerTexel: 3.0 / (HEIGHT as float32),
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
	buildScene();
	baseline = counts();
}

function drawB(slot: int32): void {
	const prepared: Result<int32, ForwardError> =
		prepareFrame(forward, contextB, items, camera, lights, fbWidth(), fbHeight());
	if (!prepared.ok) {
		stop(`cache B's frame was refused, ${prepared.error.toString()}`);
		return;
	}
	beginScreenPass(SCREEN_CLEAR);
	drawToScreen(forward, contextB);
	endPass();
	commit();
	if (voidCaptureGrab(slot) == 0) { stop("D3D11 readback failed"); }
}

function checkFirstPicture(): void {
	const background: int64 = voidCapturePixel(FIRST, 2, 2);
	const box: int64 = voidCapturePixel(FIRST, WIDTH / 2, HEIGHT / 2);
	if (voidCaptureUniform(FIRST) != 0 || box == background) {
		stop(`cache B drew no box: background ${background}, centre ${box}`);
	}
}

function populateA(): void {
	const before: Counts = counts();
	for (const spec of specs()) { const _made: uint32 = pipelineOf(contextA.pipelines, spec); }
	const after: Counts = counts();
	shadersOfA = shadersHeld(contextA.pipelines);
	pipelinesOfA = pipelinesHeld(contextA.pipelines);
	if (shadersOfA != 2 || pipelinesOfA != 4 ||
		after.shaders - before.shaders != shadersOfA ||
		after.pipelines - before.pipelines != pipelinesOfA) {
		stop(`cache A holds ${shadersOfA} shaders and ${pipelinesOfA} pipelines; ` +
			`the door counted ${describe(before)} before and ${describe(after)} after`);
	}
}

function aliasGeneration(): void {
	const real: int32 = contextA.pipelines.generation;
	contextA.pipelines.generation = real + 7;
	const seen: int32 = held.pipelines.generation;
	held.pipelines.generation = real;
	const back: int32 = contextA.pipelines.generation;
	contextA.pipelines.generation = real;
	check("(a) generation written through one alias reads back through the other",
		seen == real + 7 && back == real,
		`wrote ${real + 7} through the context, the holder read ${seen}; ` +
		`wrote ${real} through the holder, the context read ${back}`);
}

function releaseThroughBoth(): void {
	const before: Counts = counts();
	releasePipelines(contextA.pipelines);
	const middle: Counts = counts();
	const heldShaders: int32 = shadersHeld(held.pipelines);
	const heldPipelines: int32 = pipelinesHeld(held.pipelines);
	releasePipelines(held.pipelines);
	const after: Counts = counts();
	check("(b) release through one alias destroys A's objects once, the other destroys nothing",
		before.shaders - middle.shaders == shadersOfA &&
		before.pipelines - middle.pipelines == pipelinesOfA &&
		heldShaders == 0 && heldPipelines == 0 &&
		after.shaders == middle.shaders && after.pipelines == middle.pipelines,
		`A held ${shadersOfA} shaders and ${pipelinesOfA} pipelines; ${describe(before)} -> ` +
		`${describe(middle)} -> ${describe(after)}; after the first release the holder still ` +
		`held ${heldShaders} shaders and ${heldPipelines} pipelines`);
}

function rebuildStale(): void {
	contextA.pipelines.generation = contextGeneration() + 1;
	const before: Counts = counts();
	rebuilt = [];
	for (const spec of specs()) { rebuilt.push(pipelineOf(held.pipelines, spec)); }
	const after: Counts = counts();
	const adopted: boolean = contextA.pipelines.generation == contextGeneration() &&
		pipelinesHeld(contextA.pipelines) == pipelinesOfA &&
		shadersHeld(contextA.pipelines) == shadersOfA;
	let same: boolean = true;
	const list: Vec<PipelineSpec> = specs();
	for (let i = 0; i < (list.length as int32); i++) {
		if (pipelineOf(contextA.pipelines, list[i]) != rebuilt[i]) { same = false; }
	}
	const reused: Counts = counts();
	check("(c) a stale epoch rebuilt through one alias is the state the other reads",
		after.shaders - before.shaders == shadersOfA &&
		after.pipelines - before.pipelines == pipelinesOfA &&
		adopted && same &&
		reused.shaders == after.shaders && reused.pipelines == after.pipelines,
		`${describe(before)} -> ${describe(after)} -> ${describe(reused)}; the context reads ` +
		`generation ${contextA.pipelines.generation} of ${contextGeneration()}, ` +
		`${pipelinesHeld(contextA.pipelines)} pipelines, same handles ${same}`);
}

function closeThroughAlias(): void {
	const key: PipelineKey = contextA.pipelines.entries[0].key;
	const before: Counts = counts();
	closePipelines(contextA.pipelines);
	const after: Counts = counts();
	check("(e) close through one alias destroys A's objects, and the other reads it closed",
		before.shaders - after.shaders == shadersOfA &&
		before.pipelines - after.pipelines == pipelinesOfA &&
		held.pipelines.isClosed() && !held.pipelines.contains(key),
		`A held ${shadersOfA} shaders and ${pipelinesOfA} pipelines; ${describe(before)} -> ` +
		`${describe(after)}; the holder reads closed ${held.pipelines.isClosed()}`);
}

function closeB(): void {
	closePipelines(contextB.pipelines);
	const after: Counts = counts();
	check("(d) cache B drew the same picture throughout, and every count is back",
		after.shaders == baseline.shaders && after.pipelines == baseline.pipelines &&
		after.buffers == steady.buffers && after.images == steady.images &&
		after.views == steady.views && after.samplers == steady.samplers,
		`shaders and pipelines at init: ${describe(baseline)}; the rest after B's first frame: ` +
		`${describe(steady)}; now ${describe(after)}`);
}

function sameAsFirst(when: string): void {
	const differ: int32 = voidCaptureSlotsDiffer();
	if (differ != 0) { stop(`cache B's picture changed ${when}: ${differ} pixels differ`); }
}

function frame(): void {
	if (stage == 0) {
		populateA();
		held = { pipelines: contextA.pipelines };
		drawB(FIRST);
		checkFirstPicture();
		steady = counts();
		aliasGeneration();
		releaseThroughBoth();
	} else if (stage == 1) {
		drawB(LATER);
		sameAsFirst("after A was released");
		rebuildStale();
	} else if (stage == 2) {
		drawB(LATER);
		sameAsFirst("after A was rebuilt");
		closeThroughAlias();
	} else {
		drawB(LATER);
		sameAsFirst("after A was closed");
		closeB();
		if (failures != 0) {
			console.log(`FAIL pipeline cache owner: ${failures} axes failed`);
			voidCaptureExit(1);
		}
		console.log("PASS pipeline cache owner: one cache through two aliases, an independent " +
			"cache drawing throughout");
		voidCaptureExit(0);
	}
	stage = stage + 1;
}

if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
