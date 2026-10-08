import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import {
	Vec4, vec3, scaling, translation, srgbToLinear, linearToSrgb,
} from "../../src/math/math3d";
import { RenderState, BlendMode, Compare, FilterMode, Wrap } from "../../src/gpu/state";
import { MeshData, MeshError, Rgba, addTexturedQuad } from "../../src/void3d/meshData";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { TextureData, TextureId, TextureUploadError } from "../../src/void3d/texture";
import {
	Program, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH, UNLIT_MATERIAL_COLOR,
	VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MaterialError, MeshUploadError,
	addMeshData, addMaterial, addTexture, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { setExposure } from "../../src/void3d/renderer";
import {
	ForwardRenderer, ForwardError, FORWARD_HDR_UNIFORM_LENGTH, renderFrame,
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
const TOLERANCE: int32 = 2;
const BACK: float32 = 0.2;
const TOP: float32 = 0.9;
const TOP_ALPHA: float32 = 0.5;
const GLOW: float32 = 1.0;
const MULTIPLIERS: Vec<float32> = [1.0, 1.5, 0.4];
const GREY: Vec4 = { x: 0.5, y: 0.5, z: 0.5, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_HDR_UNIFORM_LENGTH + 4 * UNLIT_MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer | null = null;
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL hdr: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function unitQuad(): MeshId {
	let data: MeshData = MeshData.withUvs();
	const built: Result<int32, MeshError> = addTexturedQuad(
		data, vec3(-0.5, -0.5, 0.0), vec3(0.5, -0.5, 0.0), vec3(0.5, 0.5, 0.0),
		vec3(-0.5, 0.5, 0.0), vec3(0.0, 0.0, 1.0), WHITE,
	);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, data);
	if (uploaded.ok) { return uploaded.value; }
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

function unlit(
	texture: TextureId,
	grey: float32,
	alpha: float32,
	pass: RenderState,
	phase: Phase,
): MaterialId {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	let values: Vec<float32> = new Array(UNLIT_MATERIAL_UNIFORM_LENGTH);
	values[UNLIT_MATERIAL_COLOR] = grey;
	values[UNLIT_MATERIAL_COLOR + 1] = grey;
	values[UNLIT_MATERIAL_COLOR + 2] = grey;
	values[UNLIT_MATERIAL_COLOR + 3] = alpha;
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.plain(Program.UnlitTextured, pass, phase),
		texture: texture, uniforms: reserved.value,
	});
	if (added.ok) { return added.value; }
	fail(`a material was refused: ${added.error.toString()}`);
	unreachable;
}

// A backdrop, a half-transparent layer over its middle, and two additive layers over its left,
// whose sum is above 1 in linear light.
function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.createHdr(context, GREY);
	if (!made.ok) { fail(`createHdr refused: ${made.error.toString()}`); }
	if (made.ok) { forward = made.value; }
	const quad: MeshId = unitQuad();
	const texture: TextureId = white();
	const opaque: RenderState = RenderState.defaults();
	const over: RenderState = opaque.withBlendMode(BlendMode.Alpha);
	const added: RenderState =
		opaque.withBlendMode(BlendMode.Add).withDepth(false, Compare.LessEqual);
	const glow: MaterialId = unlit(texture, GLOW, 1.0, added, Phase.Additive);
	items.push({
		mesh: quad, material: unlit(texture, BACK, 1.0, opaque, Phase.Opaque),
		world: scaling(10.0, 10.0, 1.0) * translation(0.0, 0.0, -1.0), order: 0,
	});
	items.push({
		mesh: quad, material: unlit(texture, TOP, TOP_ALPHA, over, Phase.Alpha),
		world: scaling(2.0, 2.0, 1.0), order: 0,
	});
	const depths: Vec<float32> = [0.1, 0.2];
	for (const z of depths) {
		items.push({
			mesh: quad, material: glow,
			world: translation(-2.4, 0.0, z), order: 0,
		});
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

// A linear value as the tone map writes it: exposed, saturated and encoded, in 8 bits.
function toneMappedByte(linear: float32, multiplier: float32): float32 {
	let exposed: float32 = linear * multiplier;
	if (exposed > 1.0) { exposed = 1.0; }
	return linearToSrgb(exposed) * 255.0;
}

function near(got: int32, want: float32): boolean {
	return Math.abs((got as float32) - want) <= (TOLERANCE as float32);
}

function green(x: int32, y: int32): int32 {
	return ((voidCapturePixel(0, x, y) >> 16) & 255) as int32;
}

function expect(what: string, got: int32, want: float32, other: float32, otherName: string): void {
	if (!near(got, want)) { fail(`the ${what} drew ${got}, not ${want}`); }
	if (Math.abs(want - other) < 5.0 || near(got, other)) {
		fail(`the ${what} ${got} cannot tell HDR from ${otherName} ${other}`);
	}
}

function check(multiplier: float32): void {
	const back: float32 = srgbToLinear(BACK);
	const top: float32 = srgbToLinear(TOP);
	const glow: float32 = srgbToLinear(GLOW);
	const alone: int32 = green(20, 20);
	const overlap: int32 = green(WIDTH / 2, HEIGHT / 2);
	const lit: int32 = green(WIDTH / 2 - 120, HEIGHT / 2);
	const wantBack: float32 = toneMappedByte(back, multiplier);
	const wantOverlap: float32 =
		toneMappedByte(top * TOP_ALPHA + back * (1.0 - TOP_ALPHA), multiplier);
	const wantLit: float32 = toneMappedByte(back + 2.0 * glow, multiplier);
	console.log(`hdr: x${multiplier} backdrop ${alone} (want ${wantBack}), overlap ${overlap} ` +
		`(want ${wantOverlap}), additive ${lit} (want ${wantLit})`);
	if (!near(alone, wantBack)) { fail(`the backdrop drew ${alone}, not ${wantBack}`); }
	const gammaBlend: float32 =
		toneMappedByte(srgbToLinear(TOP * TOP_ALPHA + BACK * (1.0 - TOP_ALPHA)), multiplier);
	if (multiplier <= 1.0) {
		expect("overlap", overlap, wantOverlap, gammaBlend, "a blend of encoded colours");
	} else if (!near(overlap, wantOverlap)) {
		fail(`the overlap drew ${overlap}, not ${wantOverlap}`);
	}
	if (multiplier < 1.0) {
		const clipped: float32 = toneMappedByte(1.0, multiplier);
		expect("additive sum", lit, wantLit, clipped, "a target clipped at 1");
	} else if (!near(lit, wantLit)) {
		fail(`the additive sum drew ${lit}, not ${wantLit}`);
	}
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	if (forward === null) { fail("no preset"); }
	if (forward !== null) {
		const multiplier: float32 = MULTIPLIERS[stage];
		setExposure(forward.core, Math.log(multiplier) as float32);
		const view: CameraView = viewOf();
		view.writeCameraBlock(cameraValues);
		const drawn: Result<int32, ForwardError> =
			renderFrame(forward, items, cameraValues, lights, WIDTH, HEIGHT);
		if (!drawn.ok) { fail(`forward refused: ${drawn.error.toString()}`); }
		if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
		check(multiplier);
	}
	stage = stage + 1;
	if (stage < (MULTIPLIERS.length as int32)) { return; }
	console.log("PASS hdr: linear blending, exposure over the sum, an additive sum above 1 kept");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
