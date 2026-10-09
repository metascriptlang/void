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
import { BloomSettings, BloomCompositeMode } from "../../src/void3d/bloom";
import {
	ForwardRenderer, ForwardError, FORWARD_HDR_UNIFORM_LENGTH, renderFrame as renderForward,
	setBloom as bloomForward,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer, PixelArtError, PixelArtSettings, PixelArtLook, PIXEL_ART_HDR_UNIFORM_LENGTH,
	renderFrame as renderPixelArt, setBloom as bloomPixelArt,
} from "../../src/void3d/pixelArtRenderer";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureEnvInt, voidCaptureExit,
	voidCaptureSlotsDiffer,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const WORLD_PER_TEXEL: float32 = 0.02;
const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
// Four additive layers of white: a square of linear 4 at the centre, 8 texels across.
const BRIGHT_LAYERS: int32 = 4;
// An opaque square of linear 0.5, 40 texels across, that no curve clips.
const PATCH: float32 = 0.5;
const TOP: float32 = 0.9;
const TOP_ALPHA: float32 = 0.5;
const RADII: Vec<int32> = [8, 16, 32, 64];

enum Scene {
	Bright,
	Patch,
	Edge,
}

let pixelArt: boolean = voidCaptureEnvInt("VOID_BLOOM_PIXEL_ART", 0) != 0;
let context: DrawContext = DrawContext.withUniformCapacity(
	2 * (pixelArt ? PIXEL_ART_HDR_UNIFORM_LENGTH : FORWARD_HDR_UNIFORM_LENGTH) +
		4 * UNLIT_MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer | null = null;
let preset: PixelArtRenderer | null = null;
let edgeForward: ForwardRenderer | null = null;
let edgePreset: PixelArtRenderer | null = null;
let bright: Vec<DrawItem> = [];
let patch: Vec<DrawItem> = [];
let edge: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;
let patchEnergy: float64 = 0.0;
let edgeWithout: int32 = 0;

function fail(message: string): void {
	const which: string = pixelArt ? "pixel-art" : "forward";
	console.log(`FAIL bloom: ${which} stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function lookOn(background: Vec4): PixelArtLook {
	return {
		background: background,
		outline: {
			depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35,
		},
		fog: { start: 1.0, end: 1.0, strength: 0.0, color: BLACK },
		saturation: 0.0,
	};
}

function makePresets(): void {
	const settings: PixelArtSettings = {
		...PixelArtSettings.full(), lowResShortSide: HEIGHT, postPass: false,
	};
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.createHdr(context, settings, lookOn(BLACK));
	if (!made.ok) { fail(`createHdr refused: ${made.error.toString()}`); }
	if (made.ok) { preset = made.value; }
	const clear: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.createHdr(context, settings, lookOn(CLEAR));
	if (clear.ok) { edgePreset = clear.value; }
}

function makeForwards(): void {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.createHdr(context, BLACK);
	if (!made.ok) { fail(`createHdr refused: ${made.error.toString()}`); }
	if (made.ok) { forward = made.value; }
	const clear: Result<ForwardRenderer, ForwardError> = ForwardRenderer.createHdr(context, CLEAR);
	if (clear.ok) { edgeForward = clear.value; }
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
	if (pixelArt) { makePresets(); } else { makeForwards(); }
	const quad: MeshId = unitQuad();
	const texture: TextureId = white();
	const opaque: RenderState = RenderState.defaults();
	const added: RenderState =
		opaque.withBlendMode(BlendMode.Add).withDepth(false, Compare.LessEqual);
	const glow: MaterialId = unlit(texture, 1.0, 1.0, added, Phase.Additive);
	for (let i = 0; i < BRIGHT_LAYERS; i++) {
		bright.push({
			mesh: quad, material: glow,
			world: translation(0.0, 0.0, 0.1 * (i as float32)) * scaling(0.16, 0.16, 1.0), order: 0,
		});
	}
	patch.push({
		mesh: quad, material: unlit(texture, linearToSrgb(PATCH), 1.0, opaque, Phase.Opaque),
		world: scaling(0.8, 0.8, 1.0), order: 0,
	});
	const over: RenderState = opaque.withBlendMode(BlendMode.Alpha);
	edge.push({
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

function green(x: int32, y: int32, slot: int32 = 0): int32 {
	const pixel: int64 = voidCapturePixel(slot, x, y);
	if (pixel < 0) { fail(`capture slot ${slot} has no pixel at (${x}, ${y})`); }
	return ((pixel >> 16) & 255) as int32;
}

// The frame's light in linear units: every pixel's green decoded and summed.
function energy(): float64 {
	let sum: float64 = 0.0;
	for (let y = 0; y < HEIGHT; y++) {
		for (let x = 0; x < WIDTH; x++) {
			sum = sum + (srgbToLinear((green(x, y) as float32) / 255.0) as float64);
		}
	}
	return sum;
}

function setOn(settings: BloomSettings | null, onEdge: boolean): void {
	const art: PixelArtRenderer | null = onEdge ? edgePreset : preset;
	const fwd: ForwardRenderer | null = onEdge ? edgeForward : forward;
	if (art !== null) { bloomPixelArt(art, settings); }
	if (fwd !== null) { bloomForward(fwd, settings); }
}

function draw(scene: Scene, slot: int32): void {
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	const onEdge: boolean = scene == Scene.Edge;
	const items: Vec<DrawItem> = match (scene) {
		Scene.Bright => bright,
		Scene.Patch => patch,
		Scene.Edge => edge,
	};
	const art: PixelArtRenderer | null = onEdge ? edgePreset : preset;
	const fwd: ForwardRenderer | null = onEdge ? edgeForward : forward;
	if (art !== null) {
		const done: Result<int32, PixelArtError> =
			renderPixelArt(art, items, cameraValues, lights, SCREEN);
		if (!done.ok) { fail(`pixel-art refused: ${done.error.toString()}`); }
	} else if (fwd !== null) {
		const done: Result<int32, ForwardError> =
			renderForward(fwd, items, cameraValues, lights, WIDTH, HEIGHT);
		if (!done.ok) { fail(`forward refused: ${done.error.toString()}`); }
	} else {
		fail("no preset");
	}
	if (voidCaptureGrab(slot) == 0) { fail("readback failed"); }
}

// A bright square spreads light that falls off with distance, the same on every side.
function checkFalloff(): void {
	const cx: int32 = WIDTH / 2;
	const cy: int32 = HEIGHT / 2;
	let previous: int32 = 256;
	for (const r of RADII) {
		const right: int32 = green(cx + r, cy);
		const left: int32 = green(WIDTH - 1 - (cx + r), cy);
		const up: int32 = green(cx, HEIGHT - 1 - (cy + r));
		const down: int32 = green(cx, cy + r);
		console.log(`bloom: radius ${r}: right ${right} left ${left} up ${up} down ${down}`);
		const high: int32 = Math.max(Math.max(right, left), Math.max(up, down)) as int32;
		const low: int32 = Math.min(Math.min(right, left), Math.min(up, down)) as int32;
		if (high - low > 3) { fail(`radius ${r} is not symmetric: ${low} to ${high}`); }
		if (high > previous) { fail(`radius ${r} reads ${high}, above the nearer ${previous}`); }
		previous = high;
	}
	if (green(cx + RADII[1], cy) == 0) { fail(`no light reached ${RADII[1]} texels out`); }
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	const natural: BloomSettings = BloomSettings.natural();
	const additive: BloomSettings = { ...natural, compositeMode: BloomCompositeMode.Additive };
	if (stage == 0) {
		draw(Scene.Bright, 1);
		if (green(WIDTH / 2 + RADII[1], HEIGHT / 2, 1) != 0) { fail("light outside the square, off"); }
	} else if (stage == 1) {
		setOn(natural, false);
		draw(Scene.Bright, 0);
		checkFalloff();
	} else if (stage == 2) {
		setOn(null, false);
		draw(Scene.Bright, 0);
		if (voidCaptureSlotsDiffer() != 0) { fail("bloom set off again draws another frame"); }
	} else if (stage == 3) {
		draw(Scene.Patch, 0);
		patchEnergy = energy();
	} else if (stage == 4) {
		setOn(natural, false);
		draw(Scene.Patch, 0);
		const conserved: float64 = energy();
		console.log(`bloom: patch energy ${patchEnergy} off, ${conserved} energy conserving`);
		if (conserved > patchEnergy * 1.05 || conserved < patchEnergy * 0.85) {
			fail(`energy conserving bloom moved the light from ${patchEnergy} to ${conserved}`);
		}
	} else if (stage == 5) {
		setOn(additive, false);
		draw(Scene.Patch, 0);
		const added: float64 = energy();
		console.log(`bloom: patch energy ${patchEnergy} off, ${added} additive`);
		if (added < patchEnergy * 1.1) { fail(`additive bloom added no light: ${added}`); }
	} else if (stage == 6) {
		draw(Scene.Edge, 0);
		edgeWithout = green(WIDTH / 2, HEIGHT / 2);
	} else {
		setOn(natural, true);
		draw(Scene.Edge, 0);
		const inside: int32 = green(WIDTH / 2, HEIGHT / 2);
		const outside: int32 = green(WIDTH / 2 + 60, HEIGHT / 2);
		console.log(`bloom: edge ${edgeWithout} off, ${inside} on; outside the layer ${outside}`);
		if (outside != 0) { fail(`the transparent clear took light: ${outside}`); }
		if (Math.abs(inside - edgeWithout) > 12) {
			fail(`the half-transparent layer moved from ${edgeWithout} to ${inside}`);
		}
		console.log("PASS bloom: falloff, energy conserving and additive totals, " +
			"off byte-identical, a transparent target's alpha kept");
		voidCaptureExit(0);
	}
	stage = stage + 1;
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
