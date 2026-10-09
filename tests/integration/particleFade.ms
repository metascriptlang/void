import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec4, vec3, identity, srgbToLinear, linearToSrgb } from "../../src/math/math3d";
import { Material, MaterialKind } from "../../src/void3d/material";
import {
	Program, ProgramKey, VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, StreamError, MaterialError,
	addMaterial, addStreamMesh, writeStream,
} from "../../src/void3d/draw";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import {
	ParticleEmitter, EmitterState, SortMode, constant, updateEmitter, writeSortedInstances,
} from "../../src/void3d/particles";
import { LowResView } from "../../src/void3d/blit";
import {
	ForwardRenderer, ForwardError, FORWARD_HDR_UNIFORM_LENGTH,
	renderFrame as renderForward,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer, PixelArtError, PixelArtSettings, PixelArtLook, DepthSource,
	PIXEL_ART_HDR_UNIFORM_LENGTH, renderFrame as renderPixelArt,
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
const BACKGROUND: float32 = 0.2;
const GREY: Vec4 = { x: BACKGROUND, y: BACKGROUND, z: BACKGROUND, w: 1.0 };
const SCREEN: LowResView = { width: WIDTH, height: HEIGHT, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const ALPHAS: Vec<float32> = [0.0, 0.1, 0.25, 0.49, 0.51, 0.75, 1.0, 0.0];
let pixelArt: boolean = voidCaptureEnvInt("VOID_PARTICLE_FADE_PIXEL_ART", 0) != 0;
let hdr: boolean = voidCaptureEnvInt("VOID_PARTICLE_FADE_HDR", 0) != 0;
let control: boolean = voidCaptureEnvInt("VOID_PARTICLE_FADE_CONTROL", 0) != 0;
let post: int32 = voidCaptureEnvInt("VOID_PARTICLE_FADE_POST", 0);
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_HDR_UNIFORM_LENGTH + PIXEL_ART_HDR_UNIFORM_LENGTH,
);
let forward: ForwardRenderer | null = null;
let preset: PixelArtRenderer | null = null;
let streams: Vec<MeshId> = [];
let items: Vec<DrawItem> = [];
let values: Vec<float32> = [0.0, 0.0, 0.0, 0.6, 1.0, 1.0, 1.0, 1.0];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;
let emitter: ParticleEmitter = makeEmitter();
let sortedValues: Vec<float32> = new Array(16);

function makeEmitter(): ParticleEmitter {
	const made = ParticleEmitter.create({
		...EmitterState.defaults(), maxParts: 2, sortMode: SortMode.Sort, life: constant(10.0),
	}, 31);
	if (made.ok) { return made.value; }
	unreachable;
}

function fail(message: string): void {
	console.log(`FAIL particle fade: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function addParticle(material: Material, capacity: int32 = 1): void {
	const added: Result<MaterialId, MaterialError> = addMaterial(context, material);
	const mesh: Result<MeshId, StreamError> = addStreamMesh(context, capacity);
	if (!added.ok || !mesh.ok) { fail("particle setup refused"); }
	if (added.ok && mesh.ok) {
		streams.push(mesh.value);
		items.push({ mesh: mesh.value, material: added.value, world: identity() });
	}
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	if (pixelArt) {
		const settings: PixelArtSettings = {
			...PixelArtSettings.full(), lowResShortSide: HEIGHT, postPass: post != 0,
			palette: post == 2, depthSource: DepthSource.DepthTexture,
		};
		const look: PixelArtLook = {
			background: GREY,
			outline: {
				depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35,
			},
			fog: { start: 1.0, end: 1.0, strength: 0.0, color: GREY }, saturation: 0.0,
		};
		const made: Result<PixelArtRenderer, PixelArtError> = hdr ?
			PixelArtRenderer.createHdr(context, settings, look) :
			PixelArtRenderer.create(context, settings, look);
		if (!made.ok) { fail("pixel-art preset refused"); }
		if (made.ok) { preset = made.value; }
	} else {
		const made: Result<ForwardRenderer, ForwardError> = hdr ?
			ForwardRenderer.createHdr(context, GREY) : ForwardRenderer.create(context, GREY);
		if (!made.ok) { fail("forward preset refused"); }
		if (made.ok) { forward = made.value; }
	}
	const cut: Material = Material.ofKind(Program.Particle, MaterialKind.AlphaKill);
	const alpha: Material = Material.ofKind(Program.Particle, MaterialKind.Alpha);
	const faded: Material = control ?
		{ ...alpha, program: ProgramKey.of(Program.Particle).withCutout() } : alpha;
	addParticle(cut);
	addParticle(faded);
	addParticle(faded);
	addParticle(Material.ofKind(Program.Particle, MaterialKind.Opaque));
	addParticle(cut);
	addParticle(faded, 2);
	emitter.emitCount = 2.0;
	if (!updateEmitter(emitter, 0.0, identity()).ok || emitter.count != 2) {
		fail("sorted emitter setup refused");
	}
	for (let i = 0; i < 2; i++) {
		emitter.particles[i].position = vec3(0.0, 1.2, i == 0 ? 1.0 : 0.0);
		emitter.particles[i].size = 0.6;
		emitter.particles[i].red = i == 0 ? 1.0 : 0.0;
		emitter.particles[i].green = i == 0 ? 0.0 : 1.0;
		emitter.particles[i].blue = 0.0;
		emitter.particles[i].alpha = 0.5;
	}
}

function viewOf(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 0.0, 4.0), yaw: 0.0, pitch: 0.0,
		nearPlane: 0.1, farPlane: 10.0,
		projection: { kind: ProjectionKind.Orthographic, worldPerTexel: 0.02, snap: false },
	};
	const view: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	unreachable;
}

function write(index: int32, x: float32, z: float32, grey: float32, alpha: float32): void {
	values[0] = x;
	values[2] = z;
	values[4] = grey;
	values[5] = grey;
	values[6] = grey;
	values[7] = alpha;
	if (!writeStream(context, streams[index], values, 1).ok) { fail("stream write refused"); }
}

function channel(
	view: CameraView, x: float32, y: float32 = 0.0, shift: int64 = 16,
): int32 {
	const point = view.project(vec3(x, y, 0.0), SCREEN, true);
	const pixel: int64 = voidCapturePixel(0, point.x as int32, point.y as int32);
	if (pixel < 0) { fail("readback pixel missing"); }
	return ((pixel >> shift) & 255) as int32;
}

function green(view: CameraView, x: float32): int32 { return channel(view, x); }

function shownByte(value: float32): int32 {
	const shown: float32 = pixelArt && post == 2 ?
		(Math.round(value * 15.0) as float32) / 15.0 : value;
	return Math.round(shown * 255.0) as int32;
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("framebuffer size changed"); }
	const alpha: float32 = ALPHAS[stage];
	write(0, -2.1, 0.0, 1.0, 0.25);
	write(1, -0.7, 0.0, 1.0, alpha);
	write(2, 0.7, 0.0, 1.0, alpha);
	write(3, 0.7, 1.0, BACKGROUND, 1.0);
	write(4, 2.1, 0.0, 1.0, 0.75);
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	const sorted = writeSortedInstances(emitter, identity(), view.viewProj, sortedValues);
	if (!sorted.ok) { fail("sorted emitter write refused"); }
	if (sorted.ok && !writeStream(context, streams[5], sortedValues, sorted.value).ok) {
		fail("sorted stream refused");
	}
	const art: PixelArtRenderer | null = preset;
	const fwd: ForwardRenderer | null = forward;
	if (art !== null) {
		const done: Result<int32, PixelArtError> =
			renderPixelArt(art, items, cameraValues, lights, SCREEN);
		if (!done.ok) { fail(`pixel-art refused: ${done.error.toString()}`); }
	}
	if (fwd !== null) {
		const done: Result<int32, ForwardError> =
			renderForward(fwd, items, cameraValues, lights, WIDTH, HEIGHT);
		if (!done.ok) { fail(`forward refused: ${done.error.toString()}`); }
	}
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	const base: int32 = Math.round(BACKGROUND * 255.0) as int32;
	const mixed: float32 = hdr ?
		linearToSrgb(alpha + srgbToLinear(BACKGROUND) * (1.0 - alpha)) :
		alpha + BACKGROUND * (1.0 - alpha);
	const wanted: int32 = shownByte(mixed);
	const got: int32 = green(view, -0.7);
	console.log(`particle fade: alpha ${alpha}, green ${got}, expected ${wanted}`);
	if (Math.abs(got - wanted) > 2) { fail("alpha did not blend continuously"); }
	if (Math.abs(green(view, -2.1) - base) > 2) { fail("quarter-alpha cutout did not cut"); }
	if (Math.abs(green(view, 0.7) - base) > 2) { fail("particle ignored opaque depth"); }
	if (!hdr && green(view, 2.1) != 255) { fail("three-quarter cutout was not kept"); }
	const floor: float32 = (hdr ? srgbToLinear(BACKGROUND) : BACKGROUND) * 0.25;
	const red: float32 = hdr ? linearToSrgb(0.5 + floor) : 0.5 + floor;
	const sortedGreen: float32 = hdr ? linearToSrgb(0.25 + floor) : 0.25 + floor;
	if (Math.abs(channel(view, 0.0, 1.2, 24) - shownByte(red)) > 2 ||
		Math.abs(channel(view, 0.0, 1.2, 16) - shownByte(sortedGreen)) > 2) {
		fail("per-emitter back-to-front colors did not blend in order");
	}
	stage = stage + 1;
	if (stage < ALPHAS.length) { return; }
	console.log("PASS particle fade: intermediate alpha across half, zero/off, explicit cutout, " +
		"opaque depth occludes, HDR blends in linear light");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
