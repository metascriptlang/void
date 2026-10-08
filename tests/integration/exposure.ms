import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import {
	Vec4, vec3, scaling, translation, srgbToLinear, linearToSrgb,
} from "../../src/math/math3d";
import { RenderState, BlendMode, FilterMode, Wrap } from "../../src/gpu/state";
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
import { ToneMode, setExposure, setToneMode } from "../../src/void3d/renderer";
import { greyCurve } from "./toneCurves";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH, renderFrame as renderForward,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer, PixelArtError, PixelArtSettings, PixelArtLook, PIXEL_ART_UNIFORM_LENGTH,
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
const EXPOSED: float32 = 1.5;
const GREY: Vec4 = { x: 0.5, y: 0.5, z: 0.5, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
let pixelArt: boolean = voidCaptureEnvInt("VOID_EXPOSURE_PIXEL_ART", 0) != 0;
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + 2 * UNLIT_MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer = makeForward();
let preset: PixelArtRenderer = makePreset();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;

function fail(message: string): void {
	const which: string = pixelArt ? "pixel-art" : "forward";
	console.log(`FAIL exposure: ${which} stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, GREY);
	if (made.ok) { return made.value; }
	unreachable;
}

function makePreset(): PixelArtRenderer {
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
		PixelArtRenderer.create(context, settings, look);
	if (made.ok) { return made.value; }
	unreachable;
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

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	const quad: MeshId = unitQuad();
	const texture: TextureId = white();
	const opaque: RenderState = RenderState.defaults();
	const over: RenderState = opaque.withBlendMode(BlendMode.Alpha);
	items.push({
		mesh: quad, material: unlit(texture, BACK, 1.0, opaque, Phase.Opaque),
		world: scaling(10.0, 10.0, 1.0) * translation(0.0, 0.0, -1.0), order: 0,
	});
	items.push({
		mesh: quad, material: unlit(texture, TOP, TOP_ALPHA, over, Phase.Alpha),
		world: scaling(2.0, 2.0, 1.0), order: 0,
	});
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

// One channel of a grey layer as the scene programs write it: decoded, exposed, through the curve
// and encoded again (toneMap), in 8 bits.
function exposedByte(grey: float32, multiplier: float32, mode: ToneMode): float32 {
	return linearToSrgb(greyCurve(srgbToLinear(grey) * multiplier, mode)) * 255.0;
}

function near(got: int32, want: float32): boolean {
	return Math.abs((got as float32) - want) <= (TOLERANCE as float32);
}

function green(x: int32, y: int32): int32 {
	return ((voidCapturePixel(0, x, y) >> 16) & 255) as int32;
}

function layeredByte(multiplier: float32, mode: ToneMode): float32 {
	const back: float32 = exposedByte(BACK, multiplier, mode);
	return exposedByte(TOP, multiplier, mode) * TOP_ALPHA + back * (1.0 - TOP_ALPHA);
}

function check(multiplier: float32, mode: ToneMode): void {
	const back: float32 = exposedByte(BACK, multiplier, mode);
	const layered: float32 = layeredByte(multiplier, mode);
	const alone: int32 = green(20, 20);
	const overlap: int32 = green(WIDTH / 2, HEIGHT / 2);
	console.log(`exposure: ${mode.toString()} x${multiplier} backdrop ${alone} (want ${back}), ` +
		`overlap ${overlap} (want ${layered})`);
	if (!near(alone, back)) { fail(`the backdrop drew ${alone}, not ${back}`); }
	if (!near(overlap, layered)) { fail(`the overlap drew ${overlap}, not ${layered}`); }
	if (multiplier == 1.0) { return; }
	const unexposed: float32 = TOP * TOP_ALPHA + BACK * (1.0 - TOP_ALPHA);
	const summed: float32 = exposedByte(unexposed, multiplier, mode);
	if (Math.abs(layered - summed) < 5.0 || near(overlap, summed)) {
		fail(`the overlap ${overlap} cannot tell layers clipped one by one from a sum ${summed}`);
	}
	if (mode == ToneMode.Linear) { return; }
	const linear: float32 = layeredByte(multiplier, ToneMode.Linear);
	if (Math.abs(layered - linear) < 5.0 || near(overlap, linear)) {
		const named: string = mode.toString();
		fail(`the overlap ${overlap} cannot tell ${named} from the linear curve's ${linear}`);
	}
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	const multiplier: float32 = stage == 0 ? 1.0 : EXPOSED;
	const mode: ToneMode = stage == 2 ? ToneMode.Reinhard : ToneMode.Linear;
	setExposure(pixelArt ? preset.core : forward.core, Math.log(multiplier) as float32);
	setToneMode(pixelArt ? preset.core : forward.core, mode);
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	if (pixelArt) {
		const drawn: Result<int32, PixelArtError> =
			renderPixelArt(preset, items, cameraValues, lights, SCREEN);
		if (!drawn.ok) { fail(`pixel-art refused: ${drawn.error.toString()}`); }
	} else {
		const drawn: Result<int32, ForwardError> =
			renderForward(forward, items, cameraValues, lights, WIDTH, HEIGHT);
		if (!drawn.ok) { fail(`forward refused: ${drawn.error.toString()}`); }
	}
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	check(multiplier, mode);
	stage = stage + 1;
	if (stage < 3) { return; }
	console.log("PASS exposure: none by default, each layer clipped before it blends, " +
		"and curved per layer by Reinhard");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
