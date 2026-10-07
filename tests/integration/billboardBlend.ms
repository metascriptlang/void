import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3, identity } from "../../src/math/math3d";
import { RenderState, BlendMode, Face, FilterMode, Wrap } from "../../src/gpu/state";
import { Sampler } from "../../src/gpu/target";
import { makeTextureView } from "../../src/gpu/door";
import { Rgba } from "../../src/void3d/meshData";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import {
	Program, ProgramKey, BILLBOARD_UNIFORM_SLOT, BILLBOARD_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH, makeImage, makeVertexBuffer,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, GpuMesh, MeshId, MaterialId, MaterialError, MeshUploadError,
	addMesh, addMaterial, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	AtlasTile, BillboardInstance, BILLBOARD_INSTANCE_STRIDE, ANCHOR_CENTER,
} from "../../src/void3d/billboard";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
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
const SIDE: float32 = 1.6;
const STRAIGHT_X: float32 = -1.2;
const BLENDED_X: float32 = 1.2;
const GAP_X: float32 = 0.0;
const WORLD_PER_TEXEL: float32 = 0.02;
const TOLERANCE: int64 = 2;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const FRAMES: int32 = 3;
const QUARTER_BYTE: int64 = 64;
const THREE_QUARTERS_BYTE: int64 = 192;
let pixelArt: boolean = voidCaptureEnvInt("VOID_BILLBOARD_BLEND_PIXEL_ART", 0) != 0;
let control: boolean = voidCaptureEnvInt("VOID_BILLBOARD_BLEND_CONTROL", 0) != 0;
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + 2 * BILLBOARD_UNIFORM_LENGTH,
);
let forward: ForwardRenderer = makeForward();
let preset: PixelArtRenderer = makePreset();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;

function fail(message: string): void {
	const which: string = pixelArt ? "pixel-art" : "forward";
	console.log(`FAIL billboard blend: ${which} stage ${stage}: ${message}`);
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

function halves(): uint32 {
	const pixels: Vec<uint32> = [0x40404040, 0xC0C0C0C0];
	return makeTextureView(makeImage(pixels, 2, 1));
}

function instanceBuffer(x: float32): uint32 {
	const tile: AtlasTile = { u: 0.0, v: 0.0, u2: 1.0, v2: 1.0 };
	const instance: BillboardInstance = {
		position: vec3(x, 0.0, 0.0), width: SIDE, height: SIDE, anchor: ANCHOR_CENTER,
		tile: tile, color: WHITE,
	};
	let values: Vec<float32> = [];
	instance.pushTo(values);
	return makeVertexBuffer(values[0..BILLBOARD_INSTANCE_STRIDE]);
}

function billboard(x: float32, key: ProgramKey, pass: RenderState, phase: Phase): void {
	const values: Vec<float32> = [1.0, 1.0, 1.0, 1.0, 4.0, 0.0, 0.25, 0.0];
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, BILLBOARD_UNIFORM_SLOT, BILLBOARD_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.keyed(key, pass, phase),
		texture0: halves(),
		sampler0: Sampler.create(FilterMode.Nearest, Wrap.Clamp).asHandle(),
		uniforms: reserved.value,
	});
	if (!added.ok) {
		fail(`a billboard material was refused: ${added.error.toString()}`);
		unreachable;
	}
	const mesh: Result<MeshId, MeshUploadError> =
		addMesh(context, GpuMesh.billboards(instanceBuffer(x), 1));
	if (!mesh.ok) { unreachable; }
	items.push({ mesh: mesh.value, material: added.value, world: identity() });
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	const state: RenderState = RenderState.defaults().withCulling(Face.None);
	const blended: RenderState = state.withBlendMode(BlendMode.AlphaAdd);
	const straight: ProgramKey = ProgramKey.of(Program.Billboard);
	billboard(STRAIGHT_X, straight, state, Phase.Opaque);
	const second: ProgramKey = control ? straight : straight.withPremultiplied();
	billboard(BLENDED_X, second, control ? state : blended, control ? Phase.Opaque : Phase.Alpha);
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

function rgbAt(view: CameraView, x: float32): int64 {
	const at: Vec3 = view.project(vec3(x, 0.0, 0.0), SCREEN, true);
	return voidCapturePixel(0, at.x as int32, at.y as int32) >> 8;
}

function channel(rgb: int64, shift: int64): int64 {
	return (rgb >> shift) & 0xFF;
}

function near(got: int64, want: int64): boolean {
	return got >= want - TOLERANCE && got <= want + TOLERANCE;
}

function overBackdrop(backdrop: int64, alphaByte: int64): int64 {
	return alphaByte + (backdrop * (255 - alphaByte) + 127) / 255;
}

function check(view: CameraView): void {
	const backdrop: int64 = rgbAt(view, GAP_X);
	const cutLeft: int64 = rgbAt(view, STRAIGHT_X - SIDE / 4.0);
	const keptRight: int64 = rgbAt(view, STRAIGHT_X + SIDE / 4.0);
	console.log(`billboard blend: backdrop ${backdrop}, cut ${cutLeft}, kept ${keptRight}`);
	if (cutLeft != backdrop) { fail("the straight billboard's quarter-alpha texel was not cut"); }
	if (keptRight != 0xFFFFFF) { fail(`the straight three-quarter texel drew ${keptRight}`); }
	const light: int64 = rgbAt(view, BLENDED_X - SIDE / 4.0);
	const heavy: int64 = rgbAt(view, BLENDED_X + SIDE / 4.0);
	console.log(`billboard blend: premultiplied quarter ${light}, three-quarter ${heavy}`);
	for (const shift of [0, 8, 16]) {
		const base: int64 = channel(backdrop, shift);
		if (!near(channel(light, shift), overBackdrop(base, QUARTER_BYTE))) {
			fail(`the quarter-alpha texel did not blend over the backdrop on channel ${shift}`);
		}
		if (!near(channel(heavy, shift), overBackdrop(base, THREE_QUARTERS_BYTE))) {
			fail(`the three-quarter texel did not blend over the backdrop on channel ${shift}`);
		}
	}
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
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
	check(view);
	stage = stage + 1;
	if (stage < FRAMES) { return; }
	console.log("PASS billboard blend: premultiplied texels blend over the backdrop, straight cut");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
