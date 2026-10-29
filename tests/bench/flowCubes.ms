// The CPU flows of benchCubes' frame timed one by one: Scene3D's refresh, collectLights and the
// pass-list collect beginFrame runs per phase, with no window and no GPU. FLOW_CUBES_BEGIN=1 then
// opens a 64x64 window that draws nothing and times the core renderer's beginFrame, which needs a
// device for its stand-in and cluster textures. Each prints its median over FLOW_CUBES_FRAMES
// frames, so a change to one flow is proven by its own number before the windowed A/B. The
// meshes are external, so no vertex buffer is made; FLOW_CUBES_COUNT sets the cube count (1.6M,
// as benchCubes).

import { env, exit } from "std/process";
import { vec3, identityQuat, quatBetween } from "../../src/math/math3d";
import { gfxSetup } from "../../src/host/gpu";
import { commit } from "../../src/gpu/door";
import { RenderState } from "../../src/gpu/state";
import { Material, Phase, UniformBlock, pbrBlock } from "../../src/void3d/material";
import { PbrResponseError } from "../../src/void3d/pbrResponse";
import {
	Program, ProgramKey, MATERIAL_UNIFORM_SLOT, PBR_MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MaterialId, MaterialError, addMaterial, reserveUniforms,
	writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import {
	Renderer, RendererError, RENDERER_UNIFORM_LENGTH, beginFrame, setCameraPosition,
} from "../../src/void3d/renderer";
import { PassList, collect } from "../../src/void3d/passList";
import {
	Scene3D, NodeId3D, SceneError, Transform3D, LightInstance, LightKind, LightError,
	addMeshNode, addLightNode, refresh, collectLights,
} from "../../src/void3d/scene";
import { added, litShape } from "../../src/test/drawHelpers";
import { positiveEnv } from "./frameTimeLog";

@include("../../src/host/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

let context: DrawContext =
	DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH + PBR_MATERIAL_UNIFORM_LENGTH);
let scene: Scene3D = Scene3D.create(context);
let items: Vec<DrawItem> = [];
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let frames: int32 = positiveEnv("FLOW_CUBES_FRAMES", 15);
let began: Vec<float64> = [];
let beginFrames: int32 = 0;

function makeRenderer(): Renderer {
	const made: Result<Renderer, RendererError> = Renderer.create(context);
	if (made.ok) { return made.value; }
	unreachable;
}

let renderer: Renderer = makeRenderer();

function whiteMaterial(): MaterialId {
	const key: ProgramKey = ProgramKey.of(Program.Lit).withPbr();
	const values: Result<Vec<float32>, PbrResponseError> =
		pbrBlock(key, { metalness: 0.0, roughness: 0.5, occlusion: 1.0 });
	if (!values.ok) { unreachable; }
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, PBR_MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	if (!writeUniforms(context, reserved.value, values.value).ok) { unreachable; }
	const made: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.keyed(key, RenderState.defaults(), Phase.Opaque),
		uniforms: reserved.value,
	});
	if (made.ok) { return made.value; }
	unreachable;
}

function median(ref samples: Vec<float64>): float64 {
	samples.sort((a: float64, b: float64): number => a - b);
	return samples[(samples.length as int32) / 2];
}

function buildScene(count: int32): void {
	const mesh = added(context, litShape());
	const material: MaterialId = whiteMaterial();
	const side: int32 = Math.ceil(Math.sqrt(count as float64)) as int32;
	for (let i = 0; i < count; i++) {
		const local: Transform3D = {
			position: vec3(((i % side) as float32) * 2.0, 0.0, ((i / side) as float32) * 2.0),
			rotation: identityQuat(), scale: vec3(1.0, 1.0, 1.0),
		};
		const node: Result<NodeId3D, SceneError> =
			addMeshNode(scene, scene.rootId(), local, mesh, material);
		if (!node.ok) { unreachable; }
	}
	const sun: LightInstance = {
		kind: LightKind.Directional, color: vec3(1.0, 1.0, 1.0),
		radius: 0.0, power: 1.0, priority: 0,
	};
	const _sun: NodeId3D = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(),
		rotation: quatBetween(vec3(0.0, 0.0, 1.0), vec3(0.0, -1.0, -1.0).normalized()),
	}, sun);
	const eye = vec3(0.0, 40.0, -40.0);
	const camera: Camera3D = {
		position: eye, yaw: 0.0, pitch: 0.6, nearPlane: 0.1, farPlane: 1000.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 0.785398 },
	};
	const view: Result<CameraView, CameraError> = camera.resolve(1920, 1080);
	if (!view.ok) { unreachable; }
	view.value.writeCameraBlock(cameraValues);
	setCameraPosition(renderer, eye);
}

function cpuFlows(): void {
	let list: PassList = PassList.forPhase(Phase.Opaque);
	let refreshed: Vec<float64> = [];
	let lit: Vec<float64> = [];
	let collected: Vec<float64> = [];
	for (let frame = 0; frame <= frames; frame++) {
		const t0: float64 = performance.now();
		const _drawn: int32 = refresh(scene, items);
		const t1: float64 = performance.now();
		const light: Result<int32, LightError> = collectLights(scene, lights);
		if (!light.ok) { unreachable; }
		const t2: float64 = performance.now();
		collect(list, items, context.materials);
		const t3: float64 = performance.now();
		if (frame == 0) { continue; }
		refreshed.push(t1 - t0);
		lit.push(t2 - t1);
		collected.push(t3 - t2);
	}
	console.log(`flow.items ${items.length}`);
	console.log(`flow.refresh ${median(refreshed)} ms`);
	console.log(`flow.collectLights ${median(lit)} ms`);
	console.log(`flow.collect ${median(collected)} ms`);
}

function beginFrameFlow(): void {
	const t0: float64 = performance.now();
	const frameMade: Result<boolean, RendererError> =
		beginFrame(renderer, items, cameraValues, lights);
	const t1: float64 = performance.now();
	if (!frameMade.ok) {
		console.log(`flowCubes: beginFrame refused, ${frameMade.error.toString()}`);
		unreachable;
	}
	commit();
	if (beginFrames > 0) { began.push(t1 - t0); }
	beginFrames = beginFrames + 1;
	if (beginFrames > frames) {
		console.log(`flow.beginFrame ${median(began)} ms`);
		exit(0);
	}
}

buildScene(positiveEnv("FLOW_CUBES_COUNT", 1600000));
cpuFlows();
if (env.get("FLOW_CUBES_BEGIN") == "1") {
	voidRunConfigured(64, 64, 1, 0, gfxSetup, beginFrameFlow);
}
