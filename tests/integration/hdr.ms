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
import { LowResView } from "../../src/void3d/blit";
import { Renderer, ToneMode, setExposure, setToneMode } from "../../src/void3d/renderer";
import { greyCurve } from "./toneCurves";
import {
	ForwardRenderer, ForwardError, FORWARD_HDR_UNIFORM_LENGTH, renderFrame as renderForward,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer, PixelArtError, PixelArtSettings, PixelArtLook, PIXEL_ART_HDR_UNIFORM_LENGTH,
	renderFrame as renderPixelArt,
} from "../../src/void3d/pixelArtRenderer";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureEnvInt, voidCaptureExit,
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
const MULTIPLIERS: Vec<float32> = [1.0, 1.5, 0.4, 0.6, 0.6, 0.6];
const MODES: Vec<ToneMode> = [
	ToneMode.Linear, ToneMode.Linear, ToneMode.Linear,
	ToneMode.Reinhard, ToneMode.Filmic, ToneMode.Neutral,
];
const GREY: Vec4 = { x: 0.5, y: 0.5, z: 0.5, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
let pixelArt: boolean = voidCaptureEnvInt("VOID_HDR_PIXEL_ART", 0) != 0;
let context: DrawContext = DrawContext.withUniformCapacity(
	(pixelArt ? PIXEL_ART_HDR_UNIFORM_LENGTH : FORWARD_HDR_UNIFORM_LENGTH) +
		4 * UNLIT_MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer | null = null;
let preset: PixelArtRenderer | null = null;
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;

function fail(message: string): void {
	const which: string = pixelArt ? "pixel-art" : "forward";
	console.log(`FAIL hdr: ${which} stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

// postPass off: the blit reads the tone mapped colour target as it is.
function makePreset(): void {
	const settings: PixelArtSettings = {
		...PixelArtSettings.full(), lowResShortSide: HEIGHT, postPass: false,
	};
	const look: PixelArtLook = {
		background: GREY,
		outline: {
			depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35,
		},
		fog: { start: 1.0, end: 1.0, strength: 0.0, color: GREY },
		saturation: 0.0,
	};
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.createHdr(context, settings, look);
	if (!made.ok) { fail(`createHdr refused: ${made.error.toString()}`); }
	if (made.ok) { preset = made.value; }
}

function makeForward(): void {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.createHdr(context, GREY);
	if (!made.ok) { fail(`createHdr refused: ${made.error.toString()}`); }
	if (made.ok) { forward = made.value; }
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
	if (pixelArt) { makePreset(); } else { makeForward(); }
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

// A linear value as the tone map writes it: exposed, through the curve and encoded, in 8 bits.
function toneMappedByte(linear: float32, multiplier: float32, mode: ToneMode): float32 {
	return linearToSrgb(greyCurve(linear * multiplier, mode)) * 255.0;
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

// The curve's own stage: every region against the Heaps formula, the overlap and the additive sum
// (above 1 in linear light) against the linear curve at the same exposure.
function checkCurve(multiplier: float32, mode: ToneMode): void {
	const back: float32 = srgbToLinear(BACK);
	const layered: float32 = srgbToLinear(TOP) * TOP_ALPHA + back * (1.0 - TOP_ALPHA);
	const summed: float32 = back + 2.0 * srgbToLinear(GLOW);
	const alone: int32 = green(20, 20);
	const overlap: int32 = green(WIDTH / 2, HEIGHT / 2);
	const lit: int32 = green(WIDTH / 2 - 120, HEIGHT / 2);
	const wantBack: float32 = toneMappedByte(back, multiplier, mode);
	console.log(`hdr: ${mode.toString()} x${multiplier} backdrop ${alone} (want ${wantBack}), ` +
		`overlap ${overlap}, additive ${lit}`);
	if (!near(alone, wantBack)) { fail(`the backdrop drew ${alone}, not ${wantBack}`); }
	const curve: string = `the linear curve's`;
	expect("overlap", overlap, toneMappedByte(layered, multiplier, mode),
		toneMappedByte(layered, multiplier, ToneMode.Linear), curve);
	expect("additive sum", lit, toneMappedByte(summed, multiplier, mode),
		toneMappedByte(summed, multiplier, ToneMode.Linear), curve);
}

function check(multiplier: float32): void {
	const back: float32 = srgbToLinear(BACK);
	const top: float32 = srgbToLinear(TOP);
	const glow: float32 = srgbToLinear(GLOW);
	const alone: int32 = green(20, 20);
	const overlap: int32 = green(WIDTH / 2, HEIGHT / 2);
	const lit: int32 = green(WIDTH / 2 - 120, HEIGHT / 2);
	const wantBack: float32 = toneMappedByte(back, multiplier, ToneMode.Linear);
	const wantOverlap: float32 =
		toneMappedByte(top * TOP_ALPHA + back * (1.0 - TOP_ALPHA), multiplier, ToneMode.Linear);
	const wantLit: float32 = toneMappedByte(back + 2.0 * glow, multiplier, ToneMode.Linear);
	console.log(`hdr: x${multiplier} backdrop ${alone} (want ${wantBack}), overlap ${overlap} ` +
		`(want ${wantOverlap}), additive ${lit} (want ${wantLit})`);
	if (!near(alone, wantBack)) { fail(`the backdrop drew ${alone}, not ${wantBack}`); }
	const encodedBlend: float32 = srgbToLinear(TOP * TOP_ALPHA + BACK * (1.0 - TOP_ALPHA));
	const gammaBlend: float32 = toneMappedByte(encodedBlend, multiplier, ToneMode.Linear);
	if (multiplier <= 1.0) {
		expect("overlap", overlap, wantOverlap, gammaBlend, "a blend of encoded colours");
	} else if (!near(overlap, wantOverlap)) {
		fail(`the overlap drew ${overlap}, not ${wantOverlap}`);
	}
	if (multiplier < 1.0) {
		const clipped: float32 = toneMappedByte(1.0, multiplier, ToneMode.Linear);
		expect("additive sum", lit, wantLit, clipped, "a target clipped at 1");
	} else if (!near(lit, wantLit)) {
		fail(`the additive sum drew ${lit}, not ${wantLit}`);
	}
}

function expose(core: Renderer, multiplier: float32, mode: ToneMode): void {
	setExposure(core, Math.log(multiplier) as float32);
	setToneMode(core, mode);
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	const multiplier: float32 = MULTIPLIERS[stage];
	const mode: ToneMode = MODES[stage];
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	const art: PixelArtRenderer | null = preset;
	const fwd: ForwardRenderer | null = forward;
	if (art !== null) {
		expose(art.core, multiplier, mode);
		const drawn: Result<int32, PixelArtError> =
			renderPixelArt(art, items, cameraValues, lights, SCREEN);
		if (!drawn.ok) { fail(`pixel-art refused: ${drawn.error.toString()}`); }
	} else if (fwd !== null) {
		expose(fwd.core, multiplier, mode);
		const drawn: Result<int32, ForwardError> =
			renderForward(fwd, items, cameraValues, lights, WIDTH, HEIGHT);
		if (!drawn.ok) { fail(`forward refused: ${drawn.error.toString()}`); }
	} else {
		fail("no preset");
	}
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	if (mode == ToneMode.Linear) {
		check(multiplier);
	} else {
		checkCurve(multiplier, mode);
	}
	stage = stage + 1;
	if (stage < (MULTIPLIERS.length as int32)) { return; }
	console.log("PASS hdr: linear blending, exposure over the sum, an additive sum above 1 kept, " +
		"Reinhard, Filmic and PBR Neutral as Heaps writes them");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
