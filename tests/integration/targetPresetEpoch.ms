import { gfxSetup } from "../../src/sokol/gpu";
import {
	contextGeneration, imageAlive, viewAlive, liveImages, liveViews, destroyImage,
	destroyView, endPass, commit,
} from "../../src/gpu/door";
import { RenderTarget, beginScreenPass } from "../../src/gpu/target";
import { Vec4 } from "../../src/math/math3d";
import { DrawContext, DrawItem } from "../../src/void3d/draw";
import { VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH } from "../../src/void3d/gpu3d";
import {
	ForwardRenderer, FORWARD_UNIFORM_LENGTH, prepareFrame as prepareForward,
	drawToScreen as drawForward, closeForward,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer, PixelArtSettings, PixelArtLook, PIXEL_ART_UNIFORM_LENGTH,
	prepareFrame as preparePixelArt, drawToScreen as drawPixelArt, closePixelArt,
} from "../../src/void3d/pixelArtRenderer";
import { LowResView } from "../../src/void3d/blit";
import { voidCaptureBackend, voidCaptureExit } from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

struct Storage {
	owner: RenderTarget;
	image: uint32;
	attachment: uint32;
	texture: uint32;
}

const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const VIEW: LowResView = { width: 16, height: 12, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const items: Vec<DrawItem> = [];
let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let forward: ForwardRenderer = null as unknown as ForwardRenderer;
let pixel: PixelArtRenderer = null as unknown as PixelArtRenderer;
let held: Vec<Storage> = [];
let stage: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL target preset epoch: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function init(): void {
	gfxSetup();
	camera[0] = 1.0;
	camera[5] = 1.0;
	camera[10] = 1.0;
	camera[15] = 1.0;
	const f = ForwardRenderer.create(
		DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH), BLACK,
	);
	if (!f.ok) { fail("forward owner could not be created"); }
	if (f.ok) { forward = f.value; }
	const look: PixelArtLook = {
		background: BLACK,
		outline: {
			depthThreshold: 0.006,
			normalThreshold: 0.6,
			depthShade: 0.55,
			normalShade: 0.55,
		},
		fog: { start: 0.5, end: 0.8, strength: 0.0, color: BLACK },
		saturation: 0.0,
	};
	const p = PixelArtRenderer.create(DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH),
		PixelArtSettings.full(), look);
	if (!p.ok) { fail("pixel-art owner could not be created"); }
	if (p.ok) { pixel = p.value; }
}

function keep(owner: RenderTarget): void {
	held.push({
		owner: owner,
		image: owner.image,
		attachment: owner.attachment,
		texture: owner.texture,
	});
}

function prepare(): void {
	const f = prepareForward(forward, items, camera, lights, 16, 12);
	if (!f.ok) { fail(`forward prepare refused ${f.error.toString()}`); }
	const p = preparePixelArt(pixel, items, camera, lights, VIEW);
	if (!p.ok) { fail(`pixel-art prepare refused ${p.error.toString()}`); }
}

function frame(): void {
	const images: int32 = liveImages();
	const views: int32 = liveViews();
	if (stage == 1) {
		for (const storage of held) { storage.owner.generation = contextGeneration() - 1; }
	}
	prepare();
	if (stage == 0) {
		keep(forward.colorTarget);
		keep(forward.depthTarget);
		keep(pixel.colorTarget);
		keep(pixel.normalTarget);
		keep(pixel.depthTarget);
		keep(pixel.postTarget);
	} else {
		let borrowed: int32 = 0;
		for (const storage of held) {
			const owner: RenderTarget = storage.owner;
			if (owner.generation != contextGeneration() || owner.width != 16 ||
				owner.height != 12 ||
				owner.image == storage.image || owner.attachment == storage.attachment ||
				!imageAlive(owner.image) || !viewAlive(owner.attachment) ||
				!imageAlive(storage.image) || !viewAlive(storage.attachment)) {
				fail("same-size epoch adoption retained or destroyed a stale target id");
			}
			borrowed = borrowed + 1;
			if (storage.texture != 0) {
				borrowed = borrowed + 1;
				if (owner.texture == storage.texture || !viewAlive(owner.texture) ||
					!viewAlive(storage.texture)) {
					fail("a sampled preset target retained its stale texture view");
				}
			}
		}
		if (liveImages() != images + (held.length as int32) || liveViews() != views + borrowed) {
			fail("preset adoption retired stale ids or duplicated its new storage");
		}
		if (held[0].owner != forward.colorTarget || held[1].owner != forward.depthTarget ||
			held[2].owner != pixel.colorTarget || held[3].owner != pixel.normalTarget ||
			held[4].owner != pixel.depthTarget || held[5].owner != pixel.postTarget ||
			forward.sceneColors[0].view != forward.colorTarget.attachment ||
			forward.sceneDepth.view != forward.depthTarget.attachment ||
			pixel.sceneColors[0].view != pixel.colorTarget.attachment ||
			pixel.sceneColors[1].view != pixel.normalTarget.attachment ||
			pixel.sceneDepth.view != pixel.depthTarget.attachment ||
			pixel.postColors[0].view != pixel.postTarget.attachment) {
			fail("preset replaced an owner identity or kept old pass attachments");
		}
		for (const storage of held) {
			if (storage.texture != 0) { destroyView(storage.texture); }
			destroyView(storage.attachment);
			destroyImage(storage.image);
		}
		if (liveImages() != images || liveViews() != views) {
			fail("generation-write control cleanup did not restore image/view counts");
		}
	}
	beginScreenPass(BLACK);
	drawForward(forward);
	drawPixelArt(pixel);
	endPass();
	commit();
	stage = stage + 1;
	if (stage < 2) { return; }
	closeForward(forward);
	closePixelArt(pixel);
	for (const storage of held) {
		if (!storage.owner.isClosed()) { fail("preset teardown did not close its target aliases"); }
	}
	console.log("PASS target preset epoch: generation-write control reallocates every same-size " +
		"forward/pixel-art target without destroying stale ids or replacing owner identities");
	voidCaptureExit(0);
}

if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(128, 96, 1, 0, init, frame);
