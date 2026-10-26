import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3, scaling, translation } from "../../src/math/math3d";
import { RenderState, FilterMode, Wrap } from "../../src/gpu/state";
import { MeshData, MeshError, Rgba, addQuad, addTexturedQuad } from "../../src/void3d/meshData";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { TextureData, TextureId, TextureUploadError } from "../../src/void3d/texture";
import {
	Program, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH, UNLIT_MATERIAL_COLOR,
	DECAL_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MaterialError, MeshUploadError,
	addMeshData, addMaterial, addTexture, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { DecalOverlay, DecalError, decalBlock } from "../../src/void3d/decal";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH, renderFrame,
} from "../../src/void3d/forwardRenderer";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const WORLD_PER_TEXEL: float32 = 0.02;
const TOLERANCE: float32 = 3.0;
const BACK: float32 = 0.4;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const RED: Rgba = { red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0 };
const BACKDROP_Z: float32 = -1.0;
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + UNLIT_MATERIAL_UNIFORM_LENGTH + DECAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer = makeForward();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;

// Each stage's box: its centre's z, its depth, and the fade its backdrop pixel takes.
struct Stage {
	centerZ: float32;
	depth: float32;
	fade: float32;
	name: string;
}

const STAGES: Vec<Stage> = [
	{ centerZ: BACKDROP_Z, depth: 4.0, fade: 1.0, name: "camera outside the box" },
	{ centerZ: BACKDROP_Z, depth: 12.0, fade: 1.0, name: "camera inside the box" },
	{ centerZ: -1.5, depth: 4.0, fade: 0.75, name: "backdrop off the box's centre" },
];

function fail(message: string): void {
	console.log(`FAIL decal: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, GREY);
	if (made.ok) { return made.value; }
	unreachable;
}

function upload(data: MeshData): MeshId {
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

function unitQuad(): MeshId {
	let data: MeshData = MeshData.withUvs();
	const built: Result<int32, MeshError> = addTexturedQuad(
		data, vec3(-0.5, -0.5, 0.0), vec3(0.5, -0.5, 0.0), vec3(0.5, 0.5, 0.0),
		vec3(-0.5, 0.5, 0.0), vec3(0.0, 0.0, 1.0), WHITE,
	);
	if (!built.ok) { unreachable; }
	return upload(data);
}

function face(ref data: MeshData, a: Vec3, b: Vec3, c: Vec3, d: Vec3, normal: Vec3): void {
	if (!addQuad(data, a, b, c, d, normal, WHITE).ok) { unreachable; }
}

// h3d.prim.Cube centred: the unit box a decal's world scales, every face wound outward.
function unitBox(): MeshId {
	let data: MeshData = MeshData.empty();
	const lo: float32 = -0.5;
	const hi: float32 = 0.5;
	face(data, vec3(lo, lo, hi), vec3(hi, lo, hi), vec3(hi, hi, hi), vec3(lo, hi, hi),
		vec3(0.0, 0.0, 1.0));
	face(data, vec3(hi, lo, lo), vec3(lo, lo, lo), vec3(lo, hi, lo), vec3(hi, hi, lo),
		vec3(0.0, 0.0, -1.0));
	face(data, vec3(hi, lo, hi), vec3(hi, lo, lo), vec3(hi, hi, lo), vec3(hi, hi, hi),
		vec3(1.0, 0.0, 0.0));
	face(data, vec3(lo, lo, lo), vec3(lo, lo, hi), vec3(lo, hi, hi), vec3(lo, hi, lo),
		vec3(-1.0, 0.0, 0.0));
	face(data, vec3(lo, hi, hi), vec3(hi, hi, hi), vec3(hi, hi, lo), vec3(lo, hi, lo),
		vec3(0.0, 1.0, 0.0));
	face(data, vec3(lo, lo, lo), vec3(hi, lo, lo), vec3(hi, lo, hi), vec3(lo, lo, hi),
		vec3(0.0, -1.0, 0.0));
	return upload(data);
}

function white(): TextureId {
	const data: TextureData = {
		pixels: [0xFFFFFFFF], width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

function reserved(length: int32, values: Readonly<Span<float32>>): UniformBlock {
	const block: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, length);
	if (!block.ok) { unreachable; }
	if (!writeUniforms(context, block.value, values).ok) { unreachable; }
	return block.value;
}

function added(material: Material): MaterialId {
	const id: Result<MaterialId, MaterialError> = addMaterial(context, material);
	if (id.ok) { return id.value; }
	fail(`a material was refused: ${id.error.toString()}`);
	unreachable;
}

function backdrop(texture: TextureId): MaterialId {
	let values: Vec<float32> = new Array(UNLIT_MATERIAL_UNIFORM_LENGTH);
	for (let i = 0; i < 4; i++) { values[UNLIT_MATERIAL_COLOR + i] = i == 3 ? 1.0 : BACK; }
	return added({
		...Material.plain(Program.UnlitTextured, RenderState.defaults(), Phase.Opaque),
		texture: texture, uniforms: reserved(UNLIT_MATERIAL_UNIFORM_LENGTH, values),
	});
}

function decal(texture: TextureId): MaterialId {
	const block: Result<Vec<float32>, DecalError> =
		decalBlock({ ...DecalOverlay.defaults(), color: RED });
	if (!block.ok) { unreachable; }
	return added({
		...Material.decal(), texture: texture,
		uniforms: reserved(DECAL_UNIFORM_LENGTH, block.value),
	});
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	const texture: TextureId = white();
	items.push({
		mesh: unitQuad(), material: backdrop(texture),
		world: scaling(8.0, 8.0, 1.0) * translation(0.0, 0.0, BACKDROP_Z), order: 0,
	});
	items.push({
		mesh: unitBox(), material: decal(texture), world: scaling(1.0, 1.0, 1.0), order: 0,
	});
}

function viewOf(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 0.0, 4.0), yaw: 0.0, pitch: 0.0,
		nearPlane: 0.1, farPlane: 20.0,
		projection: {
			kind: ProjectionKind.Orthographic, worldPerTexel: WORLD_PER_TEXEL, snap: false,
		},
	};
	const view: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	unreachable;
}

function channel(x: int32, y: int32, shift: int64): float32 {
	return ((voidCapturePixel(0, x, y) >> shift) & 255) as float32;
}

function expectAt(x: int32, y: int32, red: float32, green: float32, what: string): void {
	const gotRed: float32 = channel(x, y, 24);
	const gotGreen: float32 = channel(x, y, 16);
	if (Math.abs(gotRed - red) > TOLERANCE || Math.abs(gotGreen - green) > TOLERANCE) {
		fail(`${what} at (${x}, ${y}) drew red ${gotRed} green ${gotGreen}, ` +
			`not ${red} and ${green}`);
	}
}

// The box spans two world units across, 100 texels about the centre; the backdrop is the same
// grey everywhere, so the pixel outside the box gives the byte the decal blends over.
function check(at: Stage): void {
	const back: float32 = channel(20, 20, 16);
	if (back < 20.0) { fail(`the backdrop drew ${back}, too dark to see a blend over`); }
	expectAt(20, 20, back, back, "outside the box");
	expectAt(WIDTH / 2 + 60, HEIGHT / 2, back, back, "beside the box");
	const red: float32 = 255.0 * at.fade + back * (1.0 - at.fade);
	const green: float32 = back * (1.0 - at.fade);
	expectAt(WIDTH / 2, HEIGHT / 2, red, green, "the box's centre");
	expectAt(WIDTH / 2 - 45, HEIGHT / 2 + 45, red, green, "the box's corner");
	console.log(`decal: ${at.name}: backdrop ${back}, inside red ${channel(160, 120, 24)} ` +
		`(want ${red})`);
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	const at: Stage = STAGES[stage];
	items[1] = {
		...items[1], world: scaling(2.0, 2.0, at.depth) * translation(0.0, 0.0, at.centerZ),
	};
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	const drawn: Result<int32, ForwardError> =
		renderFrame(forward, items, cameraValues, lights, WIDTH, HEIGHT);
	if (!drawn.ok) { fail(`forward refused: ${drawn.error.toString()}`); }
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	check(at);
	stage = stage + 1;
	if (stage < (STAGES.length as int32)) { return; }
	console.log("PASS decal: the box tints the backdrop under it from outside and inside, " +
		"fades by the depth it reads, and leaves the rest alone");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
