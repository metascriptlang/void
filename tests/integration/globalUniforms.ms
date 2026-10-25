import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3 } from "../../src/math/math3d";
import { FilterMode, Wrap, Face } from "../../src/gpu/state";
import { Material, MaterialKind, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addTexturedQuad } from "../../src/void3d/meshData";
import { TextureData, TextureId, TextureUploadError } from "../../src/void3d/texture";
import {
	Program, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MeshUploadError, MaterialError,
	addMeshData, addMaterial, addTexture, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, LightError, addMeshNode, refresh, collectLights,
} from "../../src/void3d/scene";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH, renderFrame as renderForward,
} from "../../src/void3d/forwardRenderer";
import {
	doorFrameStat,
	DOOR_STAT_UNIFORM_APPLIES,
	DOOR_STAT_UNIFORM_RING_BYTES,
	DOOR_STAT_PIPELINE_CHANGES,
} from "../../src/gpu/doorGpu.ms";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

// Two rows of eight quads. The top row is one pipeline. The bottom row alternates two pipelines
// (the second turns culling off) through a layer per quad, so no sort can group them. Each stage
// draws a prefix of one row; the stats of its frame are read in the next frame, and what a
// stage adds over the stage before it, per quad, is what a draw costs.
const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const HALF: float32 = 0.3;
const SPACING: float32 = 0.7;
const ROW: int32 = 8;
const SAME_Y: float32 = 0.8;
const ALTERNATING_Y: float32 = -0.8;
const WORLD_PER_TEXEL: float32 = 0.02;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const RED: Vec4 = { x: 1.0, y: 0.0, z: 0.0, w: 1.0 };
const GREEN: Vec4 = { x: 0.0, y: 1.0, z: 0.0, w: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + 2 * ROW * UNLIT_MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = -1;
let first: int32 = 0;
let count: int32 = 0;
let applies: Vec<int32> = [];
let changes: Vec<int32> = [];
let ringBytes: Vec<int32> = [];

function fail(message: string): void {
	console.log(`FAIL global uniforms: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, GREY);
	if (made.ok) { return made.value; }
	unreachable;
}

function white(): TextureId {
	const data: TextureData = {
		pixels: [0xFFFFFFFF], width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

function material(color: Vec4, culled: boolean, layer: int32, image: TextureId): MaterialId {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	const values: Vec<float32> = [0.0, 0.0, 0.0, 0.0, color.x, color.y, color.z, color.w];
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	const base: Material = Material.ofKind(Program.UnlitTextured, MaterialKind.Opaque);
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...base,
		pass: culled ? base.pass : base.pass.withCulling(Face.None),
		texture: image,
		uniforms: reserved.value,
		layer: layer,
	});
	if (added.ok) { return added.value; }
	fail(`a material was refused: ${added.error.toString()}`);
	unreachable;
}

function quad(x: float32, y: float32, made: MaterialId): void {
	let mesh: MeshData = MeshData.withUvs();
	const built: Result<int32, MeshError> = addTexturedQuad(
		mesh, vec3(-HALF, -HALF, 0.0), vec3(HALF, -HALF, 0.0),
		vec3(HALF, HALF, 0.0), vec3(-HALF, HALF, 0.0), vec3(0.0, 0.0, 1.0), WHITE,
	);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (!uploaded.ok) { unreachable; }
	const at: Transform3D = Transform3D.fromTranslation(vec3(x, y, 0.0));
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, scene.rootId(), at, uploaded.value, made);
	if (!placed.ok) { unreachable; }
}

function columnX(column: int32): float32 {
	return ((column as float32) - ((ROW - 1) as float32) * 0.5) * SPACING;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	const image: TextureId = white();
	const same: MaterialId = material(RED, true, 0, image);
	for (let i = 0; i < ROW; i++) { quad(columnX(i), SAME_Y, same); }
	for (let i = 0; i < ROW; i++) {
		quad(columnX(i), ALTERNATING_Y, material(i % 2 == 0 ? RED : GREEN, i % 2 == 0, i, image));
	}
}

function viewOf(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 0.0, 4.0), yaw: 0.0, pitch: 0.0,
		nearPlane: 0.1, farPlane: 10.0,
		projection: {
			kind: ProjectionKind.Orthographic, worldPerTexel: WORLD_PER_TEXEL, snap: false,
		},
	};
	const view: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	unreachable;
}

function red(pixel: int64): int64 { return (pixel >> 24) & 255; }
function green(pixel: int64): int64 { return (pixel >> 16) & 255; }

function checkPictures(view: CameraView): void {
	for (let i = 0; i < count; i++) {
		const same: boolean = first == 0;
		const at: Vec3 = view.project(
			vec3(columnX(i), same ? SAME_Y : ALTERNATING_Y, 0.0), SCREEN, true);
		const pixel: int64 = voidCapturePixel(0, at.x as int32, at.y as int32);
		const wantRed: boolean = same || i % 2 == 0;
		if (wantRed ? (red(pixel) != 255 || green(pixel) != 0) :
			(green(pixel) != 255 || red(pixel) != 0)) {
			fail(`quad ${i} of the ${same ? "same" : "alternating"} row drew ${pixel}`);
		}
	}
}

// The second pipeline of the alternating row differs only in culling, so both declare the
// same blocks and a switch must apply every global again.
function report(): void {
	const quads: int32 = 6;
	const sameSlope: int32 = (applies[1] - applies[0]) / quads;
	const alternatingSlope: int32 = (applies[3] - applies[2]) / quads;
	console.log(`global uniforms: applies per added quad ${sameSlope} in one pipeline, ` +
		`${alternatingSlope} alternating; ring bytes ${ringBytes[0]} / ${ringBytes[1]} / ` +
		`${ringBytes[2]} / ${ringBytes[3]}; pipeline changes ${changes[0]} / ${changes[1]} / ` +
		`${changes[2]} / ${changes[3]}`);
	if ((applies[1] - applies[0]) % quads != 0 || (applies[3] - applies[2]) % quads != 0) {
		fail("applies do not grow by a whole number per quad");
	}
	if (sameSlope != 2) {
		fail(`a quad in one pipeline applied ${sameSlope} blocks; its model and material only ` +
			"are two, the globals belong to the pipeline change");
	}
	if (alternatingSlope <= sameSlope) {
		fail(`alternating pipelines applied ${alternatingSlope} blocks per quad, no more than ` +
			`${sameSlope}: a pipeline change must apply the globals again`);
	}
	if (changes[1] != changes[0] || changes[3] - changes[2] != quads) {
		fail("one pipeline changed with its quad count, or the alternating row did not change " +
			"pipeline at every quad");
	}
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	if (stage >= 0) {
		applies.push(doorFrameStat(DOOR_STAT_UNIFORM_APPLIES));
		changes.push(doorFrameStat(DOOR_STAT_PIPELINE_CHANGES));
		ringBytes.push(doorFrameStat(DOOR_STAT_UNIFORM_RING_BYTES));
	}
	if (stage == 3) {
		report();
		console.log("PASS global uniforms: globals apply once per pipeline change");
		voidCaptureExit(0);
		return;
	}
	if (refresh(scene, items) != 2 * ROW) { fail("the scene does not draw its sixteen quads"); }
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { unreachable; }
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	stage = stage + 1;
	first = stage < 2 ? 0 : ROW;
	count = stage % 2 == 0 ? 2 : ROW;
	const drawn: Result<int32, ForwardError> =
		renderForward(forward, items[first..first + count], cameraValues, lights, WIDTH, HEIGHT);
	if (!drawn.ok) { fail(`forward refused: ${drawn.error.toString()}`); }
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	checkPictures(view);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
