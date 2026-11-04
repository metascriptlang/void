when (!voidDummy && !voidVulkan && !voidGlCore && (macos || windows)) {
	import {
		PixelFormat, doorSetup, doorShutdown, doorSubmitFrame, doorReadTexture,
	} from "../../src/gpu/doorGpu";
	import { RenderTarget } from "../../src/gpu/target";
	import {
		Texture, fromPixels, close as closeTexture,
	} from "../../src/gpu/texture";
	import { BlendMode } from "../../src/gpu/state";
	import {
		setup2d, begin2d, drawSpriteAffine,
		prepare as prepareContext, drawTarget as drawContextTarget,
	} from "../../src/void2d/draw";
	import { currentContext } from "../../src/void2d/displayList";
	import {
		void2dFrameEnd, void2dReleaseList,
	} from "../../src/void2d/batcher";
	import { Scene2D } from "../../src/void2d/node";
	import {
		create, close, add, prepare, drawTarget, isDirty,
	} from "../../src/void2d/scene";
	import { rgba, tile, identity2d } from "../../src/void2d/types";

	when (macos) {
		import { metalSystemDevice } from "../../src/test/metalDevice.h";
		@compile("../../src/test/metalDevice.m");
	} else {
		import {
			warpDevice, warpContext, warpRelease,
		} from "../../src/test/d3d11Warp.h";
		@passL("-ld3d11");
	}

	const WIDTH: int32 = 16;
	const HEIGHT: int32 = 10;
	const CLEAR = rgba(0.0, 0.0, 0.0, 1.0);

	function checkPixel(
		bytes: Readonly<Span<uint8>>,
		stage: string,
		x: int32,
		y: int32,
		red: int32,
		green: int32,
		blue: int32,
	): void {
		const at = (y * WIDTH + x) * 4;
		const r = bytes[at] as int32;
		const g = bytes[at + 1] as int32;
		const b = bytes[at + 2] as int32;
		const a = bytes[at + 3] as int32;
		const sample = `${stage} (${x},${y}) RGBA=${r},${g},${b},${a}`;
		console.log(`PIXEL ${sample} expected=${red},${green},${blue},255`);
		if (Math.abs(r - red) > 1 || Math.abs(g - green) > 1 ||
			Math.abs(b - blue) > 1 || a != 255) {
			throw new Error(`PIXEL mismatch: ${sample}`);
		}
	}

	function readSubmitted(target: RenderTarget, stage: string): Vec<uint8> {
		doorSubmitFrame();
		void2dFrameEnd();
		let bytes: Vec<uint8> = new Array(WIDTH * HEIGHT * 4);
		if (doorReadTexture(target.image, 0, 0, WIDTH, HEIGHT, bytes) != 1) {
			throw new Error(`READBACK failed: ${stage}`);
		}
		return bytes;
	}

	function paint(
		scene: Scene2D, target: RenderTarget, stage: string,
	): Vec<uint8> {
		scene.prepare(WIDTH as float32, HEIGHT as float32, 1.0);
		scene.drawTarget(target);
		return readSubmitted(target, stage);
	}

	function checkAba(bytes: Readonly<Span<uint8>>, stage: string): void {
		checkPixel(bytes, stage, 2, 3, 128, 0, 0);
		checkPixel(bytes, stage, 6, 3, 160, 64, 0);
		checkPixel(bytes, stage, 4, 3, 64, 128, 0);
		checkPixel(bytes, stage, 0, 3, 0, 0, 0);
	}

	function run(): void {
		defer { when (windows) { warpRelease(); } }
		when (macos) {
			const device = metalSystemDevice();
			if (device == null) { throw new Error("Metal device unavailable"); }
			doorSetup(device, null, 2, 0, 1);
		} else {
			const device = warpDevice();
			const context = warpContext();
			if (device == null || context == null) {
				throw new Error("D3D11 WARP device unavailable");
			}
			doorSetup(device, context, 2, 0, 1);
		}
		defer doorShutdown();
		setup2d();
		const redPixels: Vec<uint32> = [0xFF0000FF];
		const greenPixels: Vec<uint32> = [0xFF00FF00];
		const madeRed = Texture.fromPixels(redPixels, 1, 1, false);
		if (!madeRed.ok) { throw new Error("Red texture refused"); }
		const red = madeRed.value;
		defer closeTexture(red);
		const madeGreen = Texture.fromPixels(greenPixels, 1, 1, false);
		if (!madeGreen.ok) { throw new Error("Green texture refused"); }
		const green = madeGreen.value;
		defer closeTexture(green);
		if (red.image == green.image || red.view == green.view) {
			throw new Error("Distinct textures aliased");
		}
		const target = RenderTarget.allocate(
			WIDTH, HEIGHT, PixelFormat.Rgba8, false,
		);
		defer target.close();
		begin2d(WIDTH as float32, HEIGHT as float32, 1.0);
		const immediate = currentContext();
		defer void2dReleaseList(immediate.id);
		const views: Vec<uint32> = [red.view, green.view, red.view];
		for (let i: int32 = 0; i < 3; i++) {
			drawSpriteAffine(
				views[i], false, BlendMode.Alpha, identity2d(),
				(1 + i * 2) as float32, 1.0, 6.0, 6.0,
				0.0, 0.0, 1.0, 1.0,
				rgba(1.0, 1.0, 1.0, 0.5),
			);
		}
		prepareContext(immediate);
		drawContextTarget(immediate, target, CLEAR);
		const direct = readSubmitted(target, "immediate");
		checkAba(direct, "immediate");
		checkPixel(direct, "immediate", 10, 3, 128, 0, 0);

		const scene = Scene2D.create(CLEAR);
		defer scene.close();
		const mask = scene.mask(10.0, 10.0);
		scene.add(mask);
		const first = scene.sprite(tile(red, 6.0, 6.0))
			.at(1.0, 1.0).setAlpha(0.5);
		const middle = scene.sprite(tile(green, 6.0, 6.0))
			.at(3.0, 1.0).setAlpha(0.5);
		const last = scene.sprite(tile(red, 6.0, 6.0))
			.at(5.0, 1.0).setAlpha(0.5);
		mask.addChild(first);
		mask.addChild(middle);
		mask.addChild(last);
		const initial = paint(scene, target, "retained-initial");
		checkAba(initial, "retained-initial");
		checkPixel(initial, "retained-initial", 10, 3, 0, 0, 0);
		if (scene.isDirty()) { throw new Error("Prepared scene stayed dirty"); }
		const replay = paint(scene, target, "retained-clean");
		checkAba(replay, "retained-clean");
		for (let i: int32 = 0; i < initial.length; i++) {
			if (initial[i] != replay[i]) {
				throw new Error(`PIXEL mismatch: retained-clean byte ${i}`);
			}
		}
		console.log("PASS retained-clean: all 640 bytes identical");

		last.setAlpha(0.25);
		const sparse = paint(scene, target, "retained-alpha");
		checkPixel(sparse, "retained-alpha", 6, 3, 112, 96, 0);
		checkPixel(sparse, "retained-alpha", 4, 3, 64, 128, 0);
		checkPixel(sparse, "retained-alpha", 10, 3, 0, 0, 0);

		middle.setTile(tile(red, 6.0, 6.0));
		last.setAlpha(0.5);
		const topology = paint(scene, target, "retained-topology");
		checkPixel(topology, "retained-topology", 6, 3, 224, 0, 0);
		checkPixel(topology, "retained-topology", 4, 3, 191, 0, 0);
		checkPixel(topology, "retained-topology", 10, 3, 0, 0, 0);

		mask.setSize(6.0, 10.0);
		const clipped = paint(scene, target, "retained-clip");
		checkPixel(clipped, "retained-clip", 5, 3, 224, 0, 0);
		checkPixel(clipped, "retained-clip", 6, 3, 0, 0, 0);
		console.log("PASS alternating sprites: sampled ABA, replay, alpha, " +
			"topology and clip");
	}

	run();
} else {
	throw new Error("alternatingSprites requires native Metal or D3D11 WARP");
}
