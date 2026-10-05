import { env } from "std/process";
import { gfxSetup } from "../../src/sokol/gpu";
import { RenderTarget, beginScreenPass } from "../../src/gpu/target";
import {
	PixelFormat, LoadAction, StoreAction, imageAlive, viewAlive, liveImages, liveViews,
	endPass, commit,
	contextGeneration, destroyImage, destroyView,
} from "../../src/gpu/door";
import { Scene2D, NodeRef } from "../../src/void2d/node";
import { create } from "../../src/void2d/scene";
import { setup2d, begin2d, beginTarget } from "../../src/void2d/draw";
import { BlendMode } from "../../src/gpu/state";
import { rgba, tile, targetTile } from "../../src/void2d/types";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

struct Holder { target: RenderTarget; }
const target: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
const independent: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
const held: Holder = { target: target };
const producer: Scene2D = Scene2D.create(rgba(0.0, 1.0, 0.0, 1.0));
const other: Scene2D = Scene2D.create(rgba(0.0, 0.0, 1.0, 1.0));
const display: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
let shown: NodeRef = display.group();
let stage: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL target owner: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function exerciseMisuse(misuse: string): void {
	if (misuse.equals("refused-pool")) {
		let owners: Vec<RenderTarget> = [];
		while (true) { owners.push(RenderTarget.allocate(8, 8, PixelFormat.Rgba8, true)); }
	}
	const victim: RenderTarget = RenderTarget.unallocated(
		misuse.equals("depth") ? PixelFormat.Depth : PixelFormat.Rgba8, false,
	);
	const alias: RenderTarget = victim;
	if (misuse.equals("refused-zero")) {
		victim.resize(0, 8);
		console.log("a refused zero-width resize returned normally");
		voidCaptureExit(0);
	}
	if (!misuse.equals("closed-empty")) { victim.resize(8, 8); }
	victim.close();
	if (misuse.equals("begin-closed")) {
		begin2d(8.0, 8.0, 1.0);
		beginTarget(alias, 8.0, 8.0, 1.0, 0.0, 0.0, rgba(0.0, 0.0, 0.0, 0.0));
	} else if (misuse.equals("closed-empty")) {
		alias.resize(8, 8);
	} else if (misuse.equals("color")) {
		const color = alias.asColor(LoadAction.Clear, { x: 1.0, y: 0.0, z: 0.0, w: 1.0 });
		console.log(`a closed owner lent color attachment ${color.view}`);
	} else if (misuse.equals("depth")) {
		const depth = alias.asDepth(LoadAction.Clear, 1.0, StoreAction.DontCare);
		console.log(`a closed owner lent depth attachment ${depth.view}`);
	} else {
		fail(`unknown terminal owner case ${misuse}`);
	}
	console.log("a closed owner operation returned normally");
	voidCaptureExit(0);
}

function init(): void {
	gfxSetup();
	setup2d();
	const misuse: string = env.get("VOID_TARGET_OWNER_MISUSE");
	if (!misuse.equals("")) { exerciseMisuse(misuse); }
	target.resize(16, 12);
	independent.resize(8, 6);
	producer.add(producer.rect(4.0, 4.0, rgba(1.0, 0.0, 0.0, 1.0)).at(2.0, 2.0));
	shown = display.sprite(targetTile(held.target, 16.0, 12.0).premultiplied())
		.setBlend(BlendMode.None);
	display.add(shown);
}

function frame(): void {
	const oldImage: uint32 = target.image;
	const oldAttachment: uint32 = target.attachment;
	const oldTexture: uint32 = target.texture;
	const images: int32 = liveImages();
	const views: int32 = liveViews();
	if (stage == 1) {
		held.target.resize(32, 24);
		if (held.target != target || target.width != 32 || target.height != 24) {
			fail("resize lost the owner identity through a value holder");
		}
		if (target.image == oldImage || target.attachment == oldAttachment ||
			target.texture == oldTexture || imageAlive(oldImage) ||
			viewAlive(oldAttachment) || viewAlive(oldTexture)) {
			fail("resize retained a destroyed GPU object or failed to replace it");
		}
		if (liveImages() != images || liveViews() != views) {
			fail("resize leaked image or view ownership");
		}
	}
	if (stage == 2) {
		held.target.resize(32, 24);
		if (target.image != oldImage || target.attachment != oldAttachment ||
			target.texture != oldTexture || liveImages() != images || liveViews() != views) {
			fail("same-size resize replaced or duplicated live GPU objects");
		}
	}
	if (stage == 3) {
		target.generation = contextGeneration() - 1;
		held.target.resize(32, 24);
		if (target != held.target || target.generation != contextGeneration() ||
			target.image == oldImage || target.attachment == oldAttachment ||
			target.texture == oldTexture || !imageAlive(oldImage) ||
			!viewAlive(oldAttachment) || !viewAlive(oldTexture) ||
			liveImages() != images + 1 || liveViews() != views + 2) {
			fail("older-epoch adoption destroyed stale ids or failed to allocate");
		}
		destroyView(oldTexture);
		destroyView(oldAttachment);
		destroyImage(oldImage);
		if (liveImages() != images || liveViews() != views) {
			fail("generation-write control cleanup did not restore resource counts");
		}
	}
	if (stage == 4) {
		held.target.close();
		if (!target.isClosed() || !held.target.isClosed() || target.image != 0 ||
			target.attachment != 0 || target.texture != 0 || target.generation != 0) {
			fail("close did not close and clear every alias");
		}
		if (imageAlive(oldImage) || viewAlive(oldAttachment) || viewAlive(oldTexture) ||
			liveImages() != images - 1 || liveViews() != views - 2) {
			fail("terminal close did not retire exactly its image and two views");
		}
		if (independent.isClosed() || !imageAlive(independent.image) ||
			!viewAlive(independent.texture)) {
			fail("close damaged an independent owner");
		}
		other.prepare(8.0, 6.0, 1.0);
		other.drawTarget(independent);
		shown.setTile(targetTile(independent, 8.0, 6.0).premultiplied()).setSize(8.0, 6.0);
	} else {
		producer.prepare(held.target.width as float32, held.target.height as float32, 1.0);
		producer.drawTarget(held.target);
		shown.setTile(targetTile(held.target, held.target.width as float32,
			held.target.height as float32).premultiplied())
			.setSize(held.target.width as float32, held.target.height as float32);
	}
	display.prepare(128.0, 96.0, 1.0);
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	display.drawScreen();
	endPass();
	commit();
	if (voidCaptureGrab(0) == 0) { fail("screen readback failed"); }
	const expected: int64 = stage == 4 ? 0x0000FFFF : 0xFF0000FF;
	if (voidCapturePixel(0, 3, 3) != expected) {
		fail("consumer did not sample the live owner after resize or independent release");
	}
	if (stage != 4 && voidCapturePixel(0, target.width - 2, target.height - 2) != 0x00FF00FF) {
		fail("consumer kept stale target dimensions or attachment contents");
	}
	const width: int32 = stage == 4 ? independent.width : target.width;
	const height: int32 = stage == 4 ? independent.height : target.height;
	if (voidCapturePixel(0, width + 2, height + 2) != 0x000000FF) {
		fail("consumer drew past the live target dimensions");
	}
	stage = stage + 1;
	if (stage < 5) { return; }
	console.log("PASS target owner: stable alias resize, same-size reuse, terminal close, " +
		"exact image/view retirement, independent pixels and generation-write adoption");
	voidCaptureExit(0);
}

if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(128, 96, 1, 0, init, frame);
