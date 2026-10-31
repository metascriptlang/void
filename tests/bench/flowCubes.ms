// The CPU flows of benchCubes' frame timed one by one: Scene3D's refresh, collectLights and the
// pass lists beginFrame fills and culls in one walk, with no window and no GPU.
// FLOW_CUBES_BEGIN=1 then opens a 64x64 window that draws nothing and times the core renderer's
// beginFrame, which needs a device for its stand-in and cluster textures. Each prints its median
// over FLOW_CUBES_FRAMES frames, so a change to one flow is proven by its own number before the
// windowed A/B. The meshes are external, so no vertex buffer is made; FLOW_CUBES_COUNT sets the
// cube count (1.6M, as benchCubes). `flow.refreshMoving` times refresh on frames where ten
// cubes move; FLOW_CUBES_GROUP=n puts the cubes under groups of n, so the move descends into one
// group instead of the root's every child. FLOW_CUBES_SORT=1 adds `flow.sortByMaterial`, the
// opaque list's sort after collectVisible; FLOW_CUBES_SHADOW=1 makes the cubes cast and adds
// `flow.shadowLayers`, a four-cascade sun's CPU work per frame (collectCasters, filterFrustum
// and sortCasters for each layer, as DirShadowMap's drawLayers runs them, with no pass) and,
// once, `flow.shadowLayer<i> <casters>` for each layer's caster count.

import { env, exit } from "std/process";
import { Mat4, vec3, identityQuat, quatBetween } from "../../src/math/math3d";
import { Frustum3D } from "../../src/void3d/frustum";
import { gfxSetup } from "../../src/host/gpu";
import { commit } from "../../src/gpu/door";
import { RenderState } from "../../src/gpu/state";
import { Material, Phase, ShadowCasting, UniformBlock, pbrBlock } from "../../src/void3d/material";
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
import {
	PassList, collectVisible, collectCasters, filterFrustum, sortCasters, sortByMaterial,
} from "../../src/void3d/passList";
import {
	CascadeConfig, CascadeError, Cascade, cascadeBounds, cascadesOf,
} from "../../src/void3d/cascades";
import { lightBasis } from "../../src/void3d/dirShadowMap";
import {
	Scene3D, NodeId3D, SceneError, Transform3D, LightInstance, LightKind, LightError,
	addMeshNode, addLightNode, addGroup, refresh, collectLights, setLocal,
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
let movers: Vec<NodeId3D> = [];
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
		castShadows: env.get("FLOW_CUBES_SHADOW") == "1" ? ShadowCasting.On : ShadowCasting.Off,
		uniforms: reserved.value,
	});
	if (made.ok) { return made.value; }
	unreachable;
}

function median(ref samples: Vec<float64>): float64 {
	samples.sort((a: float64, b: float64): number => a - b);
	return samples[(samples.length as int32) / 2];
}

const SUN_EYE = vec3(0.0, 40.0, -40.0);

function benchCamera(): CameraView {
	const camera: Camera3D = {
		position: SUN_EYE, yaw: 0.0, pitch: 0.6, nearPlane: 0.1, farPlane: 1000.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 0.785398 },
	};
	const view: Result<CameraView, CameraError> = camera.resolve(1920, 1080);
	if (view.ok) { return view.value; }
	unreachable;
}

function buildScene(count: int32): void {
	const mesh = added(context, litShape());
	const material: MaterialId = whiteMaterial();
	const side: int32 = Math.ceil(Math.sqrt(count as float64)) as int32;
	const group: int32 = positiveEnv("FLOW_CUBES_GROUP", count);
	let under: NodeId3D = scene.rootId();
	for (let i = 0; i < count; i++) {
		if (group < count && i % group == 0) {
			under = addGroup(scene, scene.rootId(), Transform3D.identity());
		}
		const local: Transform3D = {
			position: vec3(((i % side) as float32) * 2.0, 0.0, ((i / side) as float32) * 2.0),
			rotation: identityQuat(), scale: vec3(1.0, 1.0, 1.0),
		};
		const node: Result<NodeId3D, SceneError> =
			addMeshNode(scene, under, local, mesh, material);
		if (!node.ok) { unreachable; }
		if (i < 10) { movers.push(node.value); }
	}
	const sun: LightInstance = {
		kind: LightKind.Directional, color: vec3(1.0, 1.0, 1.0),
		radius: 0.0, power: 1.0, priority: 0,
	};
	const _sun: NodeId3D = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(),
		rotation: quatBetween(vec3(0.0, 0.0, 1.0), vec3(0.0, -1.0, -1.0).normalized()),
	}, sun);
	benchCamera().writeCameraBlock(cameraValues);
	setCameraPosition(renderer, SUN_EYE);
}

function sortFlow(
	ref opaque: PassList, ref alpha: PassList, ref additive: PassList, ref decal: PassList,
	ref toneMapped: PassList,
	frustum: Frustum3D,
): void {
	let drawn: Vec<ProgramKey> = [];
	for (let i = 0; i < (context.materials.length as int32); i++) {
		drawn.push(ProgramKey.of(Program.Lit).withPbr());
	}
	let sorted: Vec<float64> = [];
	for (let frame = 0; frame <= frames; frame++) {
		const _culled: int32 = collectVisible(opaque, alpha, additive, decal, toneMapped, items,
			context.materials, context.meshData, frustum);
		const t0: float64 = performance.now();
		sortByMaterial(opaque, items, drawn, context.materials);
		const t1: float64 = performance.now();
		if (frame > 0) { sorted.push(t1 - t0); }
	}
	console.log(`flow.sortByMaterial ${opaque.count} ${median(sorted)} ms`);
}

function shadowFlow(): void {
	const view: CameraView = benchCamera();
	const toLight = vec3(0.0, 1.0, 1.0).normalized();
	const basis = lightBasis(toLight);
	const side: float32 = Math.ceil(Math.sqrt((items.length as int32) as float64)) as float32;
	let casterNear: float32 = 1.0e30;
	for (let corner = 0; corner < 4; corner++) {
		const x: float32 = (corner & 1) == 0 ? -1.0 : side * 2.0;
		const z: float32 = (corner & 2) == 0 ? -1.0 : side * 2.0;
		casterNear = Math.min(casterNear, vec3(x, -1.0, z).dot(basis.forward));
	}
	const config: CascadeConfig =
		{ bounds: cascadeBounds(4, 10.0, 150.0), overlap: 0.2, minimumDistance: 0.1 };
	const made: Result<Vec<Cascade>, CascadeError> =
		cascadesOf(config, view.inverseViewProj, view.eye, basis, 2048, casterNear);
	if (!made.ok) { unreachable; }
	let frusta: Vec<Frustum3D> = [];
	for (const cascade of made.value) { frusta.push(Frustum3D.fromMatrix(cascade.clipFromWorld)); }
	let casters: PassList = PassList.forPhase(Phase.Opaque);
	let layered: Vec<float64> = [];
	for (let frame = 0; frame <= frames; frame++) {
		const t0: float64 = performance.now();
		for (let layer = 0; layer < (frusta.length as int32); layer++) {
			collectCasters(casters, items, context.materials);
			const _culled: int32 =
				filterFrustum(casters, items, context.meshData, frusta[layer]);
			sortCasters(casters, items);
			if (frame == 0) { console.log(`flow.shadowLayer${layer} ${casters.count}`); }
		}
		const t1: float64 = performance.now();
		if (frame > 0) { layered.push(t1 - t0); }
	}
	console.log(`flow.shadowLayers ${frusta.length} ${median(layered)} ms`);
}

function cpuFlows(): void {
	let opaque: PassList = PassList.forPhase(Phase.Opaque);
	let alpha: PassList = PassList.forPhase(Phase.Alpha);
	let additive: PassList = PassList.forPhase(Phase.Additive);
	let decal: PassList = PassList.forPhase(Phase.Decal);
	let toneMapped: PassList = PassList.forPhase(Phase.DecalAfterToneMap);
	const camera: Vec<float32> = cameraValues;
	const viewProj: Mat4 = {
		m11: camera[0], m12: camera[1], m13: camera[2], m14: camera[3],
		m21: camera[4], m22: camera[5], m23: camera[6], m24: camera[7],
		m31: camera[8], m32: camera[9], m33: camera[10], m34: camera[11],
		m41: camera[12], m42: camera[13], m43: camera[14], m44: camera[15],
	};
	const frustum: Frustum3D = Frustum3D.fromMatrix(viewProj);
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
		const _culled: int32 = collectVisible(opaque, alpha, additive, decal, toneMapped, items,
			context.materials, context.meshData, frustum);
		const t3: float64 = performance.now();
		if (frame == 0) { continue; }
		refreshed.push(t1 - t0);
		lit.push(t2 - t1);
		collected.push(t3 - t2);
	}
	console.log(`flow.items ${items.length}`);
	console.log(`flow.refresh ${median(refreshed)} ms`);
	console.log(`flow.collectLights ${median(lit)} ms`);
	console.log(`flow.collectVisible ${median(collected)} ms`);
	let moved: Vec<float64> = [];
	for (let frame = 0; frame <= frames; frame++) {
		for (const mover of movers) {
			setLocal(scene, mover, Transform3D.fromTranslation(vec3(0.0, frame as float32, 0.0)));
		}
		const t0: float64 = performance.now();
		const _drawn: int32 = refresh(scene, items);
		const t1: float64 = performance.now();
		if (frame > 0) { moved.push(t1 - t0); }
	}
	console.log(`flow.refreshMoving ${movers.length} ${median(moved)} ms`);
	if (env.get("FLOW_CUBES_SORT") == "1") {
		sortFlow(opaque, alpha, additive, decal, toneMapped, frustum);
	}
	if (env.get("FLOW_CUBES_SHADOW") == "1") { shadowFlow(); }
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
