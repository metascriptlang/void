import { gfxSetup, fbWidth, fbHeight } from "../../src/host/gpu";
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
	DOOR_STAT_RESIDENT_BUFFER_BYTES,
	DOOR_STAT_RESIDENT_IMAGE_BYTES,
	DOOR_STAT_RESIDENT_TARGET_BYTES,
	doorMakeBuffer,
	doorDestroyBuffer,
	doorMakeImage,
	doorMakeImageMips,
	doorMakeTargetImage,
	doorDestroyImage,
	DOOR_BUFFER_VERTEX,
} from "../../src/gpu/doorGpu.ms";
import { contextGeneration, loseContext, liveBuffers, liveImages } from "../../src/gpu/door";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/host/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

// Three rows of eight quads. The first row is one pipeline. The second alternates two pipelines
// (the second turns culling off) through a layer per quad, so no sort can group them. The third
// alternates the same two in one layer, which a sort by pipeline groups. Each stage draws a prefix
// of one row; the stats of its frame are read in the next frame, and what a stage adds over the
// one before it, per quad, is what a draw costs.
const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const HALF: float32 = 0.3;
const SPACING: float32 = 0.7;
const ROW: int32 = 8;
const SAME_Y: float32 = 1.2;
const ALTERNATING_Y: float32 = 0.0;
const MIXED_Y: float32 = -1.2;
const ROWS: int32 = 3;
const SAME_ROW: int32 = 0;
const ALTERNATING_ROW: int32 = 1;
const MIXED_ROW: int32 = 2;
const WORLD_PER_TEXEL: float32 = 0.02;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const RED: Vec4 = { x: 1.0, y: 0.0, z: 0.0, w: 1.0 };
const GREEN: Vec4 = { x: 0.0, y: 1.0, z: 0.0, w: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + ROWS * ROW * UNLIT_MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = -1;
let firstGeneration: int32 = 0;
let row: int32 = 0;
let count: int32 = 0;
let applies: Vec<int32> = [];
let changes: Vec<int32> = [];
let ringBytes: Vec<int32> = [];

function fail(message: string): void {
	console.log(`FAIL draw frame stats: stage ${stage}: ${message}`);
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
	for (let i = 0; i < ROW; i++) {
		quad(columnX(i), MIXED_Y, material(i % 2 == 0 ? RED : GREEN, i % 2 == 0, 0, image));
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

function rowY(): float32 {
	return row == SAME_ROW ? SAME_Y : (row == ALTERNATING_ROW ? ALTERNATING_Y : MIXED_Y);
}

function checkPictures(view: CameraView): void {
	for (let i = 0; i < count; i++) {
		const at: Vec3 = view.project(vec3(columnX(i), rowY(), 0.0), SCREEN, true);
		const pixel: int64 = voidCapturePixel(0, at.x as int32, at.y as int32);
		const wantRed: boolean = row == SAME_ROW || i % 2 == 0;
		if (wantRed ? (red(pixel) != 255 || green(pixel) != 0) :
			(green(pixel) != 255 || red(pixel) != 0)) {
			fail(`quad ${i} of row ${row} drew ${pixel}`);
		}
	}
}

// The second pipeline of the last two rows differs only in culling, so both declare the same
// blocks and a switch must apply every global again.
function report(): void {
	const quads: int32 = ROW - 2;
	let slopes: Vec<int32> = [];
	let switches: Vec<int32> = [];
	for (let r = 0; r < ROWS; r++) {
		const small: int32 = 2 * r;
		if ((applies[small + 1] - applies[small]) % quads != 0) {
			fail(`applies do not grow by a whole number per quad in row ${r}`);
		}
		slopes.push((applies[small + 1] - applies[small]) / quads);
		switches.push(changes[small + 1] - changes[small]);
	}
	console.log(`draw frame stats: applies per added quad ${slopes[0]} / ${slopes[1]} / ` +
		`${slopes[2]}, pipeline changes per row ${switches[0]} / ${switches[1]} / ${switches[2]}, ` +
		`ring bytes of the full rows ${ringBytes[1]} / ${ringBytes[3]} / ${ringBytes[5]}`);
	if (slopes[SAME_ROW] != 2) {
		fail(`a quad in one pipeline applied ${slopes[SAME_ROW]} blocks; its model and material ` +
			"only are two, the globals belong to the pipeline change");
	}
	if (slopes[ALTERNATING_ROW] <= slopes[SAME_ROW]) {
		fail(`alternating pipelines applied ${slopes[ALTERNATING_ROW]} blocks per quad, no more ` +
			`than ${slopes[SAME_ROW]}: a pipeline change must apply the globals again`);
	}
	if (switches[SAME_ROW] != 0 || switches[ALTERNATING_ROW] != quads) {
		fail("one pipeline changed with its quad count, or the alternating row did not change " +
			"pipeline at every quad");
	}
	if (switches[MIXED_ROW] != 0) {
		fail(`two interleaved pipelines in one layer changed pipeline ${switches[MIXED_ROW]} ` +
			"more times with six more quads; a sort by pipeline groups them");
	}
	if (slopes[MIXED_ROW] != slopes[SAME_ROW]) {
		fail(`the grouped row applied ${slopes[MIXED_ROW]} blocks per added quad, not ` +
			`${slopes[SAME_ROW]}`);
	}
}

const BUFFER_BYTES: int64 = 1000;
const ODD_BUFFER_BYTES: int64 = 6;
const ODD_BUFFER_ALIGNED: int64 = 8;
const IMAGE_BYTES: int64 = 8 * 4 * 4;
const MIP_IMAGE_BYTES: int64 = (4 * 4 + 2 * 2 + 1) * 4;
const TARGET_BYTES: int64 = 16 * 16 * 4;

function expectResident(what: string, stat: int32, want: int64): void {
	if (doorFrameStat(stat) != want) {
		fail(`${what}: resident stat ${stat} is ${doorFrameStat(stat)}, not ${want}`);
	}
}

function pixels(count: int32): Vec<uint32> {
	let made: Vec<uint32> = new Array(0);
	for (let i = 0; i < count; i++) { made.push(0xFF808080 as uint32); }
	return made;
}

// Bytes alive now, whichever the scene already holds: a make raises its stat by its size, two
// buffer sizes and two image kinds, and the destroys return it exactly.
function checkResidentBytes(): void {
	const buffers: int64 = doorFrameStat(DOOR_STAT_RESIDENT_BUFFER_BYTES);
	const images: int64 = doorFrameStat(DOOR_STAT_RESIDENT_IMAGE_BYTES);
	const targets: int64 = doorFrameStat(DOOR_STAT_RESIDENT_TARGET_BYTES);
	const empty: Vec<uint8> = [];
	const buffer: uint32 = doorMakeBuffer(DOOR_BUFFER_VERTEX, empty, BUFFER_BYTES);
	const odd: uint32 = doorMakeBuffer(DOOR_BUFFER_VERTEX, empty, ODD_BUFFER_BYTES);
	const image: uint32 = doorMakeImage(pixels(8 * 4), 8, 4);
	const mips: uint32 = doorMakeImageMips(pixels(21), 4, 4, 3);
	const target: uint32 = doorMakeTargetImage(16, 16, 2);
	expectResident("made", DOOR_STAT_RESIDENT_BUFFER_BYTES, buffers + BUFFER_BYTES + ODD_BUFFER_ALIGNED);
	expectResident("made", DOOR_STAT_RESIDENT_IMAGE_BYTES, images + IMAGE_BYTES + MIP_IMAGE_BYTES);
	expectResident("made", DOOR_STAT_RESIDENT_TARGET_BYTES, targets + TARGET_BYTES);
	doorDestroyBuffer(odd);
	expectResident("odd buffer destroyed", DOOR_STAT_RESIDENT_BUFFER_BYTES, buffers + BUFFER_BYTES);
	doorDestroyBuffer(buffer);
	doorDestroyImage(mips);
	expectResident("mip image destroyed", DOOR_STAT_RESIDENT_IMAGE_BYTES, images + IMAGE_BYTES);
	doorDestroyImage(image);
	doorDestroyImage(target);
	expectResident("destroyed", DOOR_STAT_RESIDENT_BUFFER_BYTES, buffers);
	expectResident("destroyed", DOOR_STAT_RESIDENT_IMAGE_BYTES, images);
	expectResident("destroyed", DOOR_STAT_RESIDENT_TARGET_BYTES, targets);
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	if (stage >= 0) {
		applies.push(doorFrameStat(DOOR_STAT_UNIFORM_APPLIES) as int32);
		changes.push(doorFrameStat(DOOR_STAT_PIPELINE_CHANGES) as int32);
		ringBytes.push(doorFrameStat(DOOR_STAT_UNIFORM_RING_BYTES) as int32);
	}
	if (stage == 5) {
		report();
		checkResidentBytes();
		if (doorFrameStat(DOOR_STAT_RESIDENT_BUFFER_BYTES) == 0 ||
			doorFrameStat(DOOR_STAT_RESIDENT_IMAGE_BYTES) == 0) {
			fail("the scene holds no resident bytes before the loss");
		}
		firstGeneration = contextGeneration();
		stage = 6;
		loseContext();
		return;
	}
	if (stage == 6) {
		if (contextGeneration() != firstGeneration + 1) { fail("the context was not rebuilt"); }
		console.log(`resident after the loss: buffers ${doorFrameStat(DOOR_STAT_RESIDENT_BUFFER_BYTES)}, ` +
			`images ${doorFrameStat(DOOR_STAT_RESIDENT_IMAGE_BYTES)}, targets ${doorFrameStat(DOOR_STAT_RESIDENT_TARGET_BYTES)}`);
		if (liveBuffers() != 0 || liveImages() != 0) { fail("the loss left resources alive"); }
		expectResident("after the loss", DOOR_STAT_RESIDENT_BUFFER_BYTES, 0);
		expectResident("after the loss", DOOR_STAT_RESIDENT_IMAGE_BYTES, 0);
		expectResident("after the loss", DOOR_STAT_RESIDENT_TARGET_BYTES, 0);
		checkResidentBytes();
		console.log("PASS draw frame stats: globals apply once per pipeline change, a sort groups pipelines, resident bytes rise and return exactly across a loss");
		voidCaptureExit(0);
		return;
	}
	if (refresh(scene, items) != ROWS * ROW) { fail("the scene does not draw its quads"); }
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { unreachable; }
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	stage = stage + 1;
	row = stage / 2;
	count = stage % 2 == 0 ? 2 : ROW;
	const drawn: Result<int32, ForwardError> =
		renderForward(forward, items[row * ROW..row * ROW + count], cameraValues, lights, WIDTH, HEIGHT);
	if (!drawn.ok) { fail(`forward refused: ${drawn.error.toString()}`); }
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	checkPictures(view);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
