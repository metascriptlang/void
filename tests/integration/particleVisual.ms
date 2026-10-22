import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3, identity } from "../../src/math/math3d";
import { FilterMode, Wrap } from "../../src/gpu/state";
import {
	Program, VertexLayout, BILLBOARD_UNIFORM_SLOT, BILLBOARD_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import { Material, MaterialKind } from "../../src/void3d/material";
import {
	DrawContext, DrawItem, MeshId, addMaterial, addStreamMesh, writeStream,
	addTexture, releaseTexture, releaseMaterial, releaseMesh,
	reserveUniforms, writeUniforms, closeContext,
} from "../../src/void3d/draw";
import { ParticleSystemAsset, SimulationSpace } from "../../src/particles/asset";
import { constantCurve, linearCurve, curveOf, key, constantColor, rgbaColor } from "../../src/particles/curve";
import {
	ParticleSystem, playSystem, updateSystem, POS_X, POS_Y, POS_Z, AGE, FRAME,
} from "../../src/particles/system";
import { AtlasTile } from "../../src/void3d/billboard";
import { ParticleWriter3D, writeParticles } from "../../src/void3d/particleWriter";
import { Camera3D, CameraView, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import {
	ForwardRenderer, FORWARD_UNIFORM_LENGTH, closeForward, renderFrame as renderForward,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer, PixelArtSettings, PixelArtLook, PIXEL_ART_UNIFORM_LENGTH,
	closePixelArt, renderFrame as renderPixelArt,
} from "../../src/void3d/pixelArtRenderer";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureEnvInt, voidCaptureExit,
	voidCaptureWritePng,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1 };
const SCREEN: LowResView = { width: WIDTH, height: HEIGHT, scale: 1, offsetX: 0, offsetY: 0 };
const ROOT_A: Vec3 = { x: -1.2, y: 0, z: 0 };
const ROOT_B: Vec3 = { x: 1.2, y: 0, z: 0 };
let pixelArt: boolean = voidCaptureEnvInt("VOID_PARTICLE_VISUAL_PIXEL_ART", 0) != 0;
let control: int32 = voidCaptureEnvInt("VOID_PARTICLE_VISUAL_CONTROL", 0);
let context = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + 2 * BILLBOARD_UNIFORM_LENGTH,
);
let forward: ForwardRenderer | null = null;
let pixel: PixelArtRenderer | null = null;
let actorA: ParticleSystem = makeEmitter(true);
let actorB: ParticleSystem = makeEmitter(false);
let writer: ParticleWriter3D = ParticleWriter3D.create();
let frames: Vec<AtlasTile> = [
	{ u: 0, v: 0, u2: 0.5, v2: 1 },
	{ u: 0.5, v: 0, u2: 1, v2: 1 },
];
let streams: Vec<MeshId> = [];
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let valuesA: Vec<float32> = new Array(16);
let valuesB: Vec<float32> = new Array(16);
let stage: int32 = 0;
let failedChecks: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL particle visual: pixelArt=${pixelArt} control=${control} ` +
		`stage=${stage}: ${message}`);
	voidCaptureExit(1);
}

// Actor A is 1.2 wide and 0.9 high (1.2 times a ratio of 1.5 times the 2:1 texel aspect), a
// quarter opaque, turned a quarter turn, on frame 1, anchored at (0.25, -0.5); actor B is 1 wide
// and 0.5 high, opaque, and walks its two frames over its life.
function makeEmitter(first: boolean): ParticleSystem {
	let a = ParticleSystemAsset.defaults();
	a.main.duration = 10.0;
	a.main.maxParticles = 1;
	a.main.startLifetime = constantCurve(1.0);
	a.main.startSpeed = constantCurve(0.0);
	a.main.simulationSpace = SimulationSpace.World;
	a.main.startSize3D = true;
	a.main.startSizeX = constantCurve(first ? 1.2 : 1.0);
	a.main.startSizeY = constantCurve(first ? 0.9 : 0.5);
	a.main.startRotationZ = constantCurve(first && control != 1 ? 1.5707963267948966 : 0.0);
	a.main.startColor = constantColor(rgbaColor(1.0, 1.0, 1.0, first ? 0.25 : 1.0));
	a.shape.enabled = false;
	a.emission.rateOverTime = constantCurve(1000.0);
	a.renderer.pivot = vec3(first ? -0.25 : 0.0, first ? 0.5 : 0.0, 0.0);
	a.textureSheetAnimation.enabled = true;
	a.textureSheetAnimation.numTilesX = 2;
	a.textureSheetAnimation.numTilesY = 1;
	a.textureSheetAnimation.frameOverTime = first ? constantCurve(0.75)
		: curveOf(1.0, linearCurve([key(0.0, 0.0), key(1.0, 1.0)]));
	const made = ParticleSystem.create(a, first ? 19 : 37);
	if (!made.ok) { unreachable; }
	let sys = made.value;
	sys.clock.fixedStep = 1.0 / 60.0;
	return sys;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	if (control < 0 || control > 3) { fail("unknown control"); }
	gfxSetup();
	if (pixelArt) {
		const settings: PixelArtSettings = {
			...PixelArtSettings.full(), lowResShortSide: HEIGHT, postPass: false,
		};
		const look: PixelArtLook = {
			background: GREY,
			outline: {
				depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35,
			},
			fog: { start: 0, end: 1, strength: 0, color: GREY }, saturation: 0,
		};
		const made = PixelArtRenderer.create(context, settings, look);
		if (!made.ok) { fail("pixel-art renderer refused"); }
		if (made.ok) { pixel = made.value; }
	} else {
		const made = ForwardRenderer.create(context, GREY);
		if (!made.ok) { fail("forward renderer refused"); }
		if (made.ok) { forward = made.value; }
	}
	const texels: Vec<uint32> = [0xFF0000FF, 0xFF00FF00, 0xFFFF0000, 0xFF00FFFF];
	const atlas = addTexture(context, {
		pixels: texels, width: 4, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	});
	if (!atlas.ok) { fail("atlas refused"); unreachable; }
	for (let actor = 0; actor < 2; actor++) {
		const block = reserveUniforms(context, BILLBOARD_UNIFORM_SLOT, BILLBOARD_UNIFORM_LENGTH);
		if (!block.ok) { fail("billboard block refused"); unreachable; }
		const uniforms: Vec<float32> = [1, 1, 1, 1, 4, 0, 0.25, 0];
		if (!writeUniforms(context, block.value, uniforms).ok) { fail("uniform write refused"); }
		const material = addMaterial(context, {
			...Material.ofKind(Program.ParticleVisual, MaterialKind.Alpha),
			texture: atlas.value, uniforms: block.value,
		});
		const mesh = addStreamMesh(context, 1, VertexLayout.ParticleVisual);
		if (!material.ok || !mesh.ok) { fail("visual material or stream refused"); }
		if (material.ok && mesh.ok) {
			streams.push(mesh.value);
			items.push({ mesh: mesh.value, material: material.value, world: identity() });
		}
	}
	if (!releaseTexture(context, atlas.value).ok) { fail("atlas caller lease refused"); }
	playSystem(actorA, identity());
	playSystem(actorB, identity());
	if (!updateSystem(actorA, 1.0 / 60.0, identity()).ok
		|| !updateSystem(actorB, 1.0 / 60.0, identity()).ok
		|| actorA.count != 1 || actorB.count != 1) { fail("initial particle update refused"); }
	place(actorA, ROOT_A);
	place(actorB, ROOT_B);
}

function place(ref sys: ParticleSystem, at: Vec3): void {
	const cap: int32 = sys.capacity;
	sys.data[POS_X * cap] = at.x;
	sys.data[POS_Y * cap] = at.y;
	sys.data[POS_Z * cap] = at.z;
}

function viewOf(): CameraView {
	let camera: Camera3D = {
		position: vec3(0, 0, 4), yaw: 0, pitch: 0, nearPlane: 0.1, farPlane: 10,
		projection: { kind: ProjectionKind.Orthographic, worldPerTexel: 0.02, snap: false },
	};
	if (stage == 2) {
		camera.yaw = 0.2;
		camera.projection = { kind: ProjectionKind.Perspective, fovY: 1.0 };
	}
	const made = camera.resolve(WIDTH, HEIGHT);
	if (made.ok) { return made.value; }
	unreachable;
}

function probe(view: CameraView, root: Vec3, x: float32, y: float32): int64 {
	const point = vec3(
		root.x + view.basis.right.x * x + view.basis.up.x * y,
		root.y + view.basis.right.y * x + view.basis.up.y * y,
		root.z + view.basis.right.z * x + view.basis.up.z * y,
	);
	const at = view.project(point, SCREEN, true);
	const rgba = voidCapturePixel(0, at.x as int32, at.y as int32);
	if (rgba < 0) { fail("readback probe missing"); }
	return rgba;
}

function blue(rgba: int64): boolean {
	const red = (rgba >> 24) & 255;
	const green = (rgba >> 16) & 255;
	const value = (rgba >> 8) & 255;
	return value > red + 10 && value > green + 10;
}

function check(view: CameraView): string {
	if (!blue(probe(view, ROOT_A, 0.45, 0.6))) {
		return actorA.data[FRAME * actorA.capacity] != 1 ? "atlas frame texels" : "clockwise rotated texel";
	}
	const lower = probe(view, ROOT_A, 0.45, 0);
	if (((lower >> 24) & 255) <= ((lower >> 8) & 255) + 10
		|| ((lower >> 16) & 255) <= ((lower >> 8) & 255) + 10) { return "lower atlas texel"; }
	const outside = probe(view, ROOT_A, 1.25, 0.3);
	if (((outside >> 24) & 255) != ((outside >> 8) & 255)) { return "pixel aspect bounds"; }
	const second = probe(view, ROOT_B, -0.25, 0);
	if (stage == 0) {
		if (((second >> 24) & 255) <= ((second >> 8) & 255) + 10) { return "second initial frame"; }
	} else if (!blue(second)) { return "second animated frame"; }
	if (actorA.data[FRAME * actorA.capacity] != 1 || actorA.data[AGE * actorA.capacity] > 0.05) {
		return "updating second actor mutated first";
	}
	return "";
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("framebuffer changed"); }
	if (stage == 1 && !updateSystem(actorB, 0.5, identity()).ok) { fail("animation refused"); }
	if (control == 3) { actorA.data[FRAME * actorA.capacity] = 0.0; }
	const view = viewOf();
	view.writeCameraBlock(cameraValues);
	const eye: Vec3 = vec3(0, 0, 4);
	const lookDir: Vec3 = vec3(0, 0, -1);
	const first = writeParticles(writer, actorA, frames, eye, lookDir, valuesA);
	const second = writeParticles(writer, actorB, frames, eye, lookDir, valuesB);
	if (!first.ok || !second.ok) { fail("visual instance write refused"); }
	if (control == 2) { valuesA[4] = valuesA[3] * 1.5; }
	if (!writeStream(context, streams[0], valuesA, 1).ok
		|| !writeStream(context, streams[1], valuesB, 1).ok) { fail("stream upload refused"); }
	const art = pixel;
	const fwd = forward;
	if (art !== null && !renderPixelArt(art, items, cameraValues, lights, SCREEN).ok) {
		fail("pixel-art render refused");
	}
	if (fwd !== null && !renderForward(fwd, items, cameraValues, lights, WIDTH, HEIGHT).ok) {
		fail("forward render refused");
	}
	if (voidCaptureGrab(0) == 0) { fail("capture refused"); }
	if (voidCaptureWritePng(0, `frame${stage}.png`) == 0) { fail("PNG write refused"); }
	const verdict = check(view);
	if (verdict == "") {
		console.log(`PASS particle visual: pixelArt=${pixelArt} stage=${stage}`);
	} else {
		failedChecks = failedChecks + 1;
		console.log(`FAIL particle visual: pixelArt=${pixelArt} stage=${stage}: ${verdict}`);
	}
	stage = stage + 1;
	if (stage == 3) {
		for (const item of items) {
			if (!releaseMaterial(context, item.material).ok
				|| !releaseMesh(context, item.mesh).ok) { fail("actor release refused"); }
		}
		if (art !== null) { closePixelArt(art); }
		if (fwd !== null) { closeForward(fwd); }
		closeContext(context);
		voidCaptureExit(failedChecks == 0 ? 0 : 1);
	}
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
