// Void's counterpart of Bevy's many_cubes stress test run with `--benchmark` (docs/VOID3D.md
// "Bevy comparison bench"): the same layouts, cube count, white material, light and camera
// step, and frame_time lines in the format of Bevy's LogDiagnosticsPlugin, so one reader parses
// both logs (scripts/frameTime.sh). BENCH_CUBES_LAYOUT is sphere (default), cube or dense;
// BENCH_CUBES_COUNT the cube count; BENCH_CUBES_SECONDS how many lines to print before exiting.

import { env, exit } from "std/process";
import { FrameTimeLog, positiveEnv, startFrameTimeLog, tick } from "./frameTimeLog";
import {
	Mat4, Quat, Vec3, vec3, identity, quatBetween, quatOfRotation, rotationX, rotationZ,
	identityQuat,
} from "../../src/math/math3d";
import { gfxSetup, fbWidth, fbHeight } from "../../src/host/gpu";
import { PresentMode, setPresentMode } from "../../src/host/window";
import { RenderState } from "../../src/gpu/state";
import { MeshData, MeshError, Rgba, addQuad } from "../../src/void3d/meshData";
import { Material, Phase, UniformBlock, pbrBlock } from "../../src/void3d/material";
import { PbrResponseError } from "../../src/void3d/pbrResponse";
import {
	Program, ProgramKey, MATERIAL_UNIFORM_SLOT, PBR_MATERIAL_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MaterialError, MeshUploadError,
	addMeshData, addMaterial, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { setCameraPosition } from "../../src/void3d/renderer";
import {
	Scene3D, NodeId3D, SceneError, Transform3D, LightInstance, LightKind, LightError,
	addMeshNode, addLightNode, refresh, collectLights,
} from "../../src/void3d/scene";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH, renderFrame,
} from "../../src/void3d/forwardRenderer";

@include("../../src/host/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

// many_cubes.rs: a 1920x1080 window at scale factor 1, Bevy's default 4x MSAA.
const WIDTH: int32 = 1920;
const HEIGHT: int32 = 1080;
const SAMPLES: int32 = 4;
// WIDTH and HEIGHT of many_cubes.rs, which size the sphere and the cube layout.
const LAYOUT_WIDTH: float64 = 200.0;
const LAYOUT_HEIGHT: float64 = 200.0;
// Bevy draws the one mesh's half size from a seeded rng in [0.25, 0.75]; the centre stands in
// until that value is read from a Bevy run.
const HALF_SIZE: float32 = 0.5;
// --benchmark: the camera turns by 0.15 rad per second at a fixed 1/60 s step.
const CAMERA_STEP: float32 = 0.15 / 60.0;
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };

enum Layout {
	Sphere,
	Cube,
	Dense,
}

let context: DrawContext =
	DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH + 2 * PBR_MATERIAL_UNIFORM_LENGTH);
let forward: ForwardRenderer = makeForward();
let scene: Scene3D = Scene3D.create(context);
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let layout: Layout = layoutOf(env.get("BENCH_CUBES_LAYOUT"));
let cameraRotation: Mat4 = identity();
let cameraPosition: Vec3 = vec3(0.0, 0.0, 0.0);
let frameLog: FrameTimeLog = startFrameTimeLog(1);

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, { x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	if (made.ok) { return made.value; }
	unreachable;
}

function layoutOf(name: string): Layout {
	if (name == "" || name == "sphere") { return Layout.Sphere; }
	if (name == "cube") { return Layout.Cube; }
	if (name == "dense") { return Layout.Dense; }
	console.log(`BENCH_CUBES_LAYOUT must be sphere, cube or dense, got ${name}`);
	unreachable;
}

// Bevy's Cuboid: six faces of four vertices, each with its own normal, 24 vertices, 36 indices.
function cuboid(half: Vec3): MeshId {
	let data: MeshData = MeshData.empty();
	const faces: Vec<Vec3> = [
		vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, -1.0), vec3(0.0, 1.0, 0.0),
		vec3(-1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0),
		vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, -1.0),
		vec3(0.0, -1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0),
		vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0),
		vec3(0.0, 0.0, -1.0), vec3(-1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0),
	];
	for (let f = 0; f < 6; f++) {
		const n: Vec3 = faces[f * 3];
		const u: Vec3 = faces[f * 3 + 1];
		const v: Vec3 = faces[f * 3 + 2];
		const c: Vec3 = vec3(n.x * half.x, n.y * half.y, n.z * half.z);
		const du: Vec3 = vec3(u.x * half.x, u.y * half.y, u.z * half.z);
		const dv: Vec3 = vec3(v.x * half.x, v.y * half.y, v.z * half.z);
		const built: Result<int32, MeshError> = addQuad(
			data, c - du - dv, c + du - dv, c + du + dv, c - du + dv, n, WHITE,
		);
		if (!built.ok) { unreachable; }
	}
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

// StandardMaterial::from(Color::WHITE): metallic 0, perceptual roughness 0.5.
function whiteMaterial(): MaterialId {
	const key: ProgramKey = ProgramKey.of(Program.Lit).withPbr();
	const values: Result<Vec<float32>, PbrResponseError> =
		pbrBlock(key, { metalness: 0.0, roughness: 0.5, occlusion: 1.0 });
	if (!values.ok) { unreachable; }
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, PBR_MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	if (!writeUniforms(context, reserved.value, values.value).ok) { unreachable; }
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.keyed(key, RenderState.defaults(), Phase.Opaque),
		uniforms: reserved.value,
	});
	if (added.ok) { return added.value; }
	unreachable;
}

// Transform::looking_at(target, Vec3::Y): -Z faces the target, +X is up crossed with +Z.
function lookingAt(eye: Vec3, target: Vec3): Mat4 {
	const back: Vec3 = (eye - target).normalized();
	const across: Vec3 = vec3(0.0, 1.0, 0.0).cross(back);
	if (across.lengthSquared() == 0.0) {
		return { ...identity(), m41: eye.x, m42: eye.y, m43: eye.z };
	}
	const right: Vec3 = across.normalized();
	const up: Vec3 = back.cross(right);
	return {
		m11: right.x, m12: right.y, m13: right.z, m14: 0.0,
		m21: up.x, m22: up.y, m23: up.z, m24: 0.0,
		m31: back.x, m32: back.y, m33: back.z, m34: 0.0,
		m41: eye.x, m42: eye.y, m43: eye.z, m44: 1.0,
	};
}

function placed(position: Vec3, rotation: Quat, scale: float32): Transform3D {
	return { position: position, rotation: rotation, scale: vec3(scale, scale, scale) };
}

function addCube(mesh: MeshId, material: MaterialId, local: Transform3D): void {
	const added: Result<NodeId3D, SceneError> =
		addMeshNode(scene, scene.rootId(), local, mesh, material);
	if (!added.ok) {
		console.log(`benchCubes: a cube was refused, ${added.error.toString()}`);
		unreachable;
	}
}

// many_cubes.rs Layout::Sphere: a Fibonacci spiral on a sphere of radius WIDTH * 2.5, each cube
// looking at the centre, inside an inverted box of side radius * 2.2.
function sphereLayout(count: int32, mesh: MeshId, material: MaterialId): void {
	const radius: float64 = LAYOUT_WIDTH * 2.5;
	const golden: float64 = 0.5 * (1.0 + Math.sqrt(5.0));
	const epsilon: float64 = 0.36;
	for (let i = 0; i < count; i++) {
		const at: float64 = i as float64;
		const theta: float64 = Math.PI * 2.0 * (at / golden);
		const phi: float64 = Math.acos(
			1.0 - 2.0 * (at + epsilon) / ((count as float64) - 1.0 + 2.0 * epsilon),
		);
		const p: Vec3 = vec3(
			(radius * Math.cos(theta) * Math.sin(phi)) as float32,
			(radius * Math.sin(theta) * Math.sin(phi)) as float32,
			(radius * Math.cos(phi)) as float32,
		);
		addCube(mesh, material, placed(p, quatOfRotation(lookingAt(p, vec3(0.0, 0.0, 0.0))), 1.0));
	}
	const side: float32 = (radius * 2.2) as float32;
	addCube(cuboid(vec3(side * 0.5, side * 0.5, side * 0.5)), whiteMaterial(),
		placed(vec3(0.0, 0.0, 0.0), identityQuat(), -1.0));
}

// many_cubes.rs Layout::Cube: three walls and a floor of cubes 2.5 apart with a gap every tenth
// row and column, the camera at their centre inside an inverted box.
function cubeLayout(count: int32, mesh: MeshId, material: MaterialId): void {
	const scale: float32 = 2.5;
	const factor: float64 = (5.0 / 9.0) * Math.sqrt(count as float64) /
		(Math.sqrt(LAYOUT_HEIGHT) * Math.sqrt(LAYOUT_WIDTH));
	const dx: int32 = Math.ceil(LAYOUT_WIDTH * factor) as int32;
	const dy: int32 = Math.ceil(LAYOUT_HEIGHT * factor) as int32;
	for (let x = 0; x < dx; x++) {
		for (let y = 0; y < dy; y++) {
			if (x % 10 == 0 || y % 10 == 0) { continue; }
			const fx: float32 = (x as float32) * scale;
			const fy: float32 = (y as float32) * scale;
			const top: float32 = (dy as float32) * scale;
			addCube(mesh, material, placed(vec3(fx, fy, 0.0), identityQuat(), 1.0));
			addCube(mesh, material, placed(vec3(fx, top, fy), identityQuat(), 1.0));
			addCube(mesh, material, placed(vec3(fx, 0.0, fy), identityQuat(), 1.0));
			addCube(mesh, material, placed(vec3(0.0, fx, fy), identityQuat(), 1.0));
		}
	}
	cameraPosition = vec3(
		0.5 * scale * (dx as float32), 0.5 * scale * (dy as float32), 0.5 * scale * (dx as float32),
	);
	addCube(cuboid(vec3(1.1 * cameraPosition.x, 1.1 * cameraPosition.y, 1.1 * cameraPosition.z)),
		whiteMaterial(), placed(cameraPosition, identityQuat(), -1.0));
}

// many_cubes.rs Layout::Dense: a cube root of the count on a side, 1.25 apart, the camera fixed.
function denseLayout(count: int32, mesh: MeshId, material: MaterialId): void {
	const size: float32 = Math.round(Math.cbrt(count as float64)) as float32;
	const gap: float32 = 1.25;
	for (let i = 0; i < count; i++) {
		const at: float32 = i as float32;
		const x: float32 = at % size;
		const y: float32 = (at / size) % size;
		const z: float32 = at / (size * size);
		addCube(mesh, material, placed(vec3(x * gap, y * gap, z * gap), identityQuat(), 1.0));
	}
	const fixed: Mat4 = lookingAt(vec3(100.0, 90.0, 100.0), vec3(0.0, -10.0, 0.0));
	cameraRotation = { ...fixed, m41: 0.0, m42: 0.0, m43: 0.0 };
	cameraPosition = vec3(100.0, 90.0, 100.0);
}

function init(): void {
	gfxSetup();
	const count: int32 = positiveEnv("BENCH_CUBES_COUNT", 1600000);
	const mesh: MeshId = cuboid(vec3(HALF_SIZE, HALF_SIZE, HALF_SIZE));
	const material: MaterialId = whiteMaterial();
	match (layout) {
		Layout.Sphere => sphereLayout(count, mesh, material),
		Layout.Cube => cubeLayout(count, mesh, material),
		Layout.Dense => denseLayout(count, mesh, material),
	};
	// DirectionalLight, no shadows, Transform::IDENTITY.looking_at((0, -1, -1), Vec3::Y).
	const sun: LightInstance = {
		kind: LightKind.Directional, color: vec3(1.0, 1.0, 1.0),
		radius: 0.0, power: 1.0, priority: 0,
	};
	const _sun: NodeId3D = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(),
		rotation: quatBetween(vec3(0.0, 0.0, 1.0), vec3(0.0, -1.0, -1.0).normalized()),
	}, sun);
	console.log(`cubes.instances ${count}`);
	frameLog = startFrameTimeLog(positiveEnv("BENCH_CUBES_SECONDS", 30));
}

function cameraView(): CameraView {
	const world: Mat4 = {
		...cameraRotation, m41: cameraPosition.x, m42: cameraPosition.y, m43: cameraPosition.z,
	};
	const request: Camera3D = {
		position: cameraPosition, yaw: 0.0, pitch: 0.0, orientation: null,
		nearPlane: 0.1, farPlane: 1000.0,
		projection: { kind: ProjectionKind.Perspective, fovY: (Math.PI / 4.0) as float32 },
	};
	const camera: Result<Camera3D, CameraError> = Camera3D.fromWorld(world, request);
	if (!camera.ok) { unreachable; }
	const view: Result<CameraView, CameraError> = camera.value.resolve(fbWidth(), fbHeight());
	if (view.ok) { return view.value; }
	unreachable;
}

function frame(): void {
	if (tick(frameLog, performance.now())) {
		console.log(`cubes.frames ${frameLog.frames}`);
		exit(0);
	}
	// move_camera: rotate_z then rotate_x, both about the world axes, by the fixed step.
	if (layout != Layout.Dense) {
		cameraRotation = cameraRotation * rotationZ(CAMERA_STEP) * rotationX(CAMERA_STEP);
	}
	const _drawn: int32 = refresh(scene, items);
	const lit: Result<int32, LightError> = collectLights(scene, lights);
	if (!lit.ok) {
		console.log(`benchCubes: the light was refused, ${lit.error.toString()}`);
		unreachable;
	}
	setCameraPosition(forward.core, cameraPosition);
	cameraView().writeCameraBlock(cameraValues);
	const drawn: Result<int32, ForwardError> =
		renderFrame(forward, items, cameraValues, lights, fbWidth(), fbHeight());
	if (!drawn.ok) {
		console.log(`benchCubes: the frame was refused, ${drawn.error.toString()}`);
		unreachable;
	}
}

setPresentMode(PresentMode.AutoNoVsync);
voidRunConfigured(WIDTH, HEIGHT, SAMPLES, 0, init, frame);
